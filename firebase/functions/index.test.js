const test = require('node:test');
const assert = require('node:assert/strict');

const { _internal } = require('./index');

test('routeAuthority resolves supported city/category', () => {
  assert.equal(_internal.routeAuthority('pune', 'road_damage'), 'pune_municipal_corporation_roads');
});

test('routeAuthority falls back for unknown city', () => {
  assert.equal(_internal.routeAuthority('delhi', 'garbage'), 'unmapped_city_authority');
});

test('ranking score remains bounded', () => {
  const score = _internal.calculateRankingScore({ proximity: 1, engagement: 9999, recency: 1, severity: 1 });
  assert.ok(score <= 1 && score >= 0);
});
