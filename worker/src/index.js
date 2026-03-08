/**
 * index.js — FixingNation AI Worker
 *
 * Cloudflare Worker that acts as the secure server-side processing layer,
 * replacing Firebase Cloud Functions (which require the Blaze billing plan).
 *
 * Responsibilities:
 *   1. Authenticate every request via a shared secret.
 *   2. Receive raw post data from the Flutter client.
 *   3. Classify the complaint with Gemini 2.0 Flash.
 *   4. Compute severity, rankingScore, and authorityId server-side.
 *   5. Write all computed fields back to Firestore via the REST API.
 *   6. Return the classification result to the client.
 *
 * The Flutter client NEVER computes severity, rankingScore, or authorityId.
 * Those values only enter Firestore from this Worker, preventing manipulation.
 *
 * Required Worker secrets (set with `wrangler secret put <NAME>`):
 *   API_SHARED_SECRET       — random token included by Flutter in every request
 *   GEMINI_API_KEY          — Google AI Studio API key
 *   FIREBASE_SERVICE_ACCOUNT — Firebase service account JSON (as a string)
 *
 * Required Worker var (in wrangler.toml [vars]):
 *   FIREBASE_PROJECT_ID     — Firebase project ID, e.g. "fixingnation-dev"
 *
 * Endpoints:
 *   GET  /health    — liveness probe, no auth required
 *   POST /classify  — main endpoint, auth required
 */

import { classify }              from "./classifier.js";
import { getFirebaseAccessToken } from "./auth.js";
import { patchDocument }         from "./firestore.js";
import { handleTelegramWebhook } from "./telegram.js";
import {
  normalizeCategory,
  SEVERITY_BY_CATEGORY,
  calculateRankingScore,
  getRecencyScore,
  routeAuthority,
  clamp01,
  safeNumber,
} from "./scoring.js";

// ---------------------------------------------------------------------------
// Worker entry point
// ---------------------------------------------------------------------------

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    // Handle CORS preflight for browser/PWA clients.
    if (request.method === "OPTIONS") {
      return corsResponse(null, 204);
    }

    if (url.pathname === "/health" && request.method === "GET") {
      return corsResponse({ ok: true, service: "fixingnation-ai-worker", ts: new Date().toISOString() });
    }

    if (url.pathname === "/classify" && request.method === "POST") {
      return handleClassify(request, env);
    }

    // Telegram bot webhook — no auth header required (Telegram calls this).
    if (url.pathname === "/telegram" && request.method === "POST") {
      return handleTelegramWebhook(request, env);
    }

    return corsResponse({ error: "Not found" }, 404);
  },
};

// ---------------------------------------------------------------------------
// /classify handler
// ---------------------------------------------------------------------------

