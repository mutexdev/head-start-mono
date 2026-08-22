# Headstart — client contract (M1)

Both apps implement this identically. The server owns every alert decision; clients only
sign in, pair, manage spots, start/stop trips, stream positions, and render.

Firebase project: `fin-e8358`.

## Callables (Cloud Functions, region default)
| Name | Request | Response | Notes |
|---|---|---|---|
| `registerPushToken` | `{token, platform:"ios"\|"android", displayName?}` | `{ok:true}` | after sign-in and on every token refresh |
| `createPair` | `{}` | `{pairId, inviteCode}` | 6 chars, alphabet `ABCDEFGHJKLMNPQRSTUVWXYZ23456789` |
| `acceptPair` | `{code}` | `{pairId}` | errors: `bad-code`, `own-code` |
| `revokePair` | `{pairId}` | `{ok:true}` | |
| `upsertSpot` | `{pairId, name, lat, lng, leadTimeMin, radiusM, spotId?}` | `{spotId}` | leadTimeMin clamped 1–30, radiusM 50–500 |
| `deleteSpot` | `{spotId}` | `{ok:true}` | |
| `startTrip` | `{spotId, lat, lng, fuzzy?, etaSec?}` | `{tripId, bands:{far,near,lead}, etaSeconds, existing:boolean}` | `etaSec` = on-device ETA (iOS MapKit); when sent the server makes no routing call |
| `armTrip` | `{spotId, neededBy?}` | `{tripId}` | receiver-initiated "ping me when they leave" |
| `endTrip` | `{tripId, reason:"arrived"\|"cancelled"}` | `{ok:true}` | |
| `sendReply` | `{tripId, kind:"fiveMore"\|"takeYourTime"\|"atSpot"\|"custom", text?}` | `{ok:true}` | |
| `setRunningLate` | `{tripId, extraMin}` | `{ok:true}` | driver only, 1–60 |
| `setLowBattery` | `{lowBattery:boolean}` | `{ok:true}` | |

Error codes returned as the callable's message: `not-paired`, `trip-active`, `spot-not-found`,
`bad-code`, `own-code`, `driver-only`, `trip-not-found`, `bad-coords`, `bad-name`, `bad-token`.

## Firestore reads (clients never write these)
- `spots` where `pairId == <pairId>` — live list.
- `trips` where `pairId == <pairId>` and `state in ["armed","driving"]` — the active trip, live.
- `trips/{tripId}/replies` ordered by `ts` — quick replies both ways.
- `pairs/{pairId}` — includes `memberNames` (`uid -> displayName`) so each side can render the other's name without reading their user document.

Trip fields the clients read:
`state`, `spot{lat,lng,radiusM,name}`, `leadTimeMin`, `driverUid`, `receiverUid`,
`eta{seconds,updatedAt,approximate}`, `bands{far,near,lead}`, `phaseHint:"far"|"near"`,
`receiverView{etaSeconds,progressPct,lastPos?}`, `routePolyline`, `startedAt`,
`alerts{started,tenMin,leadTime,arrived,didYouLeave,slipCount}`.

**Receivers render `receiverView` only** — never `lastPos` — so fuzzy mode is enforced server-side.

## The one thing clients write
`trips/{tripId}/positions/{autoId}`:
```
{ lat: Double, lng: Double, accuracyM: Double, speedMps: Double,
  ts: Long (epoch ms), expireAt: Timestamp (now + 30 days), etaSec: Int? }
```
Security rules reject anything else, and only from `trip.driverUid`.

## Push payloads (FCM data + notification)
`data.kind` is one of:
`started`, `tenMin`, `leadTime`, `slip`, `arrived`, `lost`, `timeout`, `cancelled`,
`didYouLeave`, `armed`, `noShow`, `runningLate`, `reply`.

`leadTime` is the only urgent one: Android channel id **`sync_urgent`** (IMPORTANCE_HIGH, own
sound, bypass DND where permitted); iOS `interruption-level: time-sensitive`. Everything else
uses channel **`sync_updates`** (IMPORTANCE_DEFAULT) / `active`.

## Shared tracking algorithm (identical on both platforms)

State: `phase ∈ {far, near}`, starts `far`.

**Phase transition** — go to `near`, never back, when either is true:
1. `trip.phaseHint == "near"` (server said so), or
2. straight-line distance from the current fix to `trip.spot` ≤ `trip.bands.near` metres.

**Location request parameters**

| phase | accuracy | min interval | min displacement |
|---|---|---|---|
| `far` | balanced / hundred-metres | 30 s | 200 m |
| `near` | high / best-for-navigation | 5 s | 10 m |
| `far` + battery < 15 % | balanced | 60 s | 400 m |

**Upload filter** — upload a fix only when all hold:
1. `accuracyM <= 100`
2. `ts` is strictly greater than the last uploaded `ts`
3. it is the first fix, OR `ts - lastUploadedTs >= minIntervalMs` for the current phase,
   OR distance from the last uploaded point `>= minDisplacementM`

**Offline** — buffer unuploaded fixes in order, replay oldest-first when connectivity returns.
Cap the buffer at 500 fixes, dropping oldest.

**Stop tracking** immediately when the trip document's `state` leaves `"driving"`, when the
local user taps "I'm here"/"Cancel", or after a 3-hour local guard.

**Arrival is decided by the server.** Clients may register a geofence at
`spot.radiusM` as a backup wake-up, but must not send an `arrived` push themselves.

**Battery** — when the OS reports < 15 %, call `setLowBattery({lowBattery:true})` once per
trip and use the low-battery row above.

## Design tokens
Base `#15171B` · card `#1E2126` · raised `#262A30` · line `#31363D`
Text `#F2F4F7` / `#A8B0BA` / `#6D7681`
Go `#3AD693` (ink `#0C1C14`) · Headstart `#F0A13C` (ink `#241804`) · Delayed `#EF6F52`
Type: Archivo 400/500/600/700, tabular numerals for all times and countdowns.
Controls 56 dp/pt tall, nothing interactive under 44. Radii 12–14 controls, 16–22 cards, 26 sheets.
Screens are dark-only in M1. Artboards: `design/*.dc.html`.
