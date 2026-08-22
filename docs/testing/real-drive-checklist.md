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
