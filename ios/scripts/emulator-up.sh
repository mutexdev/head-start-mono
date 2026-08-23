#!/bin/bash
# ios/scripts/emulator-up.sh
#
# Start (or reuse) the Firebase Local Emulator Suite the iOS app talks to.
#
# TWO-TIER SOURCE, real first:
#   1. <repo>/firebase.json + <repo>/functions/   -> the REAL backend. Always preferred:
#      real callables, the real alert ladder, the real firestore.rules and the real
#      `_debugPushes` sink. This is the strictly stronger test.
#   2. ios/scripts/stub-backend/                  -> the cold spare, used only when the
#      backend batch has not landed. Lives inside the iOS lane and is passed with
#      `--config <abs path>/firebase.json`, so nothing at the repo root is touched.
#
# EMULATOR ETIQUETTE — three pipelines share this machine. There must be at most ONE suite,
# on the contract's ports (auth 9099 / firestore 8080 / functions 5001 / ui 4000). If
# something is already listening on 8080 this script REUSES it and exits 0. It never kills
# a running suite and never starts a second one on other ports.
#
# Usage:
#   bash ios/scripts/emulator-up.sh            # foreground (Ctrl-C to stop)
#   bash ios/scripts/emulator-up.sh --detach   # background, log to ios/build/emulator.log
set -u

REPO="$(cd "$(dirname "$0")/../.." && pwd)"
IOS="$REPO/ios"
PROJECT="fin-e8358"
STUB="$IOS/scripts/stub-backend"
LOG="$IOS/build/emulator.log"
DETACH=0
[ "${1:-}" = "--detach" ] && DETACH=1

if lsof -ti :8080 >/dev/null 2>&1; then
  echo "emulator: REUSING the suite already listening on 8080 (etiquette: never start a second one)"
  curl -s -m 5 "http://127.0.0.1:5001/$PROJECT/us-central1/debugPing" >/dev/null 2>&1 \
    && echo "emulator: functions on 5001 answer debugPing — this is the REAL backend" \
    || echo "emulator: functions on 5001 did not answer debugPing (stub, or still booting)"
  exit 0
fi

if [ -f "$REPO/firebase.json" ] && [ -d "$REPO/functions" ]; then
  echo "emulator: source=REAL  ($REPO/firebase.json + functions/)"
  CMD=(firebase emulators:start --project "$PROJECT" --only auth,firestore,functions)
  DIR="$REPO"
  # The real backend needs its build products and .secret.local; both are idempotent.
  ( cd "$REPO/functions" && [ -d node_modules ] || npm install --silent --no-audit --no-fund )
  ( cd "$REPO/functions" && node scripts/bootstrapEmulatorEnv.js >/dev/null 2>&1; npm run --silent build ) \
    || { echo "emulator: FAILED to build $REPO/functions"; exit 1; }
else
  echo "emulator: source=STUB  ($STUB) — the repo-root backend is absent"
  CMD=(firebase emulators:start --project "$PROJECT" --only auth,firestore,functions --config "$STUB/firebase.json")
  DIR="$STUB"
  ( cd "$STUB/functions" && [ -d node_modules ] || npm install --silent --no-audit --no-fund )
fi

mkdir -p "$IOS/build"
if [ "$DETACH" = "1" ]; then
  echo "emulator: starting detached, log -> $LOG"
  ( cd "$DIR" && nohup "${CMD[@]}" >"$LOG" 2>&1 & echo "emulator: pid $!" )
  for _ in $(seq 1 60); do
    lsof -ti :8080 >/dev/null 2>&1 && lsof -ti :5001 >/dev/null 2>&1 && lsof -ti :9099 >/dev/null 2>&1 && break
    sleep 1
  done
  lsof -ti :8080 >/dev/null 2>&1 || { echo "emulator: FAILED to come up; see $LOG"; exit 1; }
  echo "emulator: up on auth 9099 / firestore 8080 / functions 5001 / ui 4000"
else
  cd "$DIR" && exec "${CMD[@]}"
fi
