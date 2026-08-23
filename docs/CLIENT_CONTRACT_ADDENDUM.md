# Headstart — M1 contract addendum (binding)

Resolutions arbitrated by the orchestrator after three independent planners (backend, iOS, Android)
reviewed `CLIENT_CONTRACT.md`, the spec, and their own plan docs and reported conflicts.

**`CLIENT_CONTRACT.md` remains the law. This file resolves everything it left ambiguous or wrong.
Where this file and a plan doc disagree, this file wins on all three platforms.**

## A. Callable surface — M1 is exactly these twelve
`registerPushToken`, `createPair`, `acceptPair`, `revokePair`, `upsertSpot`, `deleteSpot`,
`startTrip`, `armTrip`, `endTrip`, `sendReply`, `setRunningLate`, `setLowBattery`.

**Not in M1** — no client may call them, no server implements them:
`registerLiveActivityToken`, `setNeededBy`, `deleteAccount`. `neededBy` is passed to `armTrip`.

## B. Reply kinds
`sendReply.kind ∈ {fiveMore, takeYourTime, atSpot, custom}` — exactly four. The spec's fifth kind
`runningLate` is **not** a reply kind; it is the `setRunningLate(tripId, extraMin 1–60, driver only)`
callable, and the receiver learns of it through the server's `runningLate` push.

## C. Urgency mapping — `leadTime` is the only urgent push
`leadTime` → Android `sync_urgent`, iOS `time-sensitive`. **All twelve other kinds**, `arrived`
included, → `sync_updates` / `active`. The backend plan doc marked `arrived` urgent; that is wrong.
A unit test on the server must assert `leadTime` is the only builder returning `urgent === true`.

## D. Push payload gains `data.tripId`
Additive and backward compatible. Every trip-scoped push carries `data.tripId` alongside `data.kind`
so a client can route the alert to a trip document. Non-trip pushes omit it.

## E. `startTrip` response includes `existing: boolean`
Per `CLIENT_CONTRACT.md`. When `existing === true` the client attaches to the trip already running —
it must **not** restart tracking or replay first-start UI. Both clients decode this field.

## F. `startTrip` with a client `etaSec` makes **zero** routing calls
The contract wins over the backend plan doc: a valid client `etaSec` means the server skips routing
entirely, sets `distanceM = haversine(from, spot) * 1.3`, leaves `routePolyline` undefined, and
records `routingCalls: 0`. iOS always sends `etaSec` (MapKit); Android never does.

## G. `arrived` / `cancelled` pushes go to the *other* member
`endTrip` addresses the push to `uid === trip.driverUid ? receiverUid : driverUid`. Whoever ends the
trip does not get pushed their own action.

## H. `lastPos` must never reach a receiver surface
Enforced structurally, not by comment. Receivers render `receiverView` only. Both clients must pass:
`grep -rn 'lastPos' <receiver UI dir>` → empty.

## I. `trip.alerts` — model exactly six fields
`{started, tenMin, leadTime, arrived, didYouLeave, slipCount}`. `lastSlipEtaSec` is server-internal.
Mappers must tolerate any alert flag being absent (it is absent until it first fires) — never trap.

## J. `positions` documents carry exactly seven keys
`lat, lng, accuracyM, speedMps, ts, expireAt` + optional `etaSec`. Nothing else; rules reject extras.
`trips/{id}.lastPos` is projected field-by-field on the server — never spread from the incoming doc,
or a `Timestamp` leaks into it.

## K. Client-side clamping mirrors the server
`leadTimeMin` 1–30, `radiusM` 50–500, `extraMin` 1–60. Defaults `radiusM 100`, `leadTimeMin 3`.
Clamp before the call and constrain the UI controls, so users never see a raw callable error.

## L. `setLowBattery` latch — identical on both platforms
Per-trip, keyed by `tripId`, in the **trip repository**. Set once on the first OS report under 15 %,
never cleared for that trip. Never downgrades the `near` cadence (decision D2).

