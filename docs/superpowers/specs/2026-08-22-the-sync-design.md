# The Sync — Design Spec (2026-08-22)

## Problem
A driver picks someone up from a fixed spot (e.g. partner from office). The receiver needs a few minutes to walk to the pickup spot. Today: "come pick me" → "coming" → 20-min drive → receiver has no idea when to start walking. The Sync gives the receiver automatic, trustworthy ETA alerts, including a receiver-configured "N minutes away — start walking now" alert.

## Decisions (approved)
- Multi-user from day one (phone OTP sign-in, pair via invite code/link).
- Native clients: iOS (Swift/SwiftUI), Android (Kotlin/Jetpack Compose).
- Backend: Firebase — Auth (phone), Firestore, Cloud Functions (TypeScript), FCM, Scheduled Functions.
- Routing: Google Routes API (Compute Routes v2, traffic-aware; 10k free calls/month) behind a `RoutingProvider` interface in Cloud Functions, so it can be swapped for self-hosted Valhalla later. **iOS drivers compute ETA on-device with MapKit `MKDirections.calculateETA` (free, traffic-aware) and attach `etaSec` to each position; the server skips its routing call when present.** Android drivers rely on the server call.
- Full feature set is v1, built in four ordered milestones (M1–M4). M1 is real-drive testable.

## 1. Architecture
Thin native clients; one server-side `TripEngine` makes all alert decisions so both platforms behave identically and alerts fire even if the receiver's app is closed.

```
iOS / Android app ──(Auth, Firestore writes, callables)──▶ Firebase
                                                         ├─ Firestore (state, realtime listeners)
                                                         ├─ Cloud Functions: callables + onPositionWrite + schedulers
                                                         │     └─ RoutingProvider → Google Routes API (ETA, polyline); bypassed when client sends etaSec
                                                         └─ FCM → APNs / Android (alerts, Live Activity pushes)
```

Research backing these choices: `docs/research/2026-08-22-feasibility-and-market.md`.

## 2. Data model (Firestore)
```
users/{uid}        phone, displayName, platform: ios|android, fcmTokens: string[],
                   liveActivityPushToken?: string, lowBattery?: bool, createdAt
pairs/{pairId}     members: [uidA, uidB], status: pending|active|revoked,
                   inviteCode (6 chars, unique while pending), createdBy, createdAt
spots/{spotId}     pairId, name, lat, lng, radiusM (default 100), leadTimeMin (receiver-set, default 3),
                   createdBy, createdAt
trips/{tripId}     pairId, driverUid, receiverUid, spotId,
                   state: armed|driving|arrived|cancelled|timeout|lost,
                   createdAt, startedAt?, endedAt?,
                   eta: { seconds, updatedAt, approximate: bool }, routePolyline?,
                   bands: { far: metersFromDest, near: metersFromDest, lead: metersFromDest },
                   lastPos: { lat, lng, accuracyM, speedMps, ts },
                   alerts: { started, tenMin, leadTime, arrived, didYouLeave: bool, slipCount: number,
                             lastSlipEtaSec?: number },
                   fuzzy: bool, neededBy?: timestamp, lastRoutingCallAt?, routingCalls: number,
                   phaseHint: far|near, leadTimeMin (snapshot), receiverView: { etaSeconds, progressPct, lastPos? }
trips/{tripId}/positions/{autoId}   lat, lng, accuracyM, speedMps, ts, etaSec? (on-device ETA), expireAt (TTL 30 days)
trips/{tripId}/replies/{autoId}     fromUid, kind: fiveMore|takeYourTime|atSpot|runningLate|custom, text?, ts
schedules/{id}     pairId, spotId, driverUid, receiverUid, days: [0-6], timeLocal "HH:mm", tz, enabled, lastFiredDate?
```
Security rules: a user may read/write only docs where they are a pair member; trip fields other than `lastPos` and `positions` are written by Functions only (clients write via callables).

## 3. Cloud Functions
Callables (all verify pair membership):
- `createPair` → inviteCode; `acceptPair(code)`; `revokePair(pairId)`.
- `upsertSpot`, `deleteSpot`. Either pair member can edit a spot; a trip snapshots `leadTimeMin` at start.
- `startTrip(spotId, fuzzy?)`: creates trip `driving`, calls the routing provider once, stores eta/polyline/bands, pushes **started** to receiver, returns `{tripId, bands, etaSeconds}`.
- `armTrip(spotId)` (receiver): creates trip `armed`, pushes driver "X is waiting — tap when you leave". `startTrip` on an armed trip transitions it to `driving`.
- `endTrip(tripId, reason: arrived|cancelled)`.
- `sendReply(tripId, kind, text?)`, `setRunningLate(tripId, extraMin)`, `setNeededBy(tripId, ts)`.
- `registerPushToken`, `registerLiveActivityToken`, `deleteAccount`.

