/**
 * index.test.js
 *
 * Unit tests for the pure, side-effect-free functions in scoring.js and
 * classifier.js.  No network calls are made.  No Worker secrets are needed.
 *
 * Run with:  npm test   (executes: vitest run)
 */

import { describe, it, expect, vi } from "vitest";

import {
  clamp01,
  safeNumber,
  normalizeCategory,
  getRecencyScore,
  calculateRankingScore,
  routeAuthority,
  SEVERITY_BY_CATEGORY,
  SUPPORTED_CATEGORIES,
} from "./scoring.js";

import { classify } from "./classifier.js";

// ---------------------------------------------------------------------------
// scoring.js — primitive helpers
// ---------------------------------------------------------------------------

describe("clamp01", () => {
  it("returns value unchanged when already in [0, 1]", () => {
    expect(clamp01(0)).toBe(0);
    expect(clamp01(1)).toBe(1);
    expect(clamp01(0.5)).toBe(0.5);
  });

  it("clamps values below 0 to 0", () => {
    expect(clamp01(-1)).toBe(0);
    expect(clamp01(-999)).toBe(0);
  });

  it("clamps values above 1 to 1", () => {
    expect(clamp01(2)).toBe(1);
    expect(clamp01(100)).toBe(1);
  });
});

describe("safeNumber", () => {
  it("returns the number when valid", () => {
    expect(safeNumber(3.14)).toBe(3.14);
    expect(safeNumber(0)).toBe(0);
  });

  it("returns fallback for NaN", () => {
    expect(safeNumber(NaN, 7)).toBe(7);
  });

  it("returns fallback for non-numeric strings", () => {
    expect(safeNumber("abc", 1)).toBe(1);
  });

  it("returns fallback for Infinity", () => {
    expect(safeNumber(Infinity, 0)).toBe(0);
  });

  it("parses numeric strings", () => {
    expect(safeNumber("3.5", 0)).toBe(3.5);
  });
});

// ---------------------------------------------------------------------------
// scoring.js — normalizeCategory
// ---------------------------------------------------------------------------

describe("normalizeCategory", () => {
  it("accepts valid categories unchanged", () => {
    for (const cat of SUPPORTED_CATEGORIES) {
      expect(normalizeCategory(cat)).toBe(cat);
    }
  });

  it("normalises upper-case input to lower-case", () => {
    expect(normalizeCategory("GARBAGE")).toBe("garbage");
    expect(normalizeCategory("Road_Damage")).toBe("road_damage");
  });

  it("trims surrounding whitespace", () => {
    expect(normalizeCategory("  water  ")).toBe("water");
  });

  it("defaults unknown values to 'other'", () => {
    expect(normalizeCategory("broken_swing")).toBe("other");
    expect(normalizeCategory("")).toBe("other");
    expect(normalizeCategory(null)).toBe("other");
    expect(normalizeCategory(undefined)).toBe("other");
  });
});

// ---------------------------------------------------------------------------
// scoring.js — getRecencyScore
// ---------------------------------------------------------------------------

describe("getRecencyScore", () => {
  it("returns 1.0 for a post created right now", () => {
    expect(getRecencyScore(Date.now())).toBe(1);
  });

  it("returns 0.5 for a 36-hour-old post", () => {
    const ms = Date.now() - 36 * 3_600_000;
    expect(getRecencyScore(ms)).toBeCloseTo(0.5, 2);
  });

  it("returns 0 for a post older than 72 hours", () => {
    const ms = Date.now() - 73 * 3_600_000;
    expect(getRecencyScore(ms)).toBe(0);
  });

  it("clamps future timestamps to now (score = 1.0)", () => {
    const future = Date.now() + 9_999_999;
    expect(getRecencyScore(future)).toBe(1);
  });

  it("uses now as fallback for invalid input", () => {
    expect(getRecencyScore(NaN)).toBe(1);
    expect(getRecencyScore(null)).toBe(1);
  });
});

// ---------------------------------------------------------------------------
// scoring.js — calculateRankingScore
// ---------------------------------------------------------------------------

