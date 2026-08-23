# `ios/fixtures/push/` — the thirteen contract push payloads

One `.apns` file per `data.kind` in CLIENT_CONTRACT.md lines 50-52. Copy is lifted
verbatim from `functions/src/messages.ts`, so a fixture cannot drift from what the
server actually sends.

## Why these exist

The Simulator cannot receive FCM, and this machine has no APNs `.p8` key, no paid
Apple team and no phone. `xcrun simctl push` can still deliver a real APNs-shaped
payload, which is the only way push routing is provable here.

```bash
UDID=F656C6C9-4797-40DF-B185-4B9C9F407420
xcrun simctl push "$UDID" com.mutexdev.headstart ios/fixtures/push/leadTime.apns
```

Then assert on the log stream — every delivery path funnels through the one entry
point `PushRouter.handle(userInfo:)`, which logs:

```
[HS][push] kind=leadTime tripId=fixtureTrip1
```

```bash
xcrun simctl spawn "$UDID" log stream --predicate 'eventMessage CONTAINS "[HS][push]"'
```

## Shape

* `Simulator Target Bundle` is set, so the bundle id argument may be omitted.
* `data` is **nested**, matching the contract and the server's `_debugPushes` rows.
  Real FCM flattens those keys onto the APNs root instead; `PushPayload` parses
  both shapes and `PushPayloadTests` table-tests both.
* `aps.content-available: 1` alongside the alert, so one push exercises **both**
  `application(_:didReceiveRemoteNotification:fetchCompletionHandler:)` and the
  `UNUserNotificationCenter` delegate.
* `leadTime` is the only fixture with `interruption-level: time-sensitive`
  (CLIENT_CONTRACT_ADDENDUM.md §C — `arrived` is **not** urgent).

## Validating them

`plutil -lint` cannot lint these: it accepts only plist syntaxes and rejects valid
JSON with `(Unexpected character { at line 1)`, while `simctl push` requires JSON.
Use the script instead, which parses with `plutil -convert` and then asserts the
contract:

```bash
ios/scripts/check-push-fixtures.sh
```

## What these do NOT prove

FCM token registration, real APNs delivery, Focus/DND breakthrough, or the server's
decision to send any of them. The first three are real-device-only. The last is
proven by the `_debugPushes` bridge (`ios/Headstart/Push/DebugPushBridge.swift`).
