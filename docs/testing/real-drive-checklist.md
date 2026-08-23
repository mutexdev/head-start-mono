# Real-drive checklist

Run this on an actual pickup at the end of every milestone, on every platform you've built.
Two phones, paired, one spot, `leadTimeMin = 3`. Record the result — a milestone isn't done
until this passes on a real road.

Fill in: **Date** ____ · **Driver phone** ____ · **Receiver phone** ____ · **Milestone** ____

## Before you leave
- [ ] Both phones signed in and showing the same pair.
- [ ] The spot's pin is on the actual curb, not the building centroid.
- [ ] Receiver has notifications enabled; the `sync_urgent` channel / time-sensitive setting is on.
- [ ] Driver phone battery above 50 % and its level noted here: ____ %

## The trip
- [ ] Driver taps "I'm coming" with the app open → receiver gets **started** within 5 s, with a sane ETA.
- [ ] Driver locks the phone and switches to their usual nav app → positions keep arriving.
      Check Firestore console `trips/{id}/positions`: a new doc at least every 60 s in the far phase.
- [ ] `trips/{id}.phaseHint` flips to `near` roughly 7 min out; positions then arrive every ~5 s.
- [ ] **10 min away** lands between 9:30 and 10:30 of real remaining time.
- [ ] **Start walking now** lands at 3 min ± 30 s.
- [ ] The receiver actually reaches the curb *before* the car does. This is the whole product —
      if it fails, nothing else on this list matters. Note the gap: ____ seconds early/late.
- [ ] The countdown on the lock screen (Live Activity / ongoing notification) matches the in-app ETA.

## Deliberate disruptions
- [ ] Pull over for 3 min after the 10-min alert → **delayed** arrives; receiver told to stay inside.
- [ ] Resume → no duplicate walk-out alert unless the ETA had climbed back above lead + 2 min.
- [ ] Receiver sends "5 more min" → driver sees it without unlocking.
- [ ] Driver taps "Late +5" → receiver gets **runningLate**.
- [ ] Airplane mode on the driver for 6 min mid-trip → both get **connection lost**;
      turn it off → buffered positions replay in order and the trip resumes within 2 min.
- [ ] Tap "I'm coming" and don't move for 3 min → driver gets **did you leave?**;
      confirm the receiver was NOT told anything was wrong.

## Arrival and cleanup
- [ ] Arriving and stopping → **arrived** within 30 s.
- [ ] The OS location indicator disappears on the driver phone (blue pill / FGS notification gone).
- [ ] No further position docs are written after the trip ends.
- [ ] Live Activity / ongoing notification is dismissed.

## Numbers to record
- [ ] Driver battery used over the whole trip: ____ % (target ≤ 3 % for a 20-min drive)
- [ ] `trips/{id}.routingCalls`: ____ (target ≤ 20 on Android; 0–1 on iOS with on-device ETA)
- [ ] Position docs written: ____
- [ ] Any alert that fired more than once: ____

## Verdict
- [ ] Pass — the receiver walked out at the right moment and nothing fired twice.
- [ ] Fail — what went wrong: ______________________________________________

---

## Android emulator dry-run (M1, no hardware)

Everything a reviewer with no phones, no Blaze billing and no Routes key can still verify.
The step-by-step runbook is `android/tools/emulator_e2e.md`; this is its checklist form.
It is a **precondition** for the real drive below, not a substitute for it.

### Setup
- [ ] `Pixel_9a` (API 36) and `Pixel_10` (API 37) both booted. **Not** `Pixel_9_Pro` — its
      `config.ini` has no `image.sysdir.1` and the emulator aborts on "Broken AVD system path".
- [ ] Exactly one Firebase Local Emulator Suite running: `lsof -ti :8080` before starting one,
      then `cd functions && npm run emu:start`. Auth 9099 / Firestore 8080 / Functions 5001 / UI 4000.
- [ ] `./gradlew :app:assembleDebug` installs on both AVDs; `pm grant` ACCESS_FINE_LOCATION and
      POST_NOTIFICATIONS on each.
- [ ] `adb logcat -d -s Headstart:I | grep 'Firebase target'` prints
      `Firebase target = emulator 10.0.2.2` on both. (If it prints `cloud`, `Prefs.useCloud` is set.)

### Onboarding and pairing
- [ ] Both AVDs sign in by phone OTP with no SMS: code read from
      `curl http://127.0.0.1:9099/emulator/v1/projects/fin-e8358/verificationCodes`.
