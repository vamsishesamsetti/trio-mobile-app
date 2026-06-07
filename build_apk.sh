#!/usr/bin/env bash
# Builds a release Android APK with Supabase credentials baked in from .env.
# Output: build/app/outputs/flutter-apk/app-release.apk
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env and fill in your Supabase keys."
  exit 1
fi
set -a; source .env; set +a

flutter build apk --release \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"

echo
echo "APK ready: build/app/outputs/flutter-apk/app-release.apk"
echo "Install on a connected phone with:  adb install -r build/app/outputs/flutter-apk/app-release.apk"
