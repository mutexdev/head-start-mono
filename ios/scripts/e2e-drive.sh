#!/bin/bash
# ios/scripts/e2e-drive.sh — the headless replacement for the M1 real drive.
#
# WHAT THIS REPLACES. Plan Task 20 is a GUI-and-hardware walkthrough: Xcode's
# "Edit Scheme > Core Location > Allow Location Simulation", "Debug > Simulate Location",
# a physical iPhone, a paid Apple team and a second phone. None of those exist here. This
# script does the same job with `xcrun simctl` and the Firebase Local Emulator Suite:
# boot, install, grant location, launch, sign in with a code read from the Auth emulator,
# pair, create the spot, start the trip, DRIVE the same Dhaka route at the same 12 m/s,
# push contract payloads, and assert against Firestore and the app's log stream.
#
# THE ONE THING simctl CANNOT DO IS TAP. So the app carries a DEBUG-only, emulator-only
# autopilot (ios/Headstart/UI/E2EAutopilot.swift) driven by launch arguments, which calls
# the SAME `AppViewModel` methods the buttons call. Nothing product-shaped is
# reimplemented here; a bug in sign-in, pairing, spot creation or startTrip fails this
# drive exactly as a human tap would.
#
# Usage:  bash ios/scripts/e2e-drive.sh
# Exit:   0 only if every assertion passed.
set -u

cd "$(dirname "$0")/.." || exit 1          # -> ios/
REPO="$(cd .. && pwd)"
EMU="scripts/lib/emuclient.py"
BUNDLE="com.mutexdev.headstart"
APP="build/DerivedData/Build/Products/Debug-iphonesimulator/Headstart.app"
OUT="build/e2e"
DRIVER="+15555550100"
RECEIVER="+15555550101"
SPOT_LAT="23.7806"; SPOT_LNG="90.4193"
# The DriveRoute.gpx waypoints, verbatim. Keep the two in step.
WAYPOINTS="23.8103,90.4125 23.8006,90.4162 23.7909,90.4181 23.7844,90.4190 23.7806,90.4193"
SPEED=12

mkdir -p "$OUT"
APP_LOG="$OUT/app-driver.log"
APP_LOG2="$OUT/app-receiver.log"
: >"$APP_LOG"; : >"$APP_LOG2"

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  PASS  $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  FAIL  $1"; }
step() { echo; echo "== $1"; }
check(){ if [ "$1" = "0" ]; then ok "$2"; else bad "$2${3:+ — $3}"; fi; }

field() { python3 -c "import sys,json;d=json.load(sys.stdin);print('' if d is None else d.get('$1',''))"; }

emu() { python3 "$EMU" "$@"; }

cleanup() {
  [ -n "${UDID:-}" ] && xcrun simctl location "$UDID" clear >/dev/null 2>&1
  [ -n "${LOGSTREAM_PID:-}" ] && kill "$LOGSTREAM_PID" >/dev/null 2>&1
  return 0
}
trap cleanup EXIT

# ── 0. preflight ────────────────────────────────────────────────────────────
step "0. preflight"

if ! curl -s -m 5 "http://127.0.0.1:5001/fin-e8358/us-central1/debugPing" >/dev/null 2>&1; then
  if ! curl -s -m 5 -o /dev/null "http://127.0.0.1:9099/"; then
    echo "  the emulator suite is not running — start it with: bash scripts/emulator-up.sh --detach"
    exit 1
  fi
fi
ok "emulator suite answering on 9099/5001"

[ -d "$APP" ] || {
  echo "  no Debug build at $APP — run: make test   (or xcodebuild … build)"
  exit 1
}
ok "Debug build present"

# The iPhone 17 Pro on iOS 26.5, resolved by name + runtime. Never hard-code a UDID.
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json,sys
d=json.load(sys.stdin)["devices"]
for runtime, devices in d.items():
    if runtime.endswith("iOS-26-5"):
        for dev in devices:
            if dev["name"] == "iPhone 17 Pro":
                print(dev["udid"]); raise SystemExit