describe("calculateRankingScore", () => {
  it("returns a value in [0, 1]", () => {
    const score = calculateRankingScore({ proximity: 0.5, engagement: 10, recency: 0.8, severity: 0.7 });
    expect(score).toBeGreaterThanOrEqual(0);
    expect(score).toBeLessThanOrEqual(1);
  });

  it("matches expected weighted sum", () => {
    // All inputs at their defaults → 0.35·0.5 + 0.30·0 + 0.20·1.0 + 0.15·0.5
    const score = calculateRankingScore();
    expect(score).toBeCloseTo(0.35 * 0.5 + 0.30 * 0 + 0.20 * 1.0 + 0.15 * 0.5, 4);
  });

  it("clamps non-numeric inputs to defaults", () => {
    const score = calculateRankingScore({ proximity: "bad", engagement: null, recency: undefined });
    expect(score).toBeGreaterThanOrEqual(0);
    expect(score).toBeLessThanOrEqual(1);
  });

  it("engagement is normalised over 100", () => {
    // engagement = 100 should give maximum engagement contribution (0.30)
    const full = calculateRankingScore({ proximity: 0, engagement: 100, recency: 0, severity: 0 });
    const none = calculateRankingScore({ proximity: 0, engagement: 0,   recency: 0, severity: 0 });
    expect(full - none).toBeCloseTo(0.30, 4);
  });

  it("always returns a number with at most 4 decimal places", () => {
    const score = calculateRankingScore({ proximity: 0.33333, engagement: 7, recency: 0.66666, severity: 0.12345 });
    const decimals = String(score).split(".")[1]?.length ?? 0;
    expect(decimals).toBeLessThanOrEqual(4);
  });
});

// ---------------------------------------------------------------------------
// scoring.js — routeAuthority
// ---------------------------------------------------------------------------

describe("routeAuthority", () => {
  it("resolves a known city and category", () => {
    expect(routeAuthority("pune",      "garbage")).toBe("pune_sanitation_department");
    expect(routeAuthority("mumbai",    "road_damage")).toBe("bmc_roads");
    expect(routeAuthority("bangalore", "electricity")).toBe("bescom_bangalore");
  });

  it("is case-insensitive for city input", () => {
    expect(routeAuthority("PUNE", "water")).toBe(routeAuthority("pune", "water"));
    expect(routeAuthority("Mumbai", "safety")).toBe(routeAuthority("mumbai", "safety"));
  });

  it("falls back to the city's 'other' authority for an unknown category", () => {
    expect(routeAuthority("pune", "unknown_category")).toBe("pune_municipal_corporation_general");
  });

  it("returns 'unmapped_city_authority' for an unknown city", () => {
    expect(routeAuthority("delhi",   "garbage")).toBe("unmapped_city_authority");
    expect(routeAuthority("",        "water"  )).toBe("unmapped_city_authority");
    expect(routeAuthority(null,      "water"  )).toBe("unmapped_city_authority");
    expect(routeAuthority(undefined, "water"  )).toBe("unmapped_city_authority");
  });
});

// ---------------------------------------------------------------------------
// scoring.js — SEVERITY_BY_CATEGORY
// ---------------------------------------------------------------------------

describe("SEVERITY_BY_CATEGORY", () => {
  it("contains an entry for every supported category", () => {
    for (const cat of SUPPORTED_CATEGORIES) {
      expect(SEVERITY_BY_CATEGORY).toHaveProperty(cat);
    }
  });

  it("all severity values are in [0, 1]", () => {
    for (const value of Object.values(SEVERITY_BY_CATEGORY)) {
      expect(value).toBeGreaterThanOrEqual(0);
      expect(value).toBeLessThanOrEqual(1);
    }
  });

  it("corruption has the highest severity", () => {
    const max = Math.max(...Object.values(SEVERITY_BY_CATEGORY));
    expect(SEVERITY_BY_CATEGORY.corruption).toBe(max);
  });
});

// ---------------------------------------------------------------------------
// classifier.js — classify() with mocked env
// ---------------------------------------------------------------------------

