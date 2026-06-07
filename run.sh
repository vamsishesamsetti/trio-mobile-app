#!/usr/bin/env bash
# Runs Trio with Supabase credentials from .env on a chosen device.
# Usage:  ./run.sh            (interactive device pick)
#         ./run.sh chrome     (run on a specific device id, e.g. chrome / emulator-5554)
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  echo "Missing .env — copy .env.example to .env and fill in your Supabase keys."
  exit 1
fi
set -a; source .env; set +a

DEVICE_ARG=()
[[ $# -ge 1 ]] && DEVICE_ARG=(-d "$1")

exec flutter run "${DEVICE_ARG[@]}" \
  --dart-define=SUPABASE_URL="$SUPABASE_URL" \
  --dart-define=SUPABASE_ANON_KEY="$SUPABASE_ANON_KEY"