raise SystemExit("no iPhone 17 Pro on iOS 26.5")
')
[ -n "$UDID" ] || { echo "  could not resolve the simulator"; exit 1; }
ok "simulator iPhone 17 Pro / iOS 26.5 = $UDID"

# ── 1. boot, install, grant ─────────────────────────────────────────────────
step "1. boot, install, grant"
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1 || xcrun simctl boot "$UDID" >/dev/null 2>&1
xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
check $? "simulator booted"

xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
xcrun simctl install "$UDID" "$APP" >/dev/null 2>&1
check $? "app installed"

# `location`, not `location-always`: the app only ever calls
# requestWhenInUseAuthorization (decision D6), and granting Always here would hide a
# regression rather than reveal one. NOTE: Xcode 26.6's `simctl privacy` has NO
# `notifications` service, so notification permission cannot be pre-granted — see
# ios/README.md. Nothing this script asserts needs it.
xcrun simctl privacy "$UDID" grant location "$BUNDLE" >/dev/null 2>&1
check $? "location permission granted (when-in-use)"

# Park the device at the start of the route so the first fix exists before "I'm coming".
xcrun simctl location "$UDID" set "23.8103,90.4125" >/dev/null 2>&1
check $? "start location set"

# ── 2. seed the two test identities ─────────────────────────────────────────
step "2. seed the backend (the second person, whom no simulator can be)"
SEED=$(python3 - "$DRIVER" "$RECEIVER" <<'PY'
import json, subprocess, sys
def run(*a):
    return json.loads(subprocess.check_output(["python3", "scripts/lib/emuclient.py", *a]).decode() or "null")
driver, receiver = sys.argv[1], sys.argv[2]
d = run("signin", driver)
r = run("signin", receiver)
# registerPushToken is the ONLY way a display name reaches the server (it denormalises
# into pairs/{id}.memberNames, ADDENDUM section M). FCM cannot mint a token on a
# Simulator, so the app can never make this call there; the harness makes it for both
# identities so partner names render. On a real device the app does it itself.
run("call", "registerPushToken", d["idToken"],
    json.dumps({"token": "ios-e2e-driver-token-0000000001", "platform": "ios", "displayName": "Mostafi"}))
run("call", "registerPushToken", r["idToken"],
    json.dumps({"token": "ios-e2e-receiver-token-000000001", "platform": "ios", "displayName": "Sara"}))
# A stale pair from an earlier run would make the app skip the pairing step entirely.
for p in run("list", "pairs"):
    members = p.get("members") or []
    if p.get("status") in ("active", "pending") and (d["uid"] in members or r["uid"] in members):
        token = d["idToken"] if d["uid"] in members else r["idToken"]
        run("call", "revokePair", token, json.dumps({"pairId": p["id"]}))
print(json.dumps({"driver": d, "receiver": r}))
PY
) || { echo "  seeding failed"; exit 1; }
DRIVER_TOKEN=$(echo "$SEED" | python3 -c 'import sys,json;print(json.load(sys.stdin)["driver"]["idToken"])')
DRIVER_UID=$(echo "$SEED"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["driver"]["uid"])')
RECV_TOKEN=$(echo "$SEED"  | python3 -c 'import sys,json;print(json.load(sys.stdin)["receiver"]["idToken"])')
RECV_UID=$(echo "$SEED"    | python3 -c 'import sys,json;print(json.load(sys.stdin)["receiver"]["uid"])')
ok "driver $DRIVER uid=$DRIVER_UID / receiver $RECEIVER uid=$RECV_UID"

# ── 3. launch the app as the DRIVER ─────────────────────────────────────────
step "3. launch as the driver, sign in, pair, create the spot, start the trip"
xcrun simctl spawn "$UDID" log stream --style compact \
  --predicate 'eventMessage CONTAINS "[HS]"' >"$OUT/logstream.log" 2>/dev/null &
