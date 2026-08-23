# Headstart Android — emulator end-to-end run

This replaces the two-phone real drive for people who do not have two phones, a Blaze project,
an APNs key or a Routes API key. Everything below runs against the **Firebase Local Emulator
Suite** and two Android Virtual Devices, and it exercises the shipping code paths — the same
callables, the same Firestore listeners, the same notification renderer.

It takes about 25 minutes the first time. Every command is copy-pasteable. Where a step has a
known emulator-only wrinkle it is called out inline rather than left for you to discover.

**What this does NOT prove** is listed at the end, and it is not a short list. `docs/testing/
real-drive-checklist.md` is still the acceptance test for the product.

Shell variables used throughout:

```bash
REPO="$(git rev-parse --show-toplevel)"
ADB="$HOME/Library/Android/sdk/platform-tools/adb"
DRIVER=emulator-5554     # Pixel_9a,  API 36
RECEIVER=emulator-5556   # Pixel_10,  API 37
PROJECT=fin-e8358
```

---

## 1. Start the two AVDs

```bash
EMU="$HOME/Library/Android/sdk/emulator/emulator"
"$EMU" -avd Pixel_9a  -no-snapshot-load &
"$EMU" -avd Pixel_10  -no-snapshot-load &
"$ADB" devices          # wait until both say `device`, not `offline`
```

> **Do not use `Pixel_9_Pro`.** Its `config.ini` has no `image.sysdir.1` and the emulator aborts
> with `Broken AVD system path. Check your ANDROID_SDK_ROOT`. Only `Pixel_9a` and `Pixel_10` boot.

Both images are `google_apis_playstore`, so Play services is present and both
FusedLocationProvider and FCM token registration work. Pixel_10 is a 16 KB-page-size image; the
Firestore and androidx native libraries load on it fine.

## 2. Start the Firebase Local Emulator Suite

**Check first — there must never be two suites on this machine:**

```bash
lsof -ti :8080 && echo "a suite is already running: REUSE IT, do not start a second one"
```

If nothing is listening:

```bash
cd "$REPO/functions" && npm run emu:start
```

That script chains `emu:bootstrap && build` first, so `.secret.local` and `lib/` are always
fresh. Wait for `All emulators ready!`. Ports are fixed by the contract addendum:

| Emulator | Host port | From inside an AVD |
|---|---|---|
| Auth | 9099 | `10.0.2.2:9099` |
| Firestore | 8080 | `10.0.2.2:8080` |
| Functions | 5001 | `10.0.2.2:5001` |
| Emulator UI | 4000 | — (open it on the host) |

