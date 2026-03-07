#!/usr/bin/env bash
set -euo pipefail

# Build web app
echo "Building Flutter web..."
(cd flutter_app && flutter build web)

# Deploy Firebase assets
echo "Deploying Firebase hosting/functions/rules..."
firebase deploy --only hosting,functions,firestore:rules,storage

echo "Deploy complete"
