# CivicPulse (FixingNation)

CivicPulse is a mobile-first civic grievance and public accountability platform focused on India (Pune, Mumbai, Bangalore).

## Stack
- Flutter (Android primary, Web PWA secondary)
- Firebase Auth, Firestore, Storage, Functions, Hosting, FCM
- GitHub Actions CI

## Repo layout
- `AGENTS.md` — implementation directives for AI/human contributors
- `ARCHITECTURE.md` — production architecture and constraints
- `TASKS.md` — phased roadmap
- `flutter_app/` — Flutter client scaffold
- `firebase/` — Firebase rules/functions/indexes
- `scripts/` — build/deploy scripts

## Quickstart
1. Install Flutter + Firebase CLI.
2. Configure Firebase project and `flutterfire configure`.
3. Run app:
   - `cd flutter_app && flutter pub get && flutter run`
4. Run functions checks:
   - `cd firebase/functions && npm install && npm test`
