# Headstart M1 — build and validation status

Built and validated by an agent fleet on 2026-08-22. Three independent planners (Opus 5),
21 implementers (Opus 5) across three parallel pipelines, four reviewers (Sonnet 5).

## Verdict

**M1 works on emulators.** The product's central promise — the receiver is told to start walking
at the right moment — was proven end to end with an Android driver and an iOS receiver paired
live against one Firebase emulator suite.

```
kind      urgent  androidChannelId  apnsInterruptionLevel  body
started   false   sync_updates      active                 ETA 6 min to Office
tenMin    false   sync_updates      active                 AndroidDriver is 6 min away
leadTime  TRUE    sync_urgent       time-sensitive         AndroidDriver is 3 min away
arrived   false   sync_updates      active                 Waiting at Office
```

Each kind exactly once, in order, `leadTime` the only urgent one. The iOS receiver rendered all
four through its real push path, its Live Activity started and ended on the same trip, and the
30 position documents carried exactly the contract's field set and stopped on arrival.

## Test counts

| Area | Proven by |
|---|---|
| Backend | 89 unit + 53 emulator tests; 9 emuDrive scenarios |
| iOS | Full XCTest suite green; headless simulator drive end to end |
| Android | 110 unit tests; APK installs and runs on two AVDs; 42-fix route replay |

## Defects found and fixed

Five real defects. **None were caught by unit tests** — every one surfaced only when an agent ran
the thing.

1. **The active-trip query could never succeed.** For a `list`, Firestore synthesises `resource`
   from the query's own constraints, so the rule's `resource.data.driverUid` was undefined and
   the whole query failed. Neither app could read its own active trip. `get` passed, which is why
   the rules tests were green. *(Found by the Android e2e drive.)*
2. **`isMember()` dereferenced a null `get()`.** A stale `pairId` produced a rule evaluation error
   instead of a clean denial. *(Found by the iOS e2e drive.)*
3. **Fallback ETA collapsed to zero past the halfway point.** `polylineRemainingMeters` snapped to
   the nearest vertex rather than the nearest point on the route — a step function on sparse
   routes. A driver 60 % of the way there would have produced a fallback ETA of ~0 s, telling the
   receiver to walk out immediately. *(Found by the backend reviewer.)*
4. **Arrival push worded from the wrong person.** When the receiver tapped "I'm here", the driver
   was told "‹receiver› has arrived". *(Found by the backend reviewer.)*
5. **Re-inviting after an unpair handed out a dead code.** `pendingInvite()` matched `!isActive`,
   which also matches `revoked`; `acceptPair` only accepts `pending`, so the code could never
   work. Android only — iOS had it right. *(Found by the two-device integration drive.)*

## How M1 was validated without billing, APNs, SMS or phones

None of Blaze billing, a Google Routes key, an APNs `.p8`, a paid Apple team or physical phones
were available. Rather than stopping, the constraints were engineered around:

| Blocker | How it was unblocked |
|---|---|
| Xcode project creation is a GUI walkthrough | XcodeGen from a checked-in `project.yml` |
| Firebase console app registration | `firebase apps:create` + `apps:sdkconfig` over the CLI |
| No Blaze plan, so no deploy | Firebase Local Emulator Suite as the verification path |
| FCM cannot deliver from the emulator | Server writes every would-be push to `_debugPushes`; both clients ship a debug-only listener that feeds the real render path |
| `onSchedule` is not emulated at all | `runHousekeeping(nowMs)` extracted pure, driven over HTTP |
| Phone OTP needs real SMS | Auth emulator's `verificationCodes` endpoint |
| Simulator/AVD cannot receive real pushes | 13 `.apns` fixtures via `simctl push`; a debug broadcast receiver on Android |

## What emulator validation does NOT prove

Not opinions — these are structurally unprovable here, and M1 is **not** shippable until a human
runs `docs/testing/real-drive-checklist.md` on two real phones.

- Background location with the screen locked, and the iOS blue location indicator
- Real APNs/FCM delivery, and real SMS OTP
- A Live Activity on a real Lock Screen or Dynamic Island
- Real battery drain over a drive
- Real Google Routes API calls — `GoogleRoutesProvider` has never executed
- `firebase deploy`, and therefore whether the composite indexes are correct in production
- **Decision D7** (iOS attaches `etaSec` so the server makes zero routing calls). `MKDirections`
  returns "Directions Not Available" on this simulator, so D7 is proven only against a fake ETA
  provider. On a real device it may hold; here it is unverified.
- OEM background-kill behaviour on Xiaomi/OnePlus/Oppo/vivo

## Known, unfixed

- `functions/tsconfig.json` has `include: ["src"]`, so `tsc` never typechecks the test tree.
- iOS preview fixtures (`TripPreviewData`, `PartnerCopy`) are ungated and ship in Release.
- The far phase delivers no fix on these AVD images — they have no network location provider, so
  `PRIORITY_BALANCED_POWER_ACCURACY` starts no provider. Judged an emulator artifact, not a
  product bug, but it means the far-phase cadence is unproven anywhere.