LOGSTREAM_PID=$!

( xcrun simctl launch --console-pty "$UDID" "$BUNDLE" \
    -HSEmulatorHost 127.0.0.1 -HSFakeEta 900 -HSFakeBatteryPct 80 \
    -HSAutoSignIn "$DRIVER" -HSAutoName Mostafi -HSAutoPair invite \
    -HSAutoSpot "$SPOT_LAT,$SPOT_LNG" -HSAutoSpotName Home -HSAutoStartTrip YES \
    >"$APP_LOG" 2>&1 & ) 

wait_log() {   # wait_log <file> <grep-pattern> <seconds> <label>
  local f="$1" pat="$2" secs="$3" label="$4" i=0
  while [ "$i" -lt "$secs" ]; do
    grep -qE "$pat" "$f" 2>/dev/null && return 0
    grep -qE '\[HS\]\[e2e\] (FAILED|timeout)' "$f" 2>/dev/null && { echo "    autopilot: $(grep -E '\[HS\]\[e2e\] (FAILED|timeout)' "$f" | tail -1)"; return 1; }
    sleep 1; i=$((i+1))
  done
  echo "    timed out after ${secs}s waiting for /$pat/ in $f"
  return 1
}

wait_log "$APP_LOG" '\[HS\] backend=emulator' 30 "launch"
check $? "app launched against the emulator ([HS] backend=emulator)"

wait_log "$APP_LOG" '\[HS\]\[e2e\] step=signedIn' 60 "signin"
check $? "OTP sign-in completed with a code read from the Auth emulator REST endpoint"

wait_log "$APP_LOG" '\[HS\]\[e2e\] step=invite code=' 60 "invite"
check $? "app minted an invite code (createPair)"

CODE=$(grep -o 'step=invite code=[A-Z0-9]*' "$APP_LOG" | tail -1 | cut -d= -f3)
PAIR_ID=""
if [ -n "$CODE" ]; then
  PAIR_ID=$(emu call acceptPair "$RECV_TOKEN" "{\"code\":\"$CODE\"}" 2>/dev/null | field pairId)
  [ -n "$PAIR_ID" ]
  check $? "receiver accepted invite code $CODE (acceptPair -> pairId=$PAIR_ID)"
else
  bad "no invite code in the log"
fi

wait_log "$APP_LOG" '\[HS\]\[e2e\] step=paired' 90 "paired"
check $? "app saw the active pair (pairs where members array-contains uid)"

wait_log "$APP_LOG" '\[HS\]\[e2e\] step=spot count=[1-9]' 60 "spot"
check $? "spot created at $SPOT_LAT/$SPOT_LNG (upsertSpot)"

wait_log "$APP_LOG" '\[HS\]\[trip\] startTrip tripId=' 90 "startTrip"
check $? "startTrip returned a tripId and bands"
grep -E '\[HS\]\[trip\] startTrip' "$APP_LOG" | tail -1 | sed 's/^/    /'

TRIP=$(grep -o '\[HS\]\[trip\] startTrip tripId=[A-Za-z0-9]*' "$APP_LOG" | tail -1 | cut -d= -f2)
[ -n "$TRIP" ] || { echo "  no tripId — cannot continue"; echo "E2E summary: $PASS passed, $((FAIL+1)) failed"; exit 1; }
echo "    tripId=$TRIP"

# ── 4. the drive ────────────────────────────────────────────────────────────
step "4. replay the Dhaka route at ${SPEED} m/s (same waypoints as ios/Headstart/DriveRoute.gpx)"
# shellcheck disable=SC2086
xcrun simctl location "$UDID" start --speed "$SPEED" $WAYPOINTS >/dev/null 2>&1
check $? "simctl location start"

