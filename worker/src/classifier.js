/**
 * classifier.js
 *
 * Classifies a civic complaint using Google Gemini 2.0 Flash.
 * Falls back to a deterministic category→severity map when Gemini is
 * unavailable, returns an error status, or produces an unparseable response.
 *
 * No other AI provider is used.
 *
 * Output contract — all fields are always present and type-safe:
 * {
 *   category:            string  — one of SUPPORTED_CATEGORIES
 *   severity:            number  — [0.0, 1.0]
 *   isSpam:              boolean
 *   isToxic:             boolean
 *   confidence:          number  — [0.0, 1.0]
 *   reason:              string  — ≤ 120 chars
 *   suggestedDepartment: string
 *   source:              "gemini_2_flash" | "fallback_deterministic"
 * }
 */

import { normalizeCategory, SEVERITY_BY_CATEGORY, clamp01, safeNumber } from "./scoring.js";

const GEMINI_URL =
  "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent";

// ---------------------------------------------------------------------------
// Prompt
// ---------------------------------------------------------------------------

function buildPrompt(title, description, city) {
  // Inputs are already sliced by the caller (index.js) but slice again here
  // as a defensive measure so this module is safe to call in isolation.
  return `You are a civic issue classifier for Indian cities.
Analyze the complaint and respond ONLY with a single valid JSON object.
No markdown, no code fences, no explanation — raw JSON only.

JSON schema (all fields required):
{
  "category": "road_damage | garbage | electricity | water | safety | corruption | other",
  "severity": <float 0.0 to 1.0>,
  "isSpam": <true|false>,
  "isToxic": <true|false>,
  "confidence": <float 0.0 to 1.0>,
  "reason": "<one sentence, max 120 chars>",
  "suggestedDepartment": "<responsible government department name>"
}

City: ${city || "unknown"}
Title: ${String(title).slice(0, 200)}
Description: ${String(description).slice(0, 400)}`;
}

// ---------------------------------------------------------------------------
// JSON extraction
// ---------------------------------------------------------------------------

/**
 * Extract the first JSON object from a Gemini response string.
 *
 * Gemini occasionally wraps its response in markdown code fences even when
 * instructed not to.  Rather than relying on regex stripping (which breaks on
 * multi-line fences or leading prose), we scan the string for the first `{`
 * and last `}` and attempt to parse that substring.  This handles:
 *   - Clean JSON responses          → parsed directly
 *   - ```json ... ``` wrapped       → first { ... last } extracted
 *   - Leading prose before JSON     → first { ... last } extracted
 */
function extractJson(text) {
  const start = text.indexOf("{");
  const end   = text.lastIndexOf("}");
  if (start === -1 || end === -1 || end <= start) return null;

  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    return null;
  }
}

// ---------------------------------------------------------------------------
// Result normalisation
// ---------------------------------------------------------------------------

/**
 * Coerce a raw parsed object into the guaranteed output contract.
 * Uses safeNumber / clamp01 so any garbage Gemini field is handled safely.
 * normalizeCategory ensures the category is always a valid enum member.
 */
function normaliseResult(raw, source) {
  const category = normalizeCategory(raw.category);
  return {
    category,
    severity:            clamp01(safeNumber(raw.severity, SEVERITY_BY_CATEGORY[category] ?? 0.5)),
    isSpam:              raw.isSpam  === true,
    isToxic:             raw.isToxic === true,
    confidence:          clamp01(safeNumber(raw.confidence, 0.5)),
    reason:              String(raw.reason ?? "").slice(0, 120) || "No reason provided.",
    suggestedDepartment: String(raw.suggestedDepartment ?? "local_authority"),
    source,
  };
}

// ---------------------------------------------------------------------------
// Deterministic fallback
// ---------------------------------------------------------------------------

/**
 * Safe classification result produced without any AI call.
 * Used when Gemini fails or when GEMINI_API_KEY is not configured.
 */
function deterministicFallback(hintCategory) {
  const category = normalizeCategory(hintCategory);
  return {
    category,
    severity:            SEVERITY_BY_CATEGORY[category] ?? 0.5,
    isSpam:              false,
    isToxic:             false,
    confidence:          0.5,
    reason:              "Deterministic fallback — AI classification unavailable.",
    suggestedDepartment: "local_authority",
    source:              "fallback_deterministic",
  };
}

// ---------------------------------------------------------------------------
// Gemini call
// ---------------------------------------------------------------------------

/**
 * POST to Gemini 2.0 Flash and return a normalised classification result.
 * Throws on any network error, non-200 HTTP response, or unparseable reply.
 *
 * Setting responseMimeType to "application/json" instructs Gemini to return
 * raw JSON without wrapping prose.  extractJson() provides a second line of
 * defence if Gemini ignores the instruction.
 */
async function classifyWithGemini(title, description, city, geminiKey) {
  let response;
  try {
    response = await fetch(`${GEMINI_URL}?key=${geminiKey}`, {
      method:  "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          { parts: [{ text: buildPrompt(title, description, city) }] },
        ],
        generationConfig: {
          temperature:      0.1,
          maxOutputTokens:  300,
          responseMimeType: "application/json",
        },
      }),
    });
  } catch (networkErr) {
    throw new Error(`Gemini network error: ${networkErr.message}`);
  }

  if (!response.ok) {
    const detail = await response.text().catch(() => "(unreadable body)");
    throw new Error(`Gemini HTTP ${response.status}: ${detail.slice(0, 300)}`);
  }

  let data;
  try {
    data = await response.json();
  } catch {
    throw new Error("Gemini response body is not valid JSON");
  }

  // Navigate the Gemini response envelope.
  const text = data?.candidates?.[0]?.content?.parts?.[0]?.text;
  if (typeof text !== "string" || text.trim().length === 0) {
    // Check for a prompt block (safety filter).
    const blockReason = data?.promptFeedback?.blockReason;
    if (blockReason) {
      throw new Error(`Gemini blocked the prompt: ${blockReason}`);
    }
    throw new Error("Gemini returned an empty or missing text part");
  }

  const parsed = extractJson(text);
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
    throw new Error(`Gemini text is not a JSON object: ${text.slice(0, 300)}`);
  }

  return normaliseResult(parsed, "gemini_2_flash");
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Classify a civic complaint.  Gemini is the only AI provider.
 * Falls back to deterministic scoring if Gemini is unavailable.
 *
 * This function never throws — errors are caught and logged internally.
 *
 * @param {string}           title
 * @param {string}           description
 * @param {string}           city
 * @param {string|undefined} hintCategory  — optional user-supplied category hint
 * @param {object}           env           — Cloudflare Worker env bindings
 * @returns {Promise<object>}
 */
export async function classify(title, description, city, hintCategory, env) {
  if (!env.GEMINI_API_KEY) {
    console.warn("[classifier] GEMINI_API_KEY not set — using deterministic fallback");
    return deterministicFallback(hintCategory);
  }

  try {
    const result = await classifyWithGemini(title, description, city, env.GEMINI_API_KEY);

    if (result.confidence < 0.4) {
      console.warn(`[classifier] Low confidence (${result.confidence}) — returning result with warning`);
    }

    return result;
  } catch (err) {
    console.error(`[classifier] Gemini failed — using deterministic fallback. Reason: ${err.message}`);
    return deterministicFallback(hintCategory);
  }
}
