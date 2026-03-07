const test = require('node:test');
const assert = require('node:assert/strict');

const { _internal } = require('./index');

test('routeAuthority resolves supported city/category', () => {
  assert.equal(_internal.routeAuthority('pune', 'road_damage'), 'pune_municipal_corporation_roads');
});

test('routeAuthority falls back for unknown city', () => {
  assert.equal(_internal.routeAuthority('delhi', 'garbage'), 'unmapped_city_authority');
});

test('normalizeCategory defaults unsupported values to other', () => {
  assert.equal(_internal.normalizeCategory('unknown_category'), 'other');
  assert.equal(_internal.normalizeCategory('WATER'), 'water');
});

test('normalizeNonNegativeInteger coerces invalid and negative values', () => {
  assert.equal(_internal.normalizeNonNegativeInteger('7.8'), 7);
  assert.equal(_internal.normalizeNonNegativeInteger(-100), 0);
  assert.equal(_internal.normalizeNonNegativeInteger('not_a_number'), 0);
});

test('normalizeCreatedAtMillis clamps future timestamps', () => {
  const now = Date.now();
  const mockedFuture = { toMillis: () => now + 3600 * 1000 };
  const normalized = _internal.normalizeCreatedAtMillis(mockedFuture);
  assert.ok(normalized <= Date.now());
  assert.ok(normalized >= 0);
});

test('calculateRankingScore sanitizes non-numeric inputs', () => {
  const score = _internal.calculateRankingScore({
    proximity: 'invalid',
    engagement: 'nan',
    recency: Infinity,
    severity: -50
  });
  assert.ok(score >= 0 && score <= 1);
});

test('ranking score remains bounded', () => {
  const score = _internal.calculateRankingScore({ proximity: 1, engagement: 9999, recency: 1, severity: 1 });
  assert.ok(score <= 1 && score >= 0);
});
