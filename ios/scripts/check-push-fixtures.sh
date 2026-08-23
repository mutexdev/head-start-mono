#!/bin/bash
# ios/scripts/check-push-fixtures.sh
#
# Validates ios/fixtures/push/*.apns — the thirteen payloads `xcrun simctl push`
# delivers to prove push ROUTING on a machine with no APNs key, no paid Apple team
# and no phone.
#
# WHY THIS SCRIPT EXISTS INSTEAD OF `plutil -lint`. The ios6 brief's done-criteria
# said `plutil -lint ios/fixtures/push/*.apns`. That command cannot pass on any
# JSON file on this machine — `plutil -lint` accepts only plist syntaxes and
# reports "(Unexpected character { at line 1)" for valid JSON, verified on
# /tmp/t.json. And the payloads MUST be JSON: `xcrun simctl help push` says
# "Path to a JSON payload". So the parse check is `plutil -convert`, which does
# read JSON, plus the contract assertions `-lint` could never have made anyway.
#
# Usage: ios/scripts/check-push-fixtures.sh
set -u

cd "$(dirname "$0")/.." || exit 1
DIR="fixtures/push"
BUNDLE="com.mutexdev.headstart"

# CLIENT_CONTRACT.md lines 50-52, in order.
KINDS=(started tenMin leadTime slip arrived lost timeout cancelled didYouLeave armed noShow runningLate reply)

fail=0
note() { echo "  FAIL: $1"; fail=1; }

echo "checking $DIR — ${#KINDS[@]} contract kinds"

count=$(find "$DIR" -name '*.apns' | wc -l | tr -d ' ')
[ "$count" = "${#KINDS[@]}" ] || note "expected ${#KINDS[@]} .apns files, found $count"

for kind in "${KINDS[@]}"; do
  f="$DIR/$kind.apns"
  [ -f "$f" ] || { note "$f missing"; continue; }

  # Parses as a property list / JSON at all.
  if ! plutil -convert xml1 -o /dev/null "$f" >/dev/null 2>&1; then
    note "$f is not parseable"
    continue
  fi

  # Contract assertions.
  python3 - "$f" "$kind" "$BUNDLE" <<'PY' || fail=1
import json, sys
path, kind, bundle = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.load(open(path))
bad = []
if d.get("Simulator Target Bundle") != bundle:
    bad.append(f"Simulator Target Bundle != {bundle}")
if d.get("data", {}).get("kind") != kind:
    bad.append(f"data.kind != {kind}")
if not d.get("data", {}).get("tripId"):
    bad.append("data.tripId missing (ADDENDUM section D)")
aps = d.get("aps", {})
want = "time-sensitive" if kind == "leadTime" else "active"
if aps.get("interruption-level") != want:
    bad.append(f"aps.interruption-level != {want} (ADDENDUM section C)")
if aps.get("content-available") != 1:
    bad.append("aps.content-available != 1 (needed for the silent-delivery funnel)")
alert = aps.get("alert", {})
if not isinstance(alert, dict) or not alert.get("title") or not alert.get("body"):
    bad.append("aps.alert.title/body missing")
if len(json.dumps(d)) > 4096:
    bad.append("payload over the 4096-byte simctl limit")
for b in bad:
    print(f"  FAIL: {path}: {b}")
sys.exit(1 if bad else 0)
PY
done

# ADDENDUM section C, stated as a whole-directory invariant rather than per file.
urgent=$(grep -l 'time-sensitive' "$DIR"/*.apns | wc -l | tr -d ' ')
[ "$urgent" = "1" ] || note "exactly one fixture may be time-sensitive; found $urgent"

if [ "$fail" = "0" ]; then
  echo "OK — ${#KINDS[@]}/${#KINDS[@]} fixtures valid, leadTime is the only time-sensitive one"
  exit 0
fi
echo "FIXTURES INVALID"
exit 1