async function handleClassify(request, env) {
  // ── 1. Authenticate ──────────────────────────────────────────────────────
  //
  // The Flutter client sends:  x-api-secret: <API_SHARED_SECRET>
  const token = request.headers.get("x-api-secret") ?? "";

  if (!env.API_SHARED_SECRET || token !== env.API_SHARED_SECRET) {
    return corsResponse({ error: "Unauthorized" }, 401);
  }

  // ── 2. Parse and validate body ───────────────────────────────────────────
  let body;
  try {
    body = await request.json();
  } catch {
    return corsResponse({ error: "Request body must be valid JSON" }, 400);
  }

  const {
    postId,
    title,
    description,
    city,
    category: hintCategory,
    createdAtMs,
  } = body;

  if (!postId || typeof postId !== "string") {
    return corsResponse({ error: "postId (string) is required" }, 400);
  }
  if (!title || typeof title !== "string" || title.trim().length === 0) {
    return corsResponse({ error: "title (non-empty string) is required" }, 400);
  }
  if (!description || typeof description !== "string" || description.trim().length === 0) {
    return corsResponse({ error: "description (non-empty string) is required" }, 400);
  }

  // ── 3. AI classification ─────────────────────────────────────────────────
  //
  // classify() tries Gemini 2.0 Flash first.
  // If Gemini fails for any reason (network error, API quota, bad JSON),
  // it falls back to the deterministic category→severity map.
  // The Flutter client always receives a valid classification result.
  let aiResult;
  try {
    aiResult = await classify(
      String(title).trim().slice(0, 500),
      String(description).trim().slice(0, 500),
      String(city ?? ""),
      hintCategory,
      env
    );
  } catch (err) {
    // classify() should not throw — it has an internal fallback.
    // This outer catch is a safety net.
    console.error("[handleClassify] classify() threw unexpectedly:", err.message);
    aiResult = {
      category:            normalizeCategory(hintCategory),
      severity:            0.5,
      isSpam:              false,
      isToxic:             false,
      confidence:          0.5,
      reason:              "Classification pipeline error — fallback applied.",
      suggestedDepartment: "local_authority",
      source:              "fallback_error",
    };
  }

  // ── 4. Compute server-authoritative fields ───────────────────────────────
  //
  // These values are computed here and written to Firestore.
  // The Firestore security rules enforce that the Flutter client cannot set
  // these fields on document creation — only the Worker (via service account
  // Admin access) may write them.

  const category = normalizeCategory(aiResult.category ?? hintCategory);

  // Use the AI-provided severity if plausible; fall back to the category map.
  const severity = clamp01(
    safeNumber(aiResult.severity, SEVERITY_BY_CATEGORY[category] ?? 0.5)
  );

  // createdAtMs comes from the client; guard against future/invalid values.
  const safeCreatedAtMs = Math.min(
    safeNumber(createdAtMs, Date.now()),
    Date.now()
  );
  const recency      = getRecencyScore(safeCreatedAtMs);
  const rankingScore = calculateRankingScore({ recency, severity });
  const authorityId  = routeAuthority(String(city ?? ""), category);

  const moderation = {
    status:     aiResult.isSpam || aiResult.isToxic ? "rejected" : "approved",
    reason:     String(aiResult.reason ?? "").slice(0, 200),
    confidence: clamp01(safeNumber(aiResult.confidence, 0.5)),
    source:     String(aiResult.source ?? "unknown"),
  };

  // ── 5. Write to Firestore ────────────────────────────────────────────────
  //
  // The service account has Firebase Admin privileges and therefore bypasses
  // Firestore security rules.  We write only the computed fields using a
  // field mask so the raw fields written by Flutter are not overwritten.

  // top-level `status` transitions:
  //   PENDING_MODERATION → OPEN     (moderation passed)
  //   PENDING_MODERATION → REJECTED (spam or toxic content)
  const postStatus = moderation.status === "rejected" ? "REJECTED" : "OPEN";

  try {
    const accessToken = await getFirebaseAccessToken(env.FIREBASE_SERVICE_ACCOUNT);

    await patchDocument(
      env.FIREBASE_PROJECT_ID,
      accessToken,
      "posts",
      postId,
      {
        status:      postStatus,
        category,
        severity,
        rankingScore,
        authorityId,
        moderation,
        updatedAt:   new Date().toISOString(),
      }
    );
  } catch (err) {
    console.error("[handleClassify] Firestore write failed:", err.message);
    // Return 500 so the Flutter client knows to retry.
    return corsResponse(
      { error: "Failed to persist classification — please retry" },
      500
    );
  }

  // ── 6. Return result to client ───────────────────────────────────────────
  return corsResponse({
    ok:          true,
    postId,
    status:      postStatus,
    category,
    severity,
    rankingScore,
    authorityId,
    moderation,
  });
}

// ---------------------------------------------------------------------------
// CORS helper
// ---------------------------------------------------------------------------

function corsResponse(body, status = 200) {
  const headers = {
    "Content-Type": "application/json",
    "Access-Control-Allow-Origin":  "*",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "x-api-secret, Content-Type",
  };
  return new Response(body ? JSON.stringify(body) : null, { status, headers });
}
