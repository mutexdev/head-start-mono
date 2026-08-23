# Headstart backend (Cloud Functions + Firestore)

Firebase project **`fin-e8358`**, region **`us-central1`** (pinned via `setGlobalOptions`, so callable
URLs are deterministic).

`docs/CLIENT_CONTRACT.md` is the law for the wire format; `docs/CLIENT_CONTRACT_ADDENDUM.md` resolves
everything it left ambiguous and wins over any plan doc. **This file is the operational half**: how to
run the backend, and everything the iOS and Android sides need in order to talk to it.

> **The emulator is the primary path.** Blaze billing, a Google Routes API key, an APNs `.p8`, a paid
> Apple team, real phones and SMS are all unavailable here, so M1 is validated 100 % against the
> Firebase Local Emulator Suite. `npm run deploy` exists but has **never been run** — see
> [Production path (blocked)](#production-path-blocked).

---

## 1. Quick start

```bash
cd functions
npm install
npm run drive:happy   # boots the suite, drives one trip, asserts the whole alert ladder, tears down
```

Expected tail (≈ 60 s wall clock, of which ~34 s is the drive itself):

```
  _debugPushes for "happy" (4 rows, ordered by sentAt)
  t+     kind      to        urgent  channel       body
  0.8s   started   receiver  -       sync_updates  ETA 11 min to Office
  2.2s   tenMin    receiver  -       sync_updates  Mostafi is 10 min away
  7.0s   leadTime  receiver  URGENT  sync_urgent   Mostafi is 3 min away
  30.6s  arrived   receiver  -       sync_updates  Waiting at Office
  ...
  PASS  scenario "happy" (eta=client) — 18/18 assertions passed
```

### npm scripts

```bash
npm run build       # tsc
npm test            # unit suites            (jest.config.js; ignores *.emulator.test.ts)
npm run test:emu    # boots the suite, then  jest -c jest.emulator.config.js
npm run emu:start   # LONG-RUNNING suite — use this while developing a client app
npm run emu:exec -- "<cmd>"   # boot, run <cmd> against the suite, tear down
npm run drive:happy # one trip, full ladder
npm run drive       # every scenario (~70 s of scenarios + boot)
npm run deploy      # BLOCKED AND UNTESTED
```

`emu:start` and `emu:exec` both run `scripts/bootstrapEmulatorEnv.js` and `tsc` first.

---

## 2. Emulator contract — what the client apps connect to

Binding on all three platforms (`CLIENT_CONTRACT_ADDENDUM.md`, "Fixed ports").

| Emulator | Port | From macOS host / iOS Simulator | From an Android AVD |
|---|---|---|---|
| Auth | 9099 | `127.0.0.1:9099` | `10.0.2.2:9099` |
| Firestore | 8080 | `127.0.0.1:8080` | `10.0.2.2:8080` |
| Functions | 5001 | `127.0.0.1:5001` | `10.0.2.2:5001` |
| Emulator UI | 4000 | <http://127.0.0.1:4000> | — |

The AVD reaches the host loopback as `10.0.2.2`; the iOS Simulator shares the host's `127.0.0.1`.
Ports are fixed in `firebase.json` with `singleProjectMode: true`, and Firestore/Auth/Functions are
flagged "do not find another port" in firebase-tools, so a conflict fails loudly instead of silently
moving.

**Callable base URL** — the region pin is what makes this deterministic:

```
http://127.0.0.1:5001/fin-e8358/us-central1/<name>
```

Callables use the standard envelope: `POST {"data": {...}}` with
`Authorization: Bearer <ID token>` → `200 {"result": {...}}`, or a non-200 with
`{"error":{"message":"<contract error code>","status":"<gRPC status>"}}`.
**The contract's error codes are the `message`, not the status** — clients switch on `message`.

The twelve M1 callables (addendum A):
`registerPushToken`, `createPair`, `acceptPair`, `revokePair`, `upsertSpot`, `deleteSpot`,
`startTrip`, `armTrip`, `endTrip`, `sendReply`, `setRunningLate`, `setLowBattery`.

### Phone sign-in without SMS

The Auth emulator accepts **any** phone number and never sends an SMS.

* Preferred, per platform SDK: iOS `Auth.auth().settings?.isAppVerificationDisabledForTesting = true`
  (plus `useEmulator(withHost:port:)`); Android `FirebaseAuth.getInstance().firebaseAuthSettings`
  → `setAppVerificationDisabledForTesting(true)` and, if you want a fixed code,
  `setAutoRetrievedSmsCodeForPhoneNumber(...)` / the console's test phone numbers.
* Or read the code the emulator generated:

```bash
curl -s http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes
```

* Scripts (not apps) can skip phone auth entirely — `scripts/lib/emuClient.js` does
  `createUser → createCustomToken → POST accounts:signInWithCustomToken?key=fake-api-key`. The
  literal string `fake-api-key` is accepted by the Auth emulator.

### Seeded test identities

`npm run drive` wipes and re-seeds these every scenario. Sign either app in with the same number and
it lands on the same account.

| Role | Phone | Display name | uid (script only) | Push token |
|---|---|---|---|---|
| Driver | `+15550001111` | Mostafi | `emu-driver` | `emu-driver-token-0000000001` |
| Receiver | `+15550002222` | Sara | `emu-receiver` | `emu-receiver-token-0000000001` |

A real app signing in by phone gets a Firebase-assigned uid instead — pair the two apps through
`createPair` / `acceptPair` as usual. `registerPushToken` requires a token of **≥ 20 characters**
(`bad-token` otherwise); in the emulator any placeholder string of that length is fine.

The demo spot is `Office`, `37.7749, -122.4194`, `leadTimeMin 3`, `radiusM 100`, and the drive starts
~6.25 km away at `37.7349, -122.4694`.

---

## 3. `_debugPushes` — how clients observe pushes without FCM/APNs

FCM cannot deliver from the emulator and there is no APNs key, so `PushSender` writes the payload FCM
*would* have carried to `_debugPushes/{autoId}` whenever `FUNCTIONS_EMULATOR === 'true'` or
`PUSH_SINK=firestore`. **This is the only way the server-decided alert ladder is observable on a
Simulator or AVD.**

**Both clients MUST ship a debug-only bridge** (`#if DEBUG` / `debug` source set) that listens to

```
_debugPushes  where toUid == <my uid>  orderBy sentAt
```

and feeds every new row into *the same* rendering path a real FCM/APNs message takes — same
`data.kind` switch, same channel, same interruption level. It must not exist in a release build.
`firestore.indexes.json` ships the `toUid` + `sentAt` composite index; `firestore.rules` lets a
signed-in user read only rows where `toUid == request.auth.uid`, and nobody may write.

The document shape is frozen as `DebugPushDoc` in `src/io/push.ts` — **eleven keys, exactly**:

```jsonc
{
  "toUid":  "emu-receiver",              // string  — the addressee
  "kind":   "leadTime",                  // string  — mirror of data.kind
  "title":  "Start walking now",         // string
  "body":   "Mostafi is 3 min away",     // string
  "urgent": true,                        // bool    — leadTime only (addendum C)
  "data":   { "kind": "leadTime", "tripId": "AbC123" },  // map<string,string>
  "androidChannelId":      "sync_urgent",      // "sync_urgent" | "sync_updates"
  "apnsInterruptionLevel": "time-sensitive",   // "time-sensitive" | "active"
  "tokens": ["emu-receiver-token-0000000001"], // string[] — what FCM would have been given
  "sentAt": 1755900000123,               // NUMBER, epoch milliseconds — NOT a Timestamp
  "delivered": false                     // always false; nothing is ever really delivered
}
```

`sentAt` being a plain number matters: the index and both clients' `orderBy` must treat it as a
number, and a strict Swift/Kotlin decoder that expects a `Timestamp` will fail.

`data.kind` is one of `started`, `tenMin`, `leadTime`, `slip`, `arrived`, `lost`, `timeout`,
`cancelled`, `didYouLeave`, `armed`, `noShow`, `runningLate`, `reply`. Every **trip-scoped** push also
carries `data.tripId` (addendum D); non-trip pushes omit it.

`leadTime` is the only urgent kind → `sync_urgent` / `time-sensitive`. Everything else, `arrived`
included, → `sync_updates` / `active`. The push layer derives both purely from the `urgent` flag, so
server and clients cannot drift.

Nothing writes `_debugPushes` in production (unless `PUSH_DEBUG_MIRROR=1`), and nothing can read or
write it except through the rules above.

---

## 4. `npm run drive` — the scenario driver

```
node scripts/emuDrive.js --scenario=<name> [--eta=client|server]
```

Run it inside a live suite: `npm run emu:exec -- "node scripts/emuDrive.js --scenario=slip"`.
It prints the emulator URLs it uses, a table of every `_debugPushes` row in send order, and a
`PASS`/`FAIL` line per assertion. **Exit code 1 on any failed assertion.**

| scenario | proves |
|---|---|
| `happy` (default) | `started → tenMin → leadTime → arrived`, all to the receiver, `leadTime` the only urgent one, `trip.state == 'arrived'` |
| `happyServer` | the same ladder on the **server** routing path (`--eta=server` forced) |
| `slip` | ETA jumps +240 s, is held by `smoothEta`, is confirmed by a second identical fix → `slip`, `slipCount ≥ 1` |
| `noMove` | `startedAt` back-dated 4 min, driver still within 150 m → `didYouLeave` **to the driver** |
| `lost` | positions 6 min stale → `state 'lost'` + one push per member; then a fresh fix resumes it |
| `timeout` | `startedAt` back-dated 4 h → `state 'timeout'` + one push per member |
| `arm` | `armTrip` → `armed` to the driver; `createdAt` back-dated 16 min → `noShow` to the receiver |
| `cancel` | receiver cancels → `cancelled` **to the driver**, never the caller (addendum G) |
| `reply` | `sendReply` → `reply` to the driver; `setRunningLate` → `runningLate` to the receiver; receiver calling it fails `driver-only`; empty custom text fails `bad-reply` |
| `all` | every scenario above, sequentially, with a wipe between each |

### `--eta=client` vs `--eta=server`

| | positions carry `etaSec` | routing calls | `routePolyline` | who does this |
|---|---|---|---|---|
| `client` (default) | yes | **0** | never written | iOS (MapKit `calculateETA`) |
| `server` | no | one per poll | rewritten each poll | Android |

Both are proven in `npm run drive`. The server path only works locally because
`functions/.env.local` sets `ETA_POLL_SCALE=0.02`, compressing the real 60/30/15-second routing
throttles to 1.2/0.6/0.3 s — a 30-second scripted drive would otherwise fetch one ETA and fire
nothing.

### Three traps the script is shaped around (read before writing your own)

1. **`smoothEta` will silently swallow your first interesting ETA.** `startTrip` stamps
   `eta.updatedAt = now`; a fix landing within 15 s whose ETA differs by more than
   `max(120 s, 25 %)` is **held** as `pendingEtaSec` and fires nothing — the trip just looks stuck.
   Walk the ETA down gradually (the drive moves ~34 s of ETA per fix), or back-date `eta.updatedAt`,
   or wait > 15 s.
2. **`onPositionWrite` drops any fix whose `ts <= trip.lastPos.ts`, equal timestamps included.**
   Emit strictly increasing `ts`; a burst sharing one millisecond loses all but the first.
3. **Arrival and no-movement are wall-clock.** Arrival needs `speedMps < 2` inside `spot.radiusM`
   for 20 s, so the script's two arrival fixes are 21 s apart — the only real wait in the run.
   Everything else (3-minute movement check, 5-minute lost, 15-minute no-show, 3-hour timeout) is
   crossed by back-dating a field with the admin SDK and POSTing `debugRunHousekeeping`.

`scripts/lib/emuClient.js` is plain CommonJS with zero extra dependencies and is reusable:
`init`, `wipe`, `signIn`, `call`, `runHousekeeping`, `writePosition`, `writeAndAwait`,
`waitForPushes`, `pushes`, `getTrip`, `tripRef`, `lerpRoute`, `haversineMeters`, `stubEtaSec`,
`sleep`, plus `URLS` / `HOSTS`.

---

## 5. Scheduled functions are **not** emulated

firebase-tools maps `onSchedule` onto the Pub/Sub topic `firebase-schedule-<name>` and, with no
Pub/Sub emulator running, logs

```
functions[us-central1-housekeeping]: function ignored because the pubsub emulator does not exist or is not running.
```

That line is **expected** locally. The lost / timeout / no-show ladder is therefore driven through an
emulator-only HTTP endpoint wrapping the same pure `runHousekeeping(nowMs)`:

```
POST http://127.0.0.1:5001/fin-e8358/us-central1/debugRunHousekeeping?now=<epochMs>
  -> {"ok":true,"nowMs":…,"timeout":0,"lost":1,"resumed":0,"noShow":0}

GET  http://127.0.0.1:5001/fin-e8358/us-central1/debugPing
  -> {"ok":true,"sink":"firestore","etaPollScale":"0.02","stubSpeed":"12"}
```

`now` may also be a JSON body `{"now": <epochMs>}`; GET and POST both work; a missing or non-numeric
value falls back to the real clock (never `NaN`, which would silently make the whole sweep a no-op).
The counts are how many trips each rule touched — assert on them. Both endpoints return **404**
unless `FUNCTIONS_EMULATOR === 'true'` or `ENABLE_DEBUG_ENDPOINTS === '1'`, so they are inert even if
deployed.

Note the resume rule: a `lost` trip is flipped back to `driving` as soon as its newest
`positions` document is younger than five minutes. Back-dating only `trip.lastPos.ts` marks a trip
lost and then un-marks it **inside the same sweep** — back-date the position documents too.

---

## 6. Runtime and dependencies

| | |
|---|---|
| Cloud Functions runtime | `nodejs22` (nodejs20 is past its 2026-04-30 deprecation; firebase-admin 14 requires node ≥ 22) |
| firebase-functions | ^7.3.2 |
| firebase-admin | ^14.3.0 — **modular entry points only** (`firebase-admin/app`, `/firestore`, `/messaging`, `/auth`). v14 removed `admin.firestore()`; copying 2024-era script code crashes at require time. |
| typescript | ^5.9.3 (not 7.x: ts-jest 29 declares peer `typescript >=4.3 <7`) |
| jest / ts-jest | ^30.4.2 / ^29.4.12 |

Environment files:

* **`.env.local`** — committed on purpose (`functions/.gitignore` negates the root `.env.*` rule) so
  the emulator's stub configuration is reproducible from a fresh clone:
  `ROUTING_STUB_SPEED_MPS=12`, `ETA_POLL_SCALE=0.02`, `PUSH_SINK=firestore`,
  `ENABLE_DEBUG_ENDPOINTS=1`, `ROUTING_PROVIDER=google`.
* **`.secret.local`** — generated idempotently by `scripts/bootstrapEmulatorEnv.js` (run by every
  `emu:*` script) so `defineSecret('GOOGLE_ROUTES_KEY')` resolves without a real key. **Gitignored**;
  never commit a real key.

---

## 7. Behaviour the contract does not fully spell out

### `bad-reply`

`sendReply` throws **`bad-reply`** when `kind === 'custom'` and the trimmed text is empty (addendum
O). It was originally missing from `CLIENT_CONTRACT.md`'s error list; the contract now lists it on
line 26. Reusing `bad-name` would be semantically wrong and would produce misleading client copy.
**Both clients must map it**, and should treat any unlisted code as a generic failure rather than
crashing. The full set as of today:

```
not-paired  trip-active  spot-not-found  bad-code  own-code  driver-only
trip-not-found  bad-coords  bad-name  bad-token  bad-reply
```

### `data.tripId` on every trip-scoped push (addendum D)

The contract's push section specifies only `data.kind`. With nothing else in the payload a client
receiving a push while several trips exist in history cannot route it. The push layer injects
`data.tripId` from its `ctx` argument — `sendPush(m, { tripId })` / `sendAll(pushes, { tripId })`.
Additive and backward compatible. **Omitting `ctx` still sends the push but the clients cannot route
it**, so every trip-scoped call site must pass it.

### Pair discovery (addendum M)

```
pairs where members array-contains <uid> and status == 'active'
```

is the canonical way a client finds its own `pairId` after a reinstall or on the second device.
`firestore.rules` permits it (`allow read: if signedIn() && uid() in resource.data.members` covers
`list`, and the query provably returns only documents the caller is in) and `firestore.indexes.json`
ships the composite index (`members ARRAY_CONTAINS` + `status ASC`). An **unfiltered** read of
`pairs` fails. Both facts are asserted in `test/rules/firestore.rules.emulator.test.ts`.

`pairs/{pairId}.memberNames` (`uid -> displayName`) exists from the first write — `createPair` seeds
the creator, `acceptPair` completes both members, `registerPushToken` calls `syncDisplayNameToPairs`
so later renames propagate. Neither client ever reads the other user's document (rules forbid it).

### `startTrip` and routing calls (addendum F)

`CLIENT_CONTRACT.md` line 17: "`etaSec` = on-device ETA (iOS MapKit); when sent the server makes no
routing call." Enforced structurally:

| caller sends | routing calls | `distanceM` | `routePolyline` | `eta.approximate` |
|---|---|---|---|---|
| a finite `etaSec > 0` | **0** — `provider()` is never touched | `haversine(from, spot) * 1.3` | absent | `false` |
| no `etaSec`, routing succeeds | 1 | from the route | the encoded route | `false` |
| no `etaSec`, routing throws | 0 | `haversine(from, spot) * 1.3` | absent | `true` |

`bands` come from `bandsFor(distanceM, etaSec, spot.leadTimeMin)` in all three cases.
`lastRoutingCallAt` is set only when a routing call was actually attempted, so an iOS trip does not
start life with a throttle it never earned.

### `endTrip` addressing (addendum G)

`arrived` and `cancelled` both push `uid === trip.driverUid ? receiverUid : driverUid`. Whoever ends
the trip never receives their own action as a notification.

---

## 8. Triggers and engine

`onPositionWrite` (`trips/{tripId}/positions/{posId}`, `onDocumentCreated`) is the only place the
pure engine meets Firestore, routing and push.

* The `Position` handed to `step()` is rebuilt field-by-field by `toPosition()` from exactly
  `{lat, lng, accuracyM, speedMps, ts, etaSec?}`. The incoming document also carries
  `expireAt: Timestamp` (the rules require it) and that must never reach `trips/{id}.lastPos` —
  a `Timestamp` there is a hard decode failure for the strict Swift/Kotlin decoders (addendum J).
* A client `etaSec` means **zero** routing calls; `lastRoutingCallAt` is still advanced so the
  throttle treats it as a poll. Trips started that way have no `routePolyline`, so the
  routing-failure fallback uses `haversine * 1.3` rather than the polyline.
* `ETA_POLL_SCALE` is read **here** (`Number(process.env.ETA_POLL_SCALE ?? '1') || 1`) and threaded
  into every `step()` call. `engine/eta.ts` and `engine/tripEngine.ts` stay env-free and pure.
* The write is a transaction that re-reads the trip and returns **without writing** when the trip is
  no longer `driving` **or** when `position.ts <= fresh.lastPos.ts`. That makes the trigger a
  monotonic last-writer-wins on position timestamp, so two fixes racing (5 s near-phase cadence,
  offline replay bursts) can no longer clobber each other's `alerts` object.

`housekeeping` is `onSchedule('every 1 minutes')` wrapping the exported pure
`runHousekeeping(nowMs): Promise<{timeout, lost, resumed, noShow}>`. Deviation from the plan doc: an
armed trip that had already been no-show notified used to `continue` before the three-hour timeout
check and so stayed armed forever; the timeout check now always runs.

---

## 9. Tests

```
test/engine/*                                    pure unit — geo, eta, tripEngine
test/messages.test.ts                            copy + the "leadTime is the only urgent kind" rule
test/io/*                                        push doc builder + routing provider selection
test/triggers/debug.test.ts                      the 404 guard on the debug endpoints
test/callables/pairs.emulator.test.ts            memberNames denormalisation
test/callables/trips.emulator.test.ts            routing stub selection; zero routing calls with a
                                                 client etaSec; endTrip addressing; a REAL callable
                                                 round-trip over HTTP with a genuine ID token
test/rules/firestore.rules.emulator.test.ts      the security-rules suite
test/triggers/onPositionWrite.emulator.test.ts   expireAt projection, routing branches, ts guard,
                                                 alert ladder, real trigger fire
test/triggers/housekeeping.emulator.test.ts      lost / resume / timeout / no-show
```

`*.emulator.test.ts` run only under `npm run test:emu`.

**`jose` in jest** — every callable imports `firebase-functions/v2/https`, which transitively loads
`firebase-admin/auth → jwks-rsa → jose@6`. jose 6 is pure ESM; Node 22 can `require()` it but jest's
CommonJS runtime cannot. Both jest configs map `^jose$` to `test/support/joseStub.js`, whose shimmed
functions throw if anything ever really reaches JWKS verification. Never
`import { logger } from 'firebase-functions'` (the package root) in any file a unit test can reach —
use `firebase-functions/logger`.

---

## 10. Production path (blocked)

Everything in this section is **written down but untested**. Nothing here has ever been executed.

1. **Blaze billing** — required for firebase-functions v2 deploys and for any outbound HTTP call
   (the Google Routes API). Currently unconfirmed, so `firebase deploy --only functions` fails before
   any code runs.
2. **`GOOGLE_ROUTES_KEY`** — enable the **Routes API** in the Google Cloud console for `fin-e8358`,
   create an API key restricted to Routes API only, then
   `firebase functions:secrets:set GOOGLE_ROUTES_KEY --project fin-e8358`. Free tier is 10 000
   Compute Routes calls/month. Remove `ROUTING_STUB_SPEED_MPS` from the deployed environment or the
   stub will be selected instead of the real provider.
3. **APNs** — upload an APNs auth key (`.p8`) under Firebase console → Cloud Messaging → Apple app
   configuration. Requires a paid Apple Developer team. Without it `FcmPushSender` cannot deliver to
   iOS at all.
4. **`npm run deploy`** = `firebase deploy --only functions,firestore --project fin-e8358`.

`FcmPushSender` and `GoogleRoutesProvider` are consequently **entirely unexercised** — no FCM, no
Routes key, no mock. So is the `onSchedule` wrapper itself (only its extracted `runHousekeeping` body
is tested), and so is the routing-failure `catch` branch in `onPositionWrite` / `startTrip` (under
`FUNCTIONS_EMULATOR` the distance-aware stub is always selected and it never throws).

---

## 11. What emulator validation does NOT prove

Background location with the screen locked, the iOS blue location indicator, real APNs/FCM delivery,
Live Activities on a real Lock Screen or Dynamic Island, real battery drain, real SMS OTP, real
Google Routes calls, and `firebase deploy`. Those stay on `docs/testing/real-drive-checklist.md` for
a human with two phones. **No agent may report "M1 verified" without repeating this caveat.**
