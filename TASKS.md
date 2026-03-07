# CivicPulse (FixingNation) — Execution Tasks

## Phase 1: Foundation
- [ ] Create monorepo structure for Flutter, Firebase functions, admin dashboard.
- [ ] Configure Firebase project files (`firebase.json`, rules, indexes).
- [ ] Configure CI skeleton in GitHub Actions.

## Phase 2: Auth & Profiles
- [ ] Email/social login with pseudonymous profile generation.
- [ ] Public profile fields + admin-only identity metadata.
- [ ] Reputation seed + anti-abuse counters.

## Phase 3: Post Issue Flow
- [ ] Create civic issue form (title/category/description/location/media).
- [ ] Offline queue + retry sync.
- [ ] Firestore write with moderation pending state.

## Phase 4: Feed & Discovery
- [ ] Ranked feed query with pagination.
- [ ] Nearby feed by city and geohash.
- [ ] Trending issues snapshot collection.

## Phase 5: Moderation & Routing
- [ ] Gemini moderation function with deterministic JSON.
- [ ] Authority routing rules by city + category.
- [ ] Auto-transition of post states.

## Phase 6: Engagement
- [ ] Upvotes + comments with denormalized counters.
- [ ] Report abuse flow.
- [ ] Share cards and deep links.

## Phase 7: Admin Dashboard
- [ ] Role-gated admin login.
- [ ] Flagged content queue.
- [ ] Ban/shadow-ban/user risk panel.

## Phase 8: Launch Readiness
- [ ] APK/AAB/web builds in CI.
- [ ] Firebase deployment workflow.
- [ ] Smoke tests and budget checks.
