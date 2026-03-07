const admin = require("firebase-admin");
const functions = require("firebase-functions");

admin.initializeApp();
const db = admin.firestore();

const CITY_AUTHORITIES = {
  pune: {
    road_damage: "pune_municipal_corporation_roads",
    garbage: "pune_sanitation_department",
    electricity: "mahadiscom_pune",
    water: "pune_water_board",
    safety: "pune_city_police",
    corruption: "maharashtra_anti_corruption_bureau",
    other: "pune_municipal_corporation_general"
  },
  mumbai: {
    road_damage: "bmc_roads",
    garbage: "bmc_solid_waste",
    electricity: "best_mumbai",
    water: "bmc_water_department",
    safety: "mumbai_police",
    corruption: "maharashtra_anti_corruption_bureau",
    other: "bmc_general"
  },
  bangalore: {
    road_damage: "bbmp_roads",
    garbage: "bbmp_solid_waste",
    electricity: "bescom_bangalore",
    water: "bwssb",
    safety: "bangalore_city_police",
    corruption: "karnataka_lokayukta",
    other: "bbmp_general"
  }
};

const SUPPORTED_CATEGORIES = new Set([
  "road_damage",
  "garbage",
  "electricity",
  "water",
  "safety",
  "corruption",
  "other"
]);

const SEVERITY_BY_CATEGORY = {
  road_damage: 0.8,
  garbage: 0.6,
  electricity: 0.7,
  water: 0.7,
  safety: 0.9,
  corruption: 0.95,
  other: 0.5
};

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function safeNumber(value, fallback = 0) {
  const parsed = Number(value);
  if (!Number.isFinite(parsed)) {
    return fallback;
  }

  return parsed;
}

function normalizeNonNegativeInteger(value) {
  return Math.max(0, Math.trunc(safeNumber(value, 0)));
}

function normalizeCategory(value) {
  const normalized = String(value || "other").trim().toLowerCase();
  if (!SUPPORTED_CATEGORIES.has(normalized)) {
    return "other";
  }

  return normalized;
}

function normalizeCreatedAtMillis(createdAt) {
  const millis = createdAt?.toMillis?.();
  const now = Date.now();
  const normalized = safeNumber(millis, now);

  // Guard against invalid/future timestamps impacting ranking recency.
  return Math.min(now, Math.max(0, normalized));
}

function getRecencyScore(createdAtMillis) {
  const ageHours = (Date.now() - safeNumber(createdAtMillis, Date.now())) / (1000 * 60 * 60);
  return clamp01(1 - ageHours / 72);
}

function calculateRankingScore({ proximity = 0.5, engagement = 0, recency = 0.5, severity = 0.5 }) {
  const normalizedProximity = clamp01(safeNumber(proximity, 0.5));
  const normalizedEngagement = clamp01(safeNumber(engagement, 0) / 100);
  const normalizedRecency = clamp01(safeNumber(recency, 0.5));
  const normalizedSeverity = clamp01(safeNumber(severity, 0.5));

  return Number((
    0.35 * normalizedProximity +
    0.30 * normalizedEngagement +
    0.20 * normalizedRecency +
    0.15 * normalizedSeverity
  ).toFixed(4));
}

function routeAuthority(city, category) {
  const cityKey = (city || "").toLowerCase();
  const categoryKey = category || "other";
  const cityMap = CITY_AUTHORITIES[cityKey];
  if (!cityMap) return "unmapped_city_authority";
  return cityMap[categoryKey] || cityMap.other;
}

exports.onPostCreated = functions.firestore.document("posts/{postId}").onCreate(async (snap) => {
  const post = snap.data();
  const category = normalizeCategory(post.category);
  const city = String(post.city || "");

  const moderation = {
    status: "approved",
    reason: "Heuristic baseline moderation",
    confidence: 0.7,
    source: "fallback_local"
  };

  const severity = SEVERITY_BY_CATEGORY[category] || 0.5;
  const createdAtMillis = normalizeCreatedAtMillis(post.createdAt);
  const recency = getRecencyScore(createdAtMillis);
  const engagement = normalizeNonNegativeInteger(post.upvotes) + normalizeNonNegativeInteger(post.commentsCount);

  const rankingScore = calculateRankingScore({
    proximity: 0.5,
    engagement,
    recency,
    severity
  });

  const authorityId = routeAuthority(city, category);

  await snap.ref.set(
    {
      status: post.status || "OPEN",
      moderation,
      severity,
      authorityId,
      rankingScore,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    },
    { merge: true }
  );
});

exports.onCommentCreated = functions.firestore.document("posts/{postId}/comments/{commentId}").onCreate(async (_, ctx) => {
  const postRef = db.collection("posts").doc(ctx.params.postId);
  await db.runTransaction(async (tx) => {
    const postSnap = await tx.get(postRef);
    if (!postSnap.exists) return;

    const post = postSnap.data();
    const commentsCount = normalizeNonNegativeInteger(post.commentsCount) + 1;
    const engagement = normalizeNonNegativeInteger(post.upvotes) + commentsCount;
    const createdAtMillis = normalizeCreatedAtMillis(post.createdAt);
    const recency = getRecencyScore(createdAtMillis);
    const rankingScore = calculateRankingScore({
      proximity: 0.5,
      engagement,
      recency,
      severity: clamp01(safeNumber(post.severity, 0.5))
    });

    tx.update(postRef, {
      commentsCount,
      rankingScore,
      updatedAt: admin.firestore.FieldValue.serverTimestamp()
    });
  });
});

exports.health = functions.https.onRequest((_, res) => {
  res.status(200).json({
    ok: true,
    service: "fixingnation-functions",
    timestamp: new Date().toISOString()
  });
});

exports._internal = {
  calculateRankingScore,
  routeAuthority,
  getRecencyScore,
  normalizeCategory,
  normalizeCreatedAtMillis,
  normalizeNonNegativeInteger
};
