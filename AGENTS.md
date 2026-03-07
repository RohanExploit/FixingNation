# FixingNation Agent Directive

## Mission
Build and operate **CivicPulse (FixingNation)** as a public civic accountability platform for India (Pune, Mumbai, Bangalore first), optimized for Gen-Z mobile behavior.

## Non-Negotiables
1. **Stability > Completion**
2. **Simple systems > Complex systems**
3. **Free infrastructure only** (Firebase Spark, OSS, free APIs)
4. **Low resource usage > High feature count**

## Required stack
- Flutter (Android primary, Web PWA secondary)
- Firebase Auth, Firestore, Storage, Functions, Hosting, FCM, Analytics
- OpenStreetMap for mapping
- Gemini Pro (low temperature) for moderation support

## Delivery order for implementation
1. System architecture
2. Firebase budget and limits
3. Data models
4. Backend services
5. Flutter app architecture
6. AI moderation system
7. Deployment pipeline
8. Security design
9. Scaling plan
10. Codebase structure
11. Initial implementation

## Cost guardrails (Spark plan)
- Firestore: 50k reads/day, 20k writes/day, 1GB storage
- Hosting: ~10GB/month transfer
- Functions: ~125k invocations/month
- Storage: 1GB

## Product guardrails
- Public pseudonymous identities (username/avatar/reputation)
- Admin-only sensitive identity view (email/device/IP metadata)
- Public-first grievance visibility and shareability
- Strict anti-abuse controls (rate limits, moderation, reputation)

## AI moderation guardrails
- Temperature <= 0.2
- Deterministic JSON outputs
- If uncertain return: `Insufficient information`
- Never fabricate authority records
