#!/usr/bin/env bash
set -euo pipefail

cd flutter_app
flutter pub get
flutter build apk --release
flutter build appbundle --release

echo "Expected outputs:"
echo " - build/app/outputs/flutter-apk/app-release.apk"
echo " - build/app/outputs/bundle/release/app-release.aab"