# Poll the trip until the driver is at the spot. `lastPosDistM` is written by the real
# onPositionWrite trigger, so this is also proof the uploads are landing.
DIST=99999
STATE=""
for i in $(seq 1 400); do
  SUMMARY=$(emu trip-summary "$TRIP" 2>/dev/null)
  [ "$SUMMARY" = "null" ] && { sleep 1; continue; }
  DIST=$(echo "$SUMMARY" | python3 -c 'import sys,json;d=json.load(sys.stdin);print(int(d.get("lastPosDistM") or 99999))')
  STATE=$(echo "$SUMMARY" | field state)
  [ "$STATE" = "arrived" ] && break
  [ "$DIST" -lt 80 ] && break
  if [ $((i % 30)) = 0 ]; then
    echo "    t+${i}s  dist=${DIST}m  positions=$(echo "$SUMMARY" | field positions)  phaseHint=$(echo "$SUMMARY" | field phaseHint)"
  fi
  sleep 1
done
[ "$DIST" -lt 80 ] || [ "${STATE:-}" = "arrived" ]
check $? "driver reached the spot (lastPos ${DIST}m away)"

xcrun simctl location "$UDID" clear >/dev/null 2>&1

# ── 5. arrival dwell ────────────────────────────────────────────────────────
step "5. arrival dwell (server rule: speed < 2 m/s inside spot.radiusM for 20 s)"
# CoreLocation only delivers a fix once the device has moved `distanceFilter` metres, and
# in the near phase that is 10 m — a device parked exactly on the spot emits nothing at
# all. So nudge it between two points ~20 m apart, both well inside the 100 m radius,
# with more than the 20 s dwell between them. `location set` reports speed -1, which
# PositionUploader clamps to 0, so the "< 2 m/s" half of the rule is satisfied.
for i in 1 2 3 4 5 6; do
  if [ $((i % 2)) = 1 ]; then
    xcrun simctl location "$UDID" set "23.78078,90.41945" >/dev/null 2>&1
  else
    xcrun simctl location "$UDID" set "$SPOT_LAT,$SPOT_LNG" >/dev/null 2>&1
  fi
  sleep 12
  STATE=$(emu trip-summary "$TRIP" | field state)
  echo "    dwell $i: state=$STATE"
  [ "$STATE" = "arrived" ] && break
done
[ "$STATE" = "arrived" ]
check $? "trips/$TRIP.state == arrived (server decided, client never claims it)"

# ── 6. push routing ─────────────────────────────────────────────────────────
step "6. deliver contract push payloads (xcrun simctl push)"
for kind in started tenMin leadTime arrived; do
  xcrun simctl push "$UDID" "$BUNDLE" "fixtures/push/$kind.apns" >/dev/null 2>&1
  sleep 2
done
sleep 3
grep -qE '\[HS\]\[push\] kind=leadTime' "$APP_LOG" "$OUT/logstream.log"
check $? "leadTime push received and routed ([HS][push] kind=leadTime)"
for kind in started tenMin arrived; do
  grep -qE "\[HS\]\[push\] kind=$kind" "$APP_LOG" "$OUT/logstream.log"
  check $? "$kind push routed through PushRouter.handle(userInfo:)"
done

# ── 7. what the position documents look like ────────────────────────────────
step "7. positions written by the app"
SUMMARY=$(emu trip-summary "$TRIP")
echo "$SUMMARY" | python3 -m json.tool | sed 's/^/    /'

N=$(echo "$SUMMARY"    | field positions)
WITH=$(echo "$SUMMARY" | field withEtaSec)
FARG=$(echo "$SUMMARY" | field farGapSec)
NEARG=$(echo "$SUMMARY" | field nearGapSec)
EXTRA=$(echo "$SUMMARY" | python3 -c 'import sys,json;print(",".join(json.load(sys.stdin)["extraKeys"]))')
RC=$(echo "$SUMMARY"   | field routingCalls)
POLY=$(echo "$SUMMARY" | field hasRoutePolyline)

[ "${N:-0}" -ge 10 ]
check $? "position documents appeared in trips/$TRIP/positions (n=$N)"