Triggers:
- `onPositionWrite` (trips/{id}/positions/{pid}): runs `TripEngine.step(trip, position, now)` → decides whether to call the routing provider (skipped if the position carries `etaSec`) (throttle: 60 s if ETA > 10 min, 30 s if 5–10 min, 15 s if < 5 min; also immediately on first near-phase position), updates `trip.eta`/`lastPos`, emits alerts, and emits a Live Activity update if ETA changed by ≥ 60 s.
- `onTripLost` (scheduled every minute): trips in `driving` with `lastPos.ts` older than 5 min → state `lost`, push both sides "Connection lost". Trips older than 3 h → `timeout`. Trips `armed` for > 15 min past `neededBy` (or 15 min after arming when no `neededBy`) → push receiver "No trip started yet" (once).
- `onSchedule` (scheduled every minute): for each enabled schedule matching today/time in its tz and not yet fired today, push driver an actionable notification "Pickup {name} at {time} — Start trip?" (action = startTrip). No silent auto-tracking.
- `onLeaveBy` (inside `onSchedule` tick): trips `armed` with `neededBy`: compute routing ETA from driver's last known position (if driver app shares a coarse position while armed; else skip) and push "Leave in N min to arrive by {time}" once when leave-by ≤ 5 min away.

### TripEngine (pure, unit-tested)
Input: trip doc, new position, now, optional fresh ETA. Output: patch to trip + list of pushes.
- ETA smoothing: reject a fresh ETA if it changes by more than max(120 s, 25 %) within 15 s of the last one unless two consecutive readings agree.
- Movement verification: if `now − startedAt ≥ 3 min` and no position ≥ 150 m from the start position → set `alerts.didYouLeave`, push driver "Did you leave? Tap to confirm or cancel". Receiver's **started** push is sent at `startTrip` regardless (user decision: started is sent immediately; didYouLeave only prompts the driver).
- Alert ladder (each fires once unless re-armed):
  - `tenMin`: etaSec ≤ 600.
  - `leadTime`: etaSec ≤ leadTimeMin×60. Text: "Start walking now — {driver} is {m} min away".
  - `slip`: after `tenMin` fired, if new etaSec − lastSlipEtaSec (or eta at tenMin time) ≥ 120 → push "Traffic — now {m} min, stay inside", `slipCount++`. If `leadTime` had fired and etaSec > (leadTimeMin+2)×60 → re-arm `leadTime`.
  - `arrived`: within `spot.radiusM` and speed < 2 m/s for ≥ 20 s, or `endTrip(arrived)`. Push "{driver} has arrived". End trip.
- Low battery: if `users/{driver}.lowBattery`, mark `eta.approximate = true`; pushes append "(approx.)".
- Routing failure: fallback ETA = remaining polyline distance / max(avg speed last 2 min, 8 m/s), `approximate = true`.

Push copy lives in one `messages.ts` file; all pushes are idempotent via transactional updates on `trip.alerts`.