describe("classify — deterministic fallback when no API key", () => {
  it("returns a valid result without calling any API", async () => {
    const result = await classify("Pothole on main road", "Large pothole", "pune", "road_damage", {
      // GEMINI_API_KEY intentionally absent
    });

    expect(result.source).toBe("fallback_deterministic");
    expect(result.category).toBe("road_damage");
    expect(result.severity).toBe(SEVERITY_BY_CATEGORY.road_damage);
    expect(result.isSpam).toBe(false);
    expect(result.isToxic).toBe(false);
    expect(typeof result.confidence).toBe("number");
  });

  it("normalises an unknown hint category to 'other'", async () => {
    const result = await classify("Test", "Test description", "mumbai", "broken_swing", {});
    expect(result.category).toBe("other");
    expect(result.severity).toBe(SEVERITY_BY_CATEGORY.other);
  });
});

describe("classify — Gemini failure falls back to deterministic", () => {
  it("returns fallback when Gemini returns a non-200 response", async () => {
    // Stub fetch to simulate a Gemini error
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   false,
      status: 503,
      text: async () => "Service Unavailable",
    });

    const result = await classify("Garbage dump", "Waste not collected", "bangalore", "garbage", {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.source).toBe("fallback_deterministic");
    expect(result.category).toBe("garbage");

    globalThis.fetch = originalFetch;
  });

  it("returns fallback when Gemini returns malformed JSON", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: "Sorry, I cannot help with that." }] } }],
      }),
    });

    const result = await classify("Electricity issue", "No power for 3 days", "mumbai", "electricity", {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.source).toBe("fallback_deterministic");

    globalThis.fetch = originalFetch;
  });

  it("returns fallback when Gemini blocks the prompt", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: async () => ({
        promptFeedback: { blockReason: "SAFETY" },
        candidates:     [],
      }),
    });

    const result = await classify("Test", "Test", "pune", undefined, {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.source).toBe("fallback_deterministic");

    globalThis.fetch = originalFetch;
  });
});

describe("classify — valid Gemini response", () => {
  it("parses a clean Gemini JSON response correctly", async () => {
    const geminiPayload = {
      category:            "water",
      severity:            0.7,
      isSpam:              false,
      isToxic:             false,
      confidence:          0.92,
      reason:              "Burst pipe reported near residential area.",
      suggestedDepartment: "pune_water_board",
    };

    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: JSON.stringify(geminiPayload) }] } }],
      }),
    });

    const result = await classify("Burst pipe", "Water leaking on street", "pune", undefined, {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.source).toBe("gemini_2_flash");
    expect(result.category).toBe("water");
    expect(result.severity).toBeCloseTo(0.7);
    expect(result.isSpam).toBe(false);
    expect(result.isToxic).toBe(false);
    expect(result.confidence).toBeCloseTo(0.92);

    globalThis.fetch = originalFetch;
  });

  it("extracts JSON even when Gemini wraps it in code fences", async () => {
    const geminiPayload = { category: "safety", severity: 0.9, isSpam: false, isToxic: false, confidence: 0.85, reason: "Test.", suggestedDepartment: "police" };
    const fencedText    = `\`\`\`json\n${JSON.stringify(geminiPayload)}\n\`\`\``;

    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: fencedText }] } }],
      }),
    });

    const result = await classify("Street fight", "Violence reported", "bangalore", undefined, {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.source).toBe("gemini_2_flash");
    expect(result.category).toBe("safety");

    globalThis.fetch = originalFetch;
  });

  it("normalises an invalid category returned by Gemini to 'other'", async () => {
    const geminiPayload = { category: "broken_swing", severity: 0.5, isSpam: false, isToxic: false, confidence: 0.6, reason: "Unknown.", suggestedDepartment: "council" };

    const originalFetch = globalThis.fetch;
    globalThis.fetch = vi.fn().mockResolvedValue({
      ok:   true,
      json: async () => ({
        candidates: [{ content: { parts: [{ text: JSON.stringify(geminiPayload) }] } }],
      }),
    });

    const result = await classify("Random thing", "Description", "mumbai", undefined, {
      GEMINI_API_KEY: "test-key",
    });

    expect(result.category).toBe("other");

    globalThis.fetch = originalFetch;
  });
});