> `firebase.json` binds the emulators to `127.0.0.1`, **not** `0.0.0.0`, and that is correct:
> `10.0.2.2` is the AVD's alias for the *host's loopback*, so a loopback bind is reachable.
> There is no need to edit `firebase.json` (and it is backend-owned — don't).

Emulator UI: <http://127.0.0.1:4000/firestore>

## 3. Install the debug APK on both AVDs and pre-grant the runtime permissions

```bash
cd "$REPO/android" && ./gradlew :app:assembleDebug
for S in $DRIVER $RECEIVER; do
  "$ADB" -s $S install -r app/build/outputs/apk/debug/app-debug.apk
  "$ADB" -s $S shell pm grant app.headstart android.permission.ACCESS_FINE_LOCATION
  "$ADB" -s $S shell pm grant app.headstart android.permission.POST_NOTIFICATIONS
  "$ADB" -s $S shell am start -n app.headstart/.MainActivity
done
```

Confirm each build is pointed at the emulator suite and not at the real cloud:

```bash
"$ADB" -s $DRIVER logcat -d -s Headstart:I | grep 'Firebase target'
# Headstart: Firebase target = emulator 10.0.2.2
```

If it says `cloud`, someone flipped `Prefs.useCloud`. Turn it off in the app's debug Settings
row, or from the host: `adb shell run-as app.headstart rm /data/data/app.headstart/shared_prefs/headstart.xml`.

Pre-granting the two permissions means the OS prompts never appear. To see the **permission
flow itself** (location first, then notifications, one dialog at a time — never both at once),
skip the two `pm grant` lines on one device.

**Give the first launch after an install room to breathe.** Measured with `am start -W` on this
machine: `TotalTime` 11.2 s on Pixel_9a and 22.2 s on Pixel_10 (its 16 KB-page image is slower).
A scripted `install -r … && am start … && sleep 5` is *not* enough on Pixel_10 — the system kills
the process with `Killing <pid>:app.headstart (adj -10000): start timeout` before it finishes
starting, which looks like a crash but leaves no stack trace. Wait 20-25 s after an install, or
use `am start -W` and read `TotalTime`. Warm launches are a second or two.

## 4. Sign in on both AVDs

Walk the UI: **Get started → number → Send code → code → name → Allow and continue.**
Use a different number per device, and a number nobody else on this machine is using — the
iOS pipeline may be driving the same suite:

* driver `+880 1900005541`
* receiver `+880 1900005561`

No SMS is sent. Read the code on the host:

```bash
curl -s http://127.0.0.1:9099/emulator/v1/projects/$PROJECT/verificationCodes | python3 -m json.tool
```

The Verify screen shows that same curl command in a DEBUG banner, so you do not have to
remember it. Sign-in works with no SHA-1, no Play Integrity and no reCAPTCHA because
`HeadstartConfig` calls `setAppVerificationDisabledForTesting(true)`.

The name typed on the profile screen rides on `registerPushToken`, and that is how the server
fills `pairs/{pairId}.memberNames`. If you skip it, both apps will call the other person
"Your partner" forever.

## 5. Pair them

On the **driver**: Invite someone → a six-character code appears (e.g. `Y2SGVG`) with its
`headstart://pair/…` link.

On the **receiver**, either type the code into "Enter a code", or use the deep link, which is
also how you test it:

```bash
"$ADB" -s $RECEIVER shell am start -a android.intent.action.VIEW -d "headstart://pair/Y2SGVG"
```

Expected: the app opens on **"Enter their code"** with the six characters already filled in.
This works whether the app was closed (`onCreate`) or already running — `launchMode` is
`singleTask`, so a second link arrives at `onNewIntent`.

Tap **Pair**. Verify in the Emulator UI that `pairs/{id}` is now `status: "active"` with a
`memberNames` map holding *both* display names.

## 6. Create the pickup spot

On the receiver: **I'm waiting → manage spots → +**. Name it `Office`, tap **Use my current
location**, leave the headstart at **3 minutes**, Save.

Put the device at the spot first so "Use my current location" reads the right coordinates —
this is the destination the canned route ends at:

```bash
"$ADB" -s $RECEIVER emu geo fix 77.5946 12.9716     # LONGITUDE FIRST
```

The spot should appear on the *driver's* home screen within a second or two. That is the
Firestore listener working.

## 7. Start the trip and replay the route

Put the driver at the start of the canned route, then tap **I'm coming** in the app:

```bash
"$ADB" -s $DRIVER emu geo fix 77.5424 12.9206       # ~8 km out, LONGITUDE FIRST
```

Expected within 2 s: the ongoing notification **"Sharing with {name}"** appears, the driver's
screen becomes the trip screen, and the receiver gets a `started` alert.

Then replay the drive (see §8 first if you want the phase change to be visible):

```bash
cd "$REPO/android" && bash tools/replay_route.sh $DRIVER
```

Watch `trips/{id}/positions` grow at <http://127.0.0.1:4000/firestore>, or from the host:

```bash
TRIP=$(curl -s -H 'Authorization: Bearer owner' \
  "http://127.0.0.1:8080/v1/projects/$PROJECT/databases/(default)/documents/trips" \
  | python3 -c "import sys,json;print(json.load(sys.stdin)['documents'][-1]['name'].split('/')[-1])")
curl -s -H 'Authorization: Bearer owner' \
  "http://127.0.0.1:8080/v1/projects/$PROJECT/databases/(default)/documents/trips/$TRIP/positions?pageSize=200" \
  | python3 -c "import sys,json;d=json.load(sys.stdin)['documents'];print(len(d),'positions')"
```

`Authorization: Bearer owner` is the Firestore emulator's rules bypass. It is for *your*
inspection only — the app itself goes through the real rules.

## 8. See the far → near cadence change

**This step needs a manual nudge on an AVD, and here is exactly why.**

These AVD images have **no network location provider** (`dumpsys location` shows
`com.google.android.gms[network_location_provider] enabled=false`, and
`settings get secure location_providers_allowed` returns just `gps`). The contract's far phase
asks for `PRIORITY_BALANCED_POWER_ACCURACY`, which on such a device resolves to *nothing at
all*: `dumpsys location` shows `gps provider: service: ProviderRequest[OFF]`, no fixes are
delivered, and `adb emu geo fix` keeps answering `OK` while the app sees nothing. On a real
phone balanced power uses wifi and cell, so this is an emulator artefact, not an app bug.

The consequence is a chicken-and-egg: no fixes → the server never sets `phaseHint`, and the
phase never leaves `far`. Break it the way the contract itself allows — **transition rule 1,
"the server said so"** — by writing `phaseHint` once:

```bash
curl -s -X PATCH -H 'Authorization: Bearer owner' -H 'Content-Type: application/json' \
  "http://127.0.0.1:8080/v1/projects/$PROJECT/databases/(default)/documents/trips/$TRIP?updateMask.fieldPaths=phaseHint" \
  -d '{"fields":{"phaseHint":{"stringValue":"near"}}}'
```

Confirm the app reacted — this is the real `TrackingPhaseController` doing its job:

```bash
"$ADB" -s $DRIVER logcat -d '*:S' 'HsTracking:D' | tail -3
# HsTracking: location updates: LocationParams(priority=BALANCED, minIntervalMs=30000, minDisplacementM=200.0)
# HsTracking: location updates: LocationParams(priority=HIGH,     minIntervalMs=5000,  minDisplacementM=10.0)
"$ADB" -s $DRIVER shell dumpsys location | grep -A1 'gps provider:'
# service: ProviderRequest[@+5s0ms, HIGH_ACCURACY, WorkSource{... app.headstart}]
```

The phase latch is one-way, so when the server later recomputes `phaseHint: "far"` from the
real distance, the app correctly ignores it.

Now the position timestamps show the near cadence — consecutive `ts` values about **5 s** apart
(the far phase would be 30 s). Run the query in §7 and diff the timestamps.

`replay_route.sh` mirrors those cadences itself: it advances 250 m every 30 s while further
than `--near-band` (default 5040 m) from the spot, and 50 m every 5 s once inside. Compress a
run with `--step-seconds 3`; preview one without touching the AVD with `--dry-run`.

## 9. Check the alert ladder and the two channels

**Server decisions.** Every push the server *would* have sent is written to `_debugPushes`
(FCM cannot deliver from the emulator), and each app's debug-only `DebugPushBridge` feeds those
rows into the same renderer a real FCM message takes:

```bash
curl -s -H 'Authorization: Bearer owner' \
  "http://127.0.0.1:8080/v1/projects/$PROJECT/databases/(default)/documents/_debugPushes?pageSize=50" \
  | python3 -c "
import sys,json
for d in sorted(json.load(sys.stdin)['documents'], key=lambda x:int(x['fields']['sentAt']['integerValue'])):
    f=d['fields']; print(f['kind']['stringValue'], f['androidChannelId']['stringValue'], f['urgent']['booleanValue'], f['title']['stringValue'])"
```

Expected over one drive: `started`, `tenMin`, `leadTime`, `arrived` — and **`leadTime` is the
only row with `urgent: true` and `androidChannelId: sync_urgent`**. `didYouLeave` and `slip`
also appear if the replay stalled or the ETA moved.

```bash
"$ADB" -s $RECEIVER logcat -d '*:S' 'HsDebugPush:I' 'HsPush:I' | tail
# HsDebugPush: server push replayed: {kind=leadTime, tripId=..., title=Start walking now, ...}
# HsPush     : push kind=leadTime channel=sync_urgent id=2002
```

**Rendering of all thirteen kinds.** The bridge only replays the kinds a drive happens to
produce. To render any kind on demand, use the debug broadcast injector:

```bash
for K in started tenMin leadTime slip arrived lost timeout cancelled \
         didYouLeave armed noShow runningLate reply; do
  "$ADB" -s $DRIVER shell am broadcast \
    -n app.headstart/app.headstart.debug.PushInjectorReceiver \
    -a app.headstart.DEBUG_PUSH -e kind $K -e title "T-$K" -e body "B-$K"
done
"$ADB" -s $DRIVER shell dumpsys notification --noredact \
  | grep -oE 'pkg=app.headstart.*(importance=[0-9]).*channel=[a-z_]+'
```

Expected: exactly one notification on `channel=sync_urgent` with `importance=4` (that is
`leadTime`), and every other kind on `channel=sync_updates` with `importance=3`.
`didYouLeave` additionally raises the "Did you actually leave?" bottom sheet over whatever the
driver is looking at.

Both the injector and the bridge live in `app/src/debug/` and cannot exist in a release build.

## 10. Ending the trip

Tap **I'm here** on the driver (or **Cancel**).

Expected, in this order:
* `trips/{id}.state` becomes `arrived` (or `cancelled`);
* the **ongoing "Sharing with …" notification disappears** — the foreground service stops
  itself from its own trip listener the moment `state` leaves `driving`; nothing in the UI
  calls `stop()`;
* the driver's screen returns to Home and the role switch goes back to the last choice the
  user made;
* the receiver gets an `arrived` push on `sync_updates` and returns to their own Home.

```bash
"$ADB" -s $DRIVER shell dumpsys activity services app.headstart | head -3   # expect no ServiceRecord
"$ADB" -s $DRIVER shell dumpsys notification --noredact | grep -c 'id=1001' # expect 0
```

---

## Known emulator-only limitations

| Symptom | Cause | What to do |
|---|---|---|
| Far phase never delivers a fix; `positions` stops growing | AVD has no network location provider, so `BALANCED` starts no provider at all | §8 — write `phaseHint: "near"` once. Real phones are unaffected. |
| `adb emu geo fix` returns `OK` but nothing moves | Same as above | Check `dumpsys location \| grep -A1 'gps provider:'`. `ProviderRequest[OFF]` means nothing is listening. |
| The first interesting ETA is swallowed | `smoothEta` holds a reading that jumps more than `max(120 s, 25 %)` within 15 s of `startTrip` | Let the ETA walk down gradually, which is what `replay_route.sh` does. |
| A burst of fixes is silently dropped | `onPositionWrite` drops any fix whose `ts <= trip.lastPos.ts`, equal included | Keep timestamps strictly increasing. |
| `housekeeping` never runs | `onSchedule` becomes a Pub/Sub trigger and Pub/Sub is not emulated | Drive it by hand: `curl "http://127.0.0.1:5001/$PROJECT/us-central1/debugRunHousekeeping?now=$(date +%s000)"` |
| Route polylines look wrong | The emulator's stub router emits a two-vertex polyline | Cosmetic; the ETA ladder does not use it. |

## What this run does not prove

Background location with the screen locked, real FCM delivery (`_debugPushes` is a stand-in),
real SMS OTP, real Google Routes calls, real battery drain over a 25-minute drive, OEM
background-kill behaviour on Xiaomi/OnePlus/Oppo/vivo, and `firebase deploy`. Those stay in
`docs/testing/real-drive-checklist.md` for a human with two phones and a car.

**No agent may report "M1 verified" without repeating this caveat.**