## 4. Native tracking (identical algorithm both platforms)
Phases: `far` → `near` → `ended`.
- Start: app in foreground, user taps "I'm coming" (or Siri/Assistant intent). App calls `startTrip`, receives `bands`, starts tracking.
- `far`: low accuracy (iOS `kCLLocationAccuracyHundredMeters`, distanceFilter 200 m; Android `PRIORITY_BALANCED_POWER_ACCURACY`, 200 m / 30 s). Upload each fix.
- Switch to `near` when straight-line distance to spot ≤ `bands.near` (ETA−12 min equivalent) OR server sets `trip.phaseHint = near` (read via listener).
- `near`: iOS `kCLLocationAccuracyBestForNavigation`; Android `PRIORITY_HIGH_ACCURACY`; upload every 5 s (batched if offline, replayed in order).
- Destination geofence (spot radius) as backup arrival: iOS `CLCircularRegion`, Android Geofencing API.
- Stop tracking immediately on trip end (listener on trip.state) or local end.
- iOS: `UIBackgroundModes: location`, "When In Use" + `allowsBackgroundLocationUpdates = true`, `showsBackgroundLocationIndicator = true`. No "Always".
- Android: `ForegroundService` with `foregroundServiceType="location"`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION`, `POST_NOTIFICATIONS`. No `ACCESS_BACKGROUND_LOCATION`. Show dontkillmyapp guidance once on Xiaomi/Huawei/OnePlus/Oppo.
- Low battery (< 15 %): stay in `far` cadence; set `users.lowBattery = true`.
- Fuzzy mode: client still uploads exact positions (server needs them for ETA); server omits `lastPos` from the receiver-visible projection (`trips/{id}.receiverView`) until ETA ≤ 5 min.

## 5. Receiver surfaces
- Pushes: started, tenMin, leadTime (time-sensitive/high-priority channel, distinct sound, user-toggleable), slip, arrived, lost, no-show, driver replies (runningLate).
- iOS Live Activity (WidgetKit extension): started via push-to-start (iOS 17.2+) on `started`; shows driver name, countdown via `Text(timerInterval:)`, progress bar; updated by APNs `liveactivity` push when ETA changes ≥ 60 s; ended on arrival. Dynamic Island compact = minutes left.
- Android: ongoing notification bound to the trip with ETA text + progress; `Notification.ProgressStyle` on API 36+.
- In-app: live map (driver dot unless fuzzy, route polyline, ETA), quick-reply bar: "5 more min", "Take your time", "I'm at {spot name}", custom text. Replies push to driver with spoken-friendly text.
- Watch/Wear OS: notification mirroring only.

## 6. Driver surfaces
- Home: spots list with one large "I'm coming → {spot}" button per spot; "Ping me when they leave" requests appear as banner.
- Siri App Intent (iOS) / App Shortcut + Assistant (Android): "Tell {name} I'm coming" → `startTrip` for the pair's default spot, speaks confirmation, no UI needed. CarPlay/Android Auto: not a car app; relies on intents + notifications.
- During trip: ETA, "Running late" (+5/+10/+15 → `setRunningLate`, receiver push "Running late — about {m} more min"), "I'm here", "Cancel". Receiver replies shown as notifications.

## 7. Scheduling, reverse trigger, calendar
- Schedules (per pair+spot): days, local time; at time → actionable push to driver (Start trip / Skip). Never auto-tracks.
- Reverse trigger: receiver "Ping me when they leave" → `armTrip`; driver push; on `startTrip` receiver gets **started**. No-show push after 15 min (or 15 min past `neededBy`).
- Calendar leave-by: receiver sets `neededBy` on an armed trip; driver's app, while a trip is armed for them, shares a coarse position every 5 min (foreground or via the same FGS/background mode, only while armed and only if driver accepted the arm request) so server can push "Leave in N min". If driver declines, feature silently degrades.

## 8. Pairing & privacy
- Sign-in: Firebase phone OTP. Display name set once.
- Pairing: `createPair` → 6-char code shown as text, share link (`thesync://pair/{code}` + universal link), and QR. NFC: Android writes/reads NDEF with the link; iOS reads via Core NFC. `acceptPair` completes.
- Trip-scoped sharing only; "Sharing active" banner on both sides; either can end a trip or revoke the pair.
- Positions TTL 30 days; `deleteAccount` wipes user, pairs, spots, trips where member.
- No "location active" nags beyond the OS-required indicator/FGS notification.

## 9. Error handling
- Invalid FCM token → prune; in-app "Notifications not working" check (test push button).
- Offline driver → local buffer, ordered replay; server `lost` after 5 min; resumes to `driving` if positions return before timeout.
- Duplicate taps → `startTrip` rejects if an active trip exists for the pair (returns existing).
- Routing quota/outage → fallback ETA (approximate) + Cloud Logging alert.
- All callables return typed error codes: `not-paired`, `trip-active`, `spot-not-found`, `rate-limited`.

## 10. Testing
- Functions: Jest unit tests for `TripEngine` (table-driven: ladder order, hysteresis, re-arm, slip, low battery, movement check, fallback ETA). Firestore emulator integration tests for callables + rules. Routing provider stubbed.
- iOS: XCTest for `TrackingPhaseController` and offline buffer; GPX simulated drives for UI tests.
- Android: JUnit for the same controller; emulator route playback.
- Per-milestone manual real-drive checklist (documented in `docs/testing/real-drive-checklist.md`).

## 11. Milestones (one v1 release)
- **M1 Core loop** — Functions project, auth, pairing (code/link), spots, startTrip/endTrip, TripEngine, hybrid tracking on both platforms, pushes: started/tenMin/leadTime/slip/arrived/lost. Real-drive testable.
- **M2 Surfaces** — Live Activity, Android ongoing/ProgressStyle notification, in-app map, quick replies, running late, Siri/Assistant intents, notification test button.
- **M3 Automation** — schedules, reverse trigger + no-show, neededBy leave-by.
- **M4 Polish** — fuzzy mode, QR/NFC pairing, low-battery mode, deleteAccount + TTL, OEM battery guidance, store listing/privacy labels.

## Repo layout
```
the-sync/
  functions/        TypeScript Cloud Functions (+ tests), firestore.rules, firestore.indexes.json
  ios/              Xcode project: TheSync app + TheSyncActivity widget extension
  android/          Gradle project: app module
  docs/             research, specs, plans, testing checklists
  firebase.json, .firebaserc
```
