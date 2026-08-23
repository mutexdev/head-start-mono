# Headstart — iOS

SwiftUI, Swift 6 language mode, deployment target iOS 17.0, built against the iOS 26.5 SDK
(Xcode 26.6). Firebase Auth / Firestore / Functions / Messaging, pinned to **12.18.0**.

`docs/CLIENT_CONTRACT.md` is the law for the wire format and
`docs/CLIENT_CONTRACT_ADDENDUM.md` resolves everything it left ambiguous — the addendum wins
over any plan doc, on all three platforms.

---

## 1. Quick start

```bash
brew install xcodegen                 # 2.46.0 here
cd ios
make test                             # xcodegen generate + xcodebuild test
bash scripts/emulator-up.sh --detach  # reuses a running suite if there is one
bash scripts/e2e-drive.sh             # the headless drive; exit 0 == everything passed
```

`Headstart.xcodeproj` is **generated** from `project.yml` and gitignored. Never commit it and
never edit it. Adding a source file is "write the file into the target's folder, then
`make project`" — there is no target-membership step.

| command | what it does |
|---|---|
| `make project` | regenerate `Headstart.xcodeproj` from `project.yml` |
| `make test` | regenerate, build, run every XCTest suite on iPhone 17 Pro / iOS 26.5 |
| `make fonts` | regenerate the four static Archivo faces with fontTools |
| `bash scripts/check-push-fixtures.sh` | validate the thirteen `.apns` payloads |
| `bash scripts/emulator-up.sh [--detach]` | start or reuse the Firebase emulator suite |
| `bash scripts/e2e-drive.sh` | the headless end-to-end drive (this is the batch's test) |

Everything standardises on `-destination 'platform=iOS Simulator,name=iPhone 17 Pro,OS=26.5'`.
`xcodebuild -showsdks` lists only `iphonesimulator26.5` on this machine, so the plan's
`iPhone 16` destination does not exist here; the 17.0 deployment target is unaffected.

---

## 2. Layout

```
Headstart/
  HeadstartApp.swift        @main — hands the scene to RootView behind ServiceLocator
  AppDelegate.swift         FirebaseApp.configure, emulator wiring, every APNs callback
  Core/                     BackendEnvironment, Callables, FirestoreStreams, HeadstartError,
                            PartnerName, PhoneNumber, Polyline, ServiceLocator, Format
  Data/                     Auth / Pair / Spot / Trip repositories, models, position sink
  Tracking/                 LocationTracker + the pure TrackingPhaseController, ETA, battery
  Push/                     PushService, PushRouter, PushPayload, DebugPushBridge (#if DEBUG)
  LiveActivity/             LiveActivityController + the shared ActivityAttributes
  Theme/                    HS tokens, Archivo typography
  UI/                       stateless screens, plus AppViewModel / RootView / HomeView
  DriveRoute.gpx            the real-device drive route (Xcode's location simulation)
HeadstartWidget/            the Live Activity presentation
HeadstartTests/             XCTest — pure logic only, no simulator services
fixtures/push/*.apns        the thirteen contract push payloads
scripts/                    make-fonts, check-push-fixtures, emulator-up, e2e-drive
scripts/stub-backend/       a cold-spare emulator config, used only if functions/ is missing
```

`AppViewModel` is the only object that owns state. Screens are stateless: they take plain
values and closures, which is why they could be written in any order and why they preview
without Firebase.

---

## 3. Backend switch

`Core/BackendEnvironment.swift` resolves, highest precedence first:

1. `HSUseEmulator` (`-HSUseEmulator NO` forces real cloud, no rebuild)
2. `HS_EMULATOR_HOST` environment variable
3. `HSEmulatorHost` UserDefaults string (`-HSEmulatorHost 10.0.0.5`)
4. `#if HS_EMULATOR`, which Debug sets and Release does not

So a Debug build talks to the Local Emulator Suite by default (auth 9099 / firestore 8080 /
functions 5001, `127.0.0.1` from the Simulator) and a Release build talks to real Firebase.
`AppDelegate` prints `[HS] backend=emulator host=…` or `[HS] backend=cloud` at launch.

`scripts/emulator-up.sh` prefers the REAL backend (`<repo>/firebase.json` + `functions/`)
and falls back to `scripts/stub-backend/` only when the backend has not landed. It **reuses**
a suite already listening on 8080 rather than starting a second one — three pipelines share
this machine and there must only ever be one suite on the contract's ports.

---

## 4. Launch arguments (Debug builds)

| argument | effect |
|---|---|
| `-HSEmulatorHost 127.0.0.1` | point Auth/Firestore/Functions at that host |
| `-HSUseEmulator NO` | force real Firebase |
| `-HSFakeEta 900` | swap `MapKitEtaProvider` for a constant-ETA fake (deterministic drives) |
| `-HSFakeBatteryPct 9` | swap `DeviceBatteryProvider` for a fake — the only way to reach the contract's "< 15 %" row, since `UIDevice.batteryLevel` is −1 on a Simulator |
| `-HSAutoSignIn +15555550100` | **DEBUG + emulator only**: the `E2EAutopilot` test harness |
| `-HSAutoName`, `-HSAutoPair`, `-HSAutoSpot`, `-HSAutoSpotName`, `-HSAutoStartTrip` | the rest of the autopilot's script |

### Why the app contains an autopilot

`xcrun simctl` can boot, install, grant privacy, push a notification, move the device and read
the log stream. **It cannot tap.** A headless drive can therefore drive the world around the
app but not the app itself. `Headstart/UI/E2EAutopilot.swift` (all inside `#if DEBUG`, inert
unless an emulator host *and* `-HSAutoSignIn` are both present) closes that gap by calling the
**same `AppViewModel` methods the buttons call** — sign-in, profile, `createPair`,
`upsertSpot`, `startTrip`. Nothing product-shaped is reimplemented, so a bug in any of those
fails the drive exactly as a human tap would. It is absent from Release builds.

---

## 5. The headless drive (`scripts/e2e-drive.sh`)

This is the substitute for plan Task 20, whose Step 2 needs Xcode's "Edit Scheme → Core
Location" GUI and whose Steps 3–4 need a physical iPhone, a paid Apple team and a second
phone. It runs 34 assertions and exits non-zero on any failure.

1. resolve the iPhone 17 Pro / iOS 26.5 simulator by name + runtime (never a hard-coded UDID),
   boot it, install the Debug build, `simctl privacy grant location`
2. seed the second person — sign `+15555550101` in over the Auth emulator's REST API and
   `registerPushToken` both identities so `pairs/{id}.memberNames` carries real names
3. launch as the driver: `[HS] backend=emulator`, phone OTP with the code read from
   `GET /emulator/v1/projects/fin-e8358/verificationCodes`, `createPair`, the harness accepts
   the code as the receiver, `upsertSpot` at 23.7806/90.4193, `startTrip`
4. `xcrun simctl location <udid> start --speed 12 …` — the same Dhaka waypoints as
   `Headstart/DriveRoute.gpx`, ~3.3 km, ~4½ minutes
5. arrival: nudge the device between two points ~20 m apart inside the spot radius so
   CoreLocation keeps delivering, until the **server** flips `trips/{id}.state` to `arrived`
6. `xcrun simctl push` the `started` / `tenMin` / `leadTime` / `arrived` fixtures and assert
   `[HS][push] kind=…` for each
7. read `trips/{id}/positions` back and assert: only the contract's keys, **every** document
   carries `etaSec`, `routingCalls == 0`, no `routePolyline`, and the cadence tightens once
   `phaseHint` flips to `near`
8. relaunch as the **receiver** and have the harness drive a trip from the other side, so the
   Live Activity (`[HS][la] started` / `ended`) and the `_debugPushes` bridge
   (`[HS][debugpush] kind=started`) are both proven

Measured on this machine: 150 position documents, 150 with `etaSec`, median gap 17.1 s in
`far` and 1.0 s in `near`, `routingCalls: 0`.

> **Cadence, honestly.** The contract's rows are "30 s / 200 m" in `far` and "5 s / 10 m" in
> `near`, and the client uploads when **either** condition is met. At 12 m/s the 200 m
> displacement wins in `far` (~17 s) and the 10 m one wins in `near` (~1 s). The assertion is
> that the cadence *tightens*, not that it equals 30 and 5.

### Log lines anything may assert on

```
[HS] backend=emulator host=…              [HS][push] kind=<kind> tripId=<id>
[HS][trip] startTrip tripId=… existing=…  [HS][debugpush] kind=… urgent=… toUid=…
[HS][la] started|updated|ended id=…        [HS][e2e] step=…
[HS][perm] notifications=… location=…      [HS][track] started trip … near=…m
```

---

## 6. What the Simulator and the emulator CANNOT prove

None of this is papered over with a green test. All of it belongs to
`docs/testing/real-drive-checklist.md`, whose **iOS results section is filled in by a human on
a device** — that file is orchestrator/backend-owned and nothing in this directory edits it.

* **Background location with the screen locked**, and the blue background-location indicator.
  A Simulator does not lock, does not suspend the app the way a phone does, and never shows
  the indicator. `UIBackgroundModes: [location]` and `allowsBackgroundLocationUpdates` are set
  and compile-verified; that they keep the uploads alive is device-only.
* **Real APNs / FCM delivery.** There is no `.p8` key and no paid team.
  `Messaging.register()` fails on a Simulator (`[HS][push] fcm-token-unavailable`), so
  **`registerPushToken` never fires there** and a display name never reaches the server from
  the app — the drive's harness calls it instead so partner names render. On a device the app
  does it itself. `xcrun simctl push` proves *rendering and routing* of all thirteen kinds;
  the `_debugPushes` bridge proves the server's *decisions*; neither proves the network.
* **Notification permission.** `xcrun simctl privacy` in Xcode 26.6 has **no `notifications`
  service** (`grant notifications` fails with "Operation not permitted"), so the system prompt
  cannot be answered headlessly. The drive starts the real `completeProfile` and moves on;
  everything it asserts works without the grant, because the `.apns` fixtures carry
  `content-available: 1` and reach `application(_:didReceiveRemoteNotification:…)` regardless.
  That also means `willPresent` / `didReceive` are **not** exercised by the drive.
* **A Live Activity on a real Lock Screen or Dynamic Island.** `[HS][la] started/ended` proves
  the controller's lifecycle and `LiveActivityStateTests` proves the state model, but the
  rendering is only ever seen in the widget `#Preview`s.
* **Battery drain over a trip.** `UIDevice.batteryLevel` is −1 on a Simulator; the "< 15 %"
  behaviour is reachable only through `-HSFakeBatteryPct`.
* **Settings → Headstart → Time Sensitive Notifications.** That switch only exists when the
  `com.apple.developer.usernotifications.time-sensitive` entitlement is signed by a paid team.
  `Headstart/Headstart.entitlements` is written and correct; the Release config points at it.
* **Real SMS OTP, real Google Routes calls, and `firebase deploy`.**

### Signing, and why Debug is ad-hoc signed

`CODE_SIGNING_ALLOWED = NO` leaves the binary with no entitlements blob at all, and then every
`SecItemAdd` fails with **−34018**. FirebaseAuth persists the signed-in user in the keychain,
so `Auth.signIn(with:)` returns `FIRAuthErrorDomain 17995 / ERROR_KEYCHAIN_ERROR` and **phone
sign-in cannot complete** — observed on iPhone 17 Pro / iOS 26.5 with Firebase 12.18.0. Debug
therefore uses `CODE_SIGN_IDENTITY = "-"` ("Sign to Run Locally") plus
`Headstart/HeadstartSimulator.entitlements`, which contains only `application-identifier` and
`keychain-access-groups`. Still no team, no profile, and no real capability: `aps-environment`
and the time-sensitive key stay in `Headstart.entitlements`, which only Release uses.

---

## 7. The GPX route

`Headstart/DriveRoute.gpx` exists for the **real-device** run only. In Xcode:
Product → Scheme → Edit Scheme → Run → Options → Core Location → Allow Location Simulation →
`DriveRoute`, and Debug → Simulate Location while running. Both are GUI-only, which is why
`scripts/e2e-drive.sh` uses `xcrun simctl location … start --speed 12` with the identical
waypoints. **If you change a waypoint in one, change it in the other.**

---

## 8. A rules trap worth knowing about

The contract's active-trip query is `trips where pairId == … and state in ["armed","driving"]`.
Firestore synthesises `resource` for a **list** from the query's own constraints, so a `trips`
rule that dereferences `resource.data.driverUid` in a combined `allow read` rejects the whole
query with `Property driverUid is undefined on object. for 'list'` — and the active-trip
stream then silently never delivers: no trip screens, no Live Activity, and no error a user
can see. Both client pipelines hit this on their end-to-end drives. `firestore.rules` now
splits `get` from `list` and the `list` half is `isMember(resource.data.pairId)`.
`Headstart/Data/TripRepository.swift` carries the full note; the client keeps the contract's
query and must not be "fixed" with ownership filters.

## 9. Known deviations from the plan doc

* Task 1 and Task 17 Step 3 (Xcode GUI walkthroughs) are replaced by `project.yml` + XcodeGen.
* Task 20's location-simulation and physical-device steps are replaced by `simctl` automation
  plus this file's honest limits list.
* Blanket `@preconcurrency import` on Firebase files is dropped; imports are clean and the
  target builds with zero concurrency warnings under Swift 6.
* Archivo static faces are generated with fontTools (`make fonts`) rather than downloaded
  through a browser.