- [ ] On a device where the permissions were **not** pre-granted: location is requested first,
      notifications second, one OS dialog at a time — never both at once.
- [ ] `headstart://pair/{code}` opens the app on "Enter their code" with the code prefilled,
      both from cold start and while the app is already running (`onNewIntent`, singleTask).
- [ ] After pairing, `pairs/{id}.status == "active"` and `memberNames` holds **both** display
      names; each app shows the other person's real name, never "Your partner".
- [ ] A spot created on one device appears on the other within a second or two (live listener).

### The trip
- [ ] "I'm coming" → ongoing notification "Sharing with {name}" within 2 s, and the driver's
      screen becomes the trip screen.
- [ ] `tools/replay_route.sh <serial>` runs to completion; every `adb emu geo fix` returns OK.
- [ ] `trips/{id}/positions` grows while the route replays.
- [ ] Near-phase cadence is visible in the position timestamps: consecutive `ts` about 5 s apart.
- [ ] Writing `phaseHint: "near"` on the trip flips the app to
      `LocationParams(priority=HIGH, minIntervalMs=5000, minDisplacementM=10.0)` in `HsTracking`
      — contract transition rule 1. **Required on an AVD**: these images have no network
      location provider, so the far phase's BALANCED request starts no provider at all and no
      fix is ever delivered. Real phones are unaffected. See the runbook, §8.
- [ ] `_debugPushes` shows the ladder in order — `started`, `tenMin`, `leadTime`, `arrived` —
      and `leadTime` is the ONLY row with `urgent: true` / `androidChannelId: sync_urgent`.
- [ ] The receiver's `HsDebugPush` log shows each of those rows replayed into the real renderer.

### Notification rendering, all thirteen kinds
- [ ] Broadcasting each `data.kind` to `app.headstart.debug.PushInjectorReceiver` renders
      `leadTime` on `sync_urgent` (importance 4) and every other kind on `sync_updates`
      (importance 3), per `dumpsys notification`.
- [ ] `didYouLeave` raises the "Did you actually leave?" sheet over the trip screen.

### Ending
- [ ] "I'm here" → `state` becomes `arrived`, the ongoing notification disappears on its own
      (the service stops from its trip listener; no UI code calls `stop()`), and the driver
      returns to Home.
- [ ] `dumpsys activity services app.headstart` shows no ServiceRecord afterwards.

### Still unproven after all of the above
Background location with the screen locked · real FCM/APNs delivery · real SMS · real Google
Routes calls · real battery drain · OEM background-kill behaviour · `firebase deploy`.
**Nobody may report "M1 verified" on the strength of this section alone.**

---

## Android client (M1)

Driver on Android, receiver on either platform. Start with both phones above 60 % battery.

- [ ] Tap "I'm coming" → the ongoing notification appears within 2 s, titled "Sharing with {name}".
- [ ] Receiver gets the "started driving" push within 5 s with a plausible ETA.
- [ ] Lock the driver's phone and drive. Check Firestore `trips/{id}/positions`: fixes arrive
      roughly every 30 s or 200 m in the far phase.
- [ ] Around 7 minutes out, `trip.phaseHint` flips to `near` and positions switch to ~5 s.
      Check with `adb logcat -s HsTracking` — it logs each parameter change.
- [ ] "10 min away" arrives between 9:30 and 10:30 of real remaining time.
- [ ] **"Start walking now" arrives at 3 min ± 30 s, on the loud channel, with its own sound,
      and the receiver reaches the spot before the car does.** This is the product.
- [ ] Put the driver's phone in airplane mode for 5 minutes mid-drive; positions buffer
      (`HsTracking` logs no errors) and replay in timestamp order when it comes back.
- [ ] Arrive and stop → "arrived" push within 30 s, the ongoing notification disappears, and
      the driver's screen returns to Home.
- [ ] Repeat with the receiver's app force-stopped: the walk-out push still arrives (the
      server owns the decision, not the app).
- [ ] Tap "I'm coming" and do not move for 3 minutes → the "Did you actually leave?" sheet
      appears over the trip screen and the tray notification is quiet, not loud.
- [ ] Driver battery used over a 25-minute drive: ≤ 3 %.
- [ ] On a Xiaomi/OnePlus/Oppo/vivo device, the battery guidance dialog appeared once after
      the first trip started, and never again.
- [ ] Settings → "Send me a test alert" produces the same loud alert as the real walk-out one.
- [ ] Unpair from either phone → the other phone returns to the pairing screen.
