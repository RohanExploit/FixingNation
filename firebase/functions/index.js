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

function clamp01(value) {
  return Math.max(0, Math.min(1, value));
}

function getRecencyScore(createdAtMillis) {
  const ageHours = (Date.now() - createdAtMillis) / (1000 * 60 * 60);
  return clamp01(1 - ageHours / 72);
}

function calculateRankingScore({ proximity = 0.5, engagement = 0, recency = 0.5, severity = 0.5 }) {
  const normalizedEngagement = clamp01(engagement / 100);
  return Number((0.35 * proximity + 0.30 * normalizedEngagement + 0.20 * recency + 0.15 * severity).toFixed(4));
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
  const category = post.category || "other";
  const city = post.city || "";

  const moderation = {
    status: "approved",
    reason: "Heuristic baseline moderation",
    confidence: 0.7,
    source: "fallback_local"
  };

  const severityByCategory = {
    road_damage: 0.8,
    garbage: 0.6,
    electricity: 0.7,
    water: 0.7,
    safety: 0.9,
    corruption: 0.95,
    other: 0.5
  };

  const severity = severityByCategory[category] || 0.5;
  const createdAtMillis = post.createdAt?.toMillis?.() || Date.now();
  const recency = getRecencyScore(createdAtMillis);
  const engagement = (post.upvotes || 0) + (post.commentsCount || 0);

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
    const commentsCount = (post.commentsCount || 0) + 1;
    const engagement = (post.upvotes || 0) + commentsCount;
    const createdAtMillis = post.createdAt?.toMillis?.() || Date.now();
    const recency = getRecencyScore(createdAtMillis);
    const rankingScore = calculateRankingScore({
      proximity: 0.5,
      engagement,
      recency,
      severity: post.severity || 0.5
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
  getRecencyScore
};