## M. Pair discovery
A client finds its own pair with `pairs where members array-contains uid and status == 'active'`.
The backend ships the required composite index. `pairs/{pairId}.memberNames` (`uid -> displayName`)
exists from the first line of code — not retrofitted — so neither side reads the other's user doc.

## N. Deep link scheme is `headstart` everywhere
`headstart://pair/{code}`. `thesync://` is a leftover from the pre-rename repo and must appear nowhere.
Share text must lead with the bare code so manual entry always works:
`Pair with me on Headstart. Code: K7M2QP — headstart://pair/K7M2QP`.

## O. `bad-reply` is a real error code
Returned by `sendReply` for empty custom text, in addition to the codes listed in `CLIENT_CONTRACT.md`.
Both clients must map it.

---

# Emulator contract (how M1 is validated without billing, APNs, SMS or hardware)

Blaze billing, the Routes API key, an APNs `.p8`, a paid Apple team and real phones are all
unavailable here. The Firebase Local Emulator Suite is the sanctioned and primary verification path.

## Fixed ports — binding on all three platforms
| Emulator | Port | From macOS host / iOS Simulator | From Android AVD |
|---|---|---|---|
| Auth | 9099 | `127.0.0.1` | `10.0.2.2` |
| Firestore | 8080 | `127.0.0.1` | `10.0.2.2` |
| Functions | 5001 | `127.0.0.1` | `10.0.2.2` |
| Emulator UI | 4000 | `127.0.0.1` | — |

Callable URLs are deterministic: `http://127.0.0.1:5001/fin-e8358/us-central1/<name>` (region pinned
to `us-central1`).

## `_debugPushes` — the emulator push sink
FCM cannot deliver from the emulator, so the server's `PushSender` writes every would-be push to
`_debugPushes/{autoId}` instead, with the exact payload FCM would have carried:

```
{ toUid, kind, title, body, urgent, data{kind, tripId?}, androidChannelId,
  apnsInterruptionLevel, tokens, sentAt, delivered:false }
```

Rules: a signed-in user may read rows where `toUid == request.auth.uid`; nobody may write. Inert in
production (only active when `FUNCTIONS_EMULATOR === 'true'` or `PUSH_SINK=firestore`).

**Both clients MUST ship a debug-only push bridge** (`#if DEBUG` / `debug` source set): a Firestore
listener on `_debugPushes where toUid == me orderBy sentAt`, feeding each new row into *the same*
rendering path a real FCM/APNs message takes — same `data.kind` switch, same channel, same
interruption level. This is what makes the server-decided alert ladder observable end-to-end on a
simulator and an AVD. It must not exist in a release build.

The clients' other injection paths (`xcrun simctl push` fixtures on iOS, the debug broadcast receiver
on Android) stay — they validate *rendering* of all thirteen kinds. The `_debugPushes` bridge
validates the *server's decisions*. Both are required.

## Phone sign-in without SMS
The Auth emulator issues codes retrievable from the host:
`curl -s http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes`
iOS additionally sets `setAppVerificationDisabledForTesting(true)`; Android does the same.

## Scheduled functions are not emulated
`firebase-tools` converts `onSchedule` to a Pub/Sub trigger and ignores it without the Pub/Sub
emulator. The lost/timeout/no-show ladder is therefore driven through an emulator-only
`debugRunHousekeeping` HTTP endpoint wrapping the pure `runHousekeeping(nowMs)`.

## What emulator validation does NOT prove
Background location with the screen locked, the iOS blue location indicator, real APNs/FCM delivery,
a Live Activity on a real Lock Screen or Dynamic Island, real battery drain, real SMS OTP, real
Google Routes calls, and `firebase deploy`. These stay on `docs/testing/real-drive-checklist.md` for
a human with two phones. **No agent may report "M1 verified" without repeating this caveat.**
