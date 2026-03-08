/**
 * scoring.js
 *
 * Pure, side-effect-free scoring functions ported directly from
 * firebase/functions/index.js.  The Worker is the sole authority that
 * computes these values; the Flutter client never touches them.
 */

export const SUPPORTED_CATEGORIES = new Set([
  "road_damage",
  "garbage",
  "electricity",
  "water",
  "safety",
  "corruption",
  "other",
]);

/** Baseline severity when AI classification is unavailable. */
export const SEVERITY_BY_CATEGORY = {
  road_damage: 0.80,
  garbage:     0.60,
  electricity: 0.70,
  water:       0.70,
  safety:      0.90,
  corruption:  0.95,
  other:       0.50,
};

/** City → category → authorityId routing table.
 *  New cities should be added here or, better, loaded from Firestore
 *  cities/{city}/routes once that collection is seeded. */
export const CITY_AUTHORITIES = {
  pune: {
    road_damage:  "pune_municipal_corporation_roads",
    garbage:      "pune_sanitation_department",
    electricity:  "mahadiscom_pune",
    water:        "pune_water_board",
    safety:       "pune_city_police",
    corruption:   "maharashtra_anti_corruption_bureau",
    other:        "pune_municipal_corporation_general",
  },
  mumbai: {
    road_damage:  "bmc_roads",
    garbage:      "bmc_solid_waste",
    electricity:  "best_mumbai",
    water:        "bmc_water_department",
    safety:       "mumbai_police",
    corruption:   "maharashtra_anti_corruption_bureau",
    other:        "bmc_general",
  },
  bangalore: {
    road_damage:  "bbmp_roads",
    garbage:      "bbmp_solid_waste",
    electricity:  "bescom_bangalore",
    water:        "bwssb",
    safety:       "bangalore_city_police",
    corruption:   "karnataka_lokayukta",
    other:        "bbmp_general",
  },
};

// ---------------------------------------------------------------------------
// Primitive helpers
// ---------------------------------------------------------------------------

export function clamp01(v) {
  return Math.max(0, Math.min(1, v));
}

export function safeNumber(v, fallback = 0) {
  const n = Number(v);
  return Number.isFinite(n) ? n : fallback;
}

// ---------------------------------------------------------------------------
// Domain helpers
// ---------------------------------------------------------------------------

/**
 * Coerce any raw category string into a member of SUPPORTED_CATEGORIES.
 * Defaults to "other" for invalid or missing input.
 */
export function normalizeCategory(raw) {
  const s = String(raw ?? "other").trim().toLowerCase();
  return SUPPORTED_CATEGORIES.has(s) ? s : "other";
}

/**
 * Recency score based on post age.
 * Score decays linearly from 1.0 at creation to 0.0 at 72 hours.
 *
 * @param {number} createdAtMs - Unix epoch milliseconds of post creation.
 */
export function getRecencyScore(createdAtMs) {
  // `?? Date.now()` handles null and undefined before safeNumber sees the value.
  // safeNumber then handles NaN / Infinity / non-numeric strings.
  // Without this, Number(null) === 0 (epoch 1970) which produces score 0.
  const safeMs  = Math.min(safeNumber(createdAtMs ?? Date.now(), Date.now()), Date.now());
  const ageHours = (Date.now() - safeMs) / 3_600_000;
  return clamp01(1 - ageHours / 72);
}

/**
 * Weighted ranking score.
 * Formula: 0.35·proximity + 0.30·engagement + 0.20·recency + 0.15·severity
 *
 * All inputs are normalised to [0, 1] before weighting.
 * engagement is divided by 100 so that 100 interactions = maximum engagement.
 */
export function calculateRankingScore({
  proximity  = 0.5,
  engagement = 0,
  recency    = 1.0,
  severity   = 0.5,
} = {}) {
  const p = clamp01(safeNumber(proximity,  0.5));
  const e = clamp01(safeNumber(engagement, 0)   / 100);
  const r = clamp01(safeNumber(recency,    1.0));
  const s = clamp01(safeNumber(severity,   0.5));

  return Number((0.35 * p + 0.30 * e + 0.20 * r + 0.15 * s).toFixed(4));
}

/**
 * Map city + category to the responsible government authority ID.
 * Falls back to "unmapped_city_authority" for unknown cities.
 */
export function routeAuthority(city, category) {
  const cityMap = CITY_AUTHORITIES[(city ?? "").toLowerCase()];
  if (!cityMap) return "unmapped_city_authority";
  return cityMap[category] ?? cityMap.other;
}