[ "$N" = "$WITH" ] && [ "${N:-0}" -gt 0 ]
check $? "EVERY position carries etaSec ($WITH/$N) — decision D7, the whole cost argument for iOS"

[ -z "$EXTRA" ]
check $? "positions carry only the contract's keys${EXTRA:+ (extra: $EXTRA)}"

[ "${RC:-x}" = "0" ]
check $? "trips/$TRIP.routingCalls == 0 (ADDENDUM section F — a client etaSec means no routing)"

[ "$POLY" = "False" ]
check $? "no routePolyline on a client-etaSec trip"

python3 -c "
import sys
far, near = '$FARG', '$NEARG'
if far in ('', 'None') or near in ('', 'None'):
    print('    far/near gap not measurable: far=%s near=%s' % (far, near)); sys.exit(1)
far, near = float(far), float(near)
print('    median gap: far=%.2fs  near=%.2fs' % (far, near))
sys.exit(0 if near < far else 1)
"
check $? "cadence tightened after phaseHint flipped to near (far ${FARG}s -> near ${NEARG}s)"

# ── 8. the receiver half: Live Activity + the _debugPushes bridge ───────────
step "8. relaunch as the RECEIVER (the Live Activity is receiver-only)"
xcrun simctl terminate "$UDID" "$BUNDLE" >/dev/null 2>&1
sleep 2
( xcrun simctl launch --console-pty "$UDID" "$BUNDLE" \
    -HSEmulatorHost 127.0.0.1 -HSFakeEta 900 -HSFakeBatteryPct 80 \
    -HSAutoSignIn "$RECEIVER" -HSAutoName Sara -HSAutoPair wait \
    >"$APP_LOG2" 2>&1 & )

wait_log "$APP_LOG2" '\[HS\]\[e2e\] step=paired' 120 "receiver paired"
check $? "app re-signed-in as the receiver and found the same pair"

SPOT_ID=$(emu list spots | python3 -c "
import sys, json
rows = [s for s in json.load(sys.stdin) if s.get('pairId') == '$PAIR_ID']
print(rows[-1]['id'] if rows else '')
")
[ -n "$SPOT_ID" ]
check $? "the pair's spot is readable (spotId=$SPOT_ID)"
TRIP2=$(emu call startTrip "$DRIVER_TOKEN" \
  "{\"spotId\":\"$SPOT_ID\",\"lat\":23.8103,\"lng\":90.4125,\"etaSec\":900,\"fuzzy\":false}" \
  | field tripId)
[ -n "$TRIP2" ]
check $? "the other person started a trip (tripId=$TRIP2)"

wait_log "$APP_LOG2" '\[HS\]\[la\] started' 60 "live activity"
check $? "Live Activity started ([HS][la] started)"

wait_log "$APP_LOG2" '\[HS\]\[debugpush\] kind=started' 60 "debug push bridge"
check $? "_debugPushes bridge delivered the server's own push (ADDENDUM emulator contract)"

emu call endTrip "$DRIVER_TOKEN" "{\"tripId\":\"$TRIP2\",\"reason\":\"arrived\"}" >/dev/null
wait_log "$APP_LOG2" '\[HS\]\[la\] ended' 60 "live activity end"
check $? "Live Activity ended ([HS][la] ended)"

# ── summary ────────────────────────────────────────────────────────────────
step "summary"
echo "  logs: $APP_LOG  $APP_LOG2  $OUT/logstream.log"
echo "  E2E summary: $PASS passed, $FAIL failed"
[ "$FAIL" = "0" ] || exit 1
echo
echo "  NOTE: emulator + Simulator validation does NOT prove background location with the"
echo "  screen locked, the blue location indicator, real APNs/FCM delivery, a Live Activity"
echo "  on a real Lock Screen or Dynamic Island, real battery drain, or Time Sensitive"
echo "  Notifications. Those stay on docs/testing/real-drive-checklist.md."
exit 0
