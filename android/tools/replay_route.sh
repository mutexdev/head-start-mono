#!/usr/bin/env bash
#
# replay_route.sh — feed a driving route into a running Android emulator so the app's
# real tracking stack (TrackingPhaseController -> PositionUploader -> Firestore) can be
# watched end to end without a car.
#
# usage:
#   replay_route.sh <serial> <lon1,lat1> <lon2,lat2> ... [options]
#   replay_route.sh <serial>                             # the canned ~8 km route
#
# options:
#   --step-seconds N   seconds between fixes, overriding BOTH phase cadences
#   --near-band M      metres at which the far phase becomes the near phase (default 5040)
#   --far-step M       metres advanced per fix while far   (default 250, > the 200 m filter)
#   --near-step M      metres advanced per fix while near  (default  50, > the  10 m filter)
#   --dry-run          print the fixes instead of pushing them
#   --adb PATH         adb binary (default: $ANDROID_HOME/platform-tools/adb, then PATH)
#
# NOTE THE ARGUMENT ORDER. `adb emu geo fix` takes LONGITUDE FIRST, LATITUDE SECOND.
# Waypoints on this command line are therefore also `lon,lat`. Getting it backwards puts
# the route in the wrong hemisphere and every fix still returns OK, so nothing tells you.
#
# The emulator's fused provider reports hAcc = 5.0 m for an injected fix, which passes the
# controller's `accuracyM <= 100` gate, so these are real uploads and not a special path.
#
# The default cadences mirror CLIENT_CONTRACT.md's tracking table: 30 s / 200 m while far,
# 5 s / 10 m while near. The step distances are set just above each filter's threshold so
# every generated fix is one the app is expected to upload.
#
set -euo pipefail

SERIAL=""
WAYPOINTS=()
STEP_SECONDS=""
NEAR_BAND=5040
FAR_STEP=250
NEAR_STEP=50
FAR_SLEEP=30
NEAR_SLEEP=5
DRY_RUN=0
ADB="${ANDROID_HOME:-$HOME/Library/Android/sdk}/platform-tools/adb"

die() { echo "replay_route.sh: $*" >&2; exit 1; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --step-seconds) STEP_SECONDS="${2:-}"; shift 2 ;;
    --near-band)    NEAR_BAND="${2:-}";    shift 2 ;;
    --far-step)     FAR_STEP="${2:-}";     shift 2 ;;
    --near-step)    NEAR_STEP="${2:-}";    shift 2 ;;
    --adb)          ADB="${2:-}";          shift 2 ;;
    --dry-run)      DRY_RUN=1;             shift ;;
    -h|--help)      sed -n '2,30p' "$0"; exit 0 ;;
    -*)             die "unknown option $1" ;;
    *)
      if [[ -z "$SERIAL" ]]; then SERIAL="$1"; else WAYPOINTS+=("$1"); fi
      shift ;;
  esac
done

[[ -n "$SERIAL" ]] || die "no emulator serial. usage: replay_route.sh <serial> [<lon,lat> ...]"
[[ -x "$ADB" ]] || ADB="$(command -v adb || true)"
[[ -n "$ADB" && -x "$ADB" ]] || die "adb not found; pass --adb /path/to/adb"

if [[ -n "$STEP_SECONDS" ]]; then
  FAR_SLEEP="$STEP_SECONDS"
  NEAR_SLEEP="$STEP_SECONDS"
fi

# The canned route: ~8 km into central Bengaluru, ending exactly on the 'spot' coordinate
# the runbook tells you to save as the pickup point. Four legs, so it bends like a road
# rather than running as one straight line.
#
# WHY 8 km and not the 4 km you might expect. The server sets `bands.near` to
# `min(routeDistanceM, 7 min x speed)`, and the emulator's stub router runs at
# ROUTING_STUB_SPEED_MPS=12, so bands.near tops out at 7*60*12 = 5040 m. On any route
# shorter than that the trip is in the `near` phase from its very first fix and the
# far->near cadence change — the thing this script exists to make visible — never happens.
# 8 km leaves ~3 km of genuine far phase before the switch. Hence the 5040 m default above.
CANNED_SPOT="77.5946,12.9716"
if [[ ${#WAYPOINTS[@]} -eq 0 ]]; then
  WAYPOINTS=(
    "77.5424,12.9206"
    "77.5560,12.9330"
    "77.5700,12.9470"
    "77.5840,12.9600"
    "$CANNED_SPOT"
  )
  echo "no waypoints given — using the canned ~8 km route ending at $CANNED_SPOT"
fi

[[ ${#WAYPOINTS[@]} -ge 2 ]] || die "need at least two waypoints (start and spot)"

for wp in "${WAYPOINTS[@]}"; do
  [[ "$wp" =~ ^-?[0-9.]+,-?[0-9.]+$ ]] || die "waypoint '$wp' is not lon,lat"
done

# ---------------------------------------------------------------------------
# Generate the fixes. awk owns the geometry: haversine for the distance-to-spot
# that decides the phase, linear interpolation along each leg for the path itself.
# Emits: <lon> <lat> <metres to spot> <phase> <sleep seconds>
# ---------------------------------------------------------------------------
generate_fixes() {
  printf '%s\n' "${WAYPOINTS[@]}" | awk -F, \
    -v nearBand="$NEAR_BAND" -v farStep="$FAR_STEP" -v nearStep="$NEAR_STEP" \
    -v farSleep="$FAR_SLEEP" -v nearSleep="$NEAR_SLEEP" '
    function rad(d) { return d * 3.141592653589793 / 180 }
    function haversine(lat1, lon1, lat2, lon2,   R, dLat, dLon, a) {
      R = 6371000
      dLat = rad(lat2 - lat1); dLon = rad(lon2 - lon1)
      a = sin(dLat/2)^2 + cos(rad(lat1)) * cos(rad(lat2)) * sin(dLon/2)^2
      return 2 * R * atan2(sqrt(a), sqrt(1-a))
    }
    function emit(lon, lat,   d, phase, slp) {
      d = haversine(lat, lon, spotLat, spotLon)
      if (d <= nearBand) { phase = "near"; slp = nearSleep } else { phase = "far"; slp = farSleep }
      printf "%.6f %.6f %d %s %s\n", lon, lat, d, phase, slp
      return d
    }
    { lon[NR] = $1; lat[NR] = $2; n = NR }
    END {
      spotLon = lon[n]; spotLat = lat[n]
      emit(lon[1], lat[1])
      curLon = lon[1]; curLat = lat[1]
      for (i = 2; i <= n; i++) {
        legLon = lon[i]; legLat = lat[i]
        while (1) {
          remaining = haversine(curLat, curLon, legLat, legLon)
          if (remaining < 1) break
          d = haversine(curLat, curLon, spotLat, spotLon)
          step = (d <= nearBand) ? nearStep : farStep
          if (step >= remaining) { curLon = legLon; curLat = legLat }
          else {
            f = step / remaining
            curLon = curLon + (legLon - curLon) * f
            curLat = curLat + (legLat - curLat) * f
          }
          emit(curLon, curLat)
          if (curLon == legLon && curLat == legLat) break
        }
      }
    }'
}

FIXES="$(generate_fixes)"
COUNT="$(printf '%s\n' "$FIXES" | grep -c . || true)"
echo "serial=$SERIAL fixes=$COUNT nearBand=${NEAR_BAND}m farStep=${FAR_STEP}m nearStep=${NEAR_STEP}m"
echo "cadence: far ${FAR_SLEEP}s / near ${NEAR_SLEEP}s"

if [[ "$DRY_RUN" -eq 1 ]]; then
  printf '%s\n' "$FIXES"
  exit 0
fi

i=0
last_phase=""
while read -r lon lat dist phase slp; do
  [[ -n "$lon" ]] || continue
  i=$((i + 1))
  out="$("$ADB" -s "$SERIAL" emu geo fix "$lon" "$lat" 2>&1 | tr -d '\r')"
  case "$out" in
    *OK*) : ;;
    *) die "fix $i ($lon,$lat) failed: $out" ;;
  esac
  if [[ "$phase" != "$last_phase" ]]; then
    echo "--- phase -> $phase (${slp}s cadence) ---"
    last_phase="$phase"
  fi
  printf '%3d/%s  %s,%s  %sm to spot  %s  OK\n' "$i" "$COUNT" "$lon" "$lat" "$dist" "$phase"
  # No sleep after the final fix: the driver has arrived, the server decides the rest.
  if [[ "$i" -lt "$COUNT" ]]; then sleep "$slp"; fi
done <<< "$FIXES"

echo "replayed $i fixes on $SERIAL; final position is the spot"
