# head-start-mono

**Headstart** — the driver taps once; the person waiting is told exactly when to walk out.

A pickup app for iOS and Android. The driver taps "I'm coming"; the person waiting gets automatic push alerts driven by live driving ETA: *started driving* → *10 minutes away* → **"start walking now"** at a lead time they choose → *arrived*, plus a *delayed — stay inside* re-alert when traffic pushes the ETA back.

No consumer app does the receiver-configured "X minutes away" alert today. That's the product.

## Repo layout

```
docs/
  SETUP.md                             one-time Firebase + Google Routes setup
  research/2026-08-22-feasibility-and-market.md    feasibility, competitors, review mining
  superpowers/specs/                   approved design spec (architecture, data model, engine)
  superpowers/plans/                   task-by-task implementation plans
  testing/                             real-drive checklist (added by the M1 plan)
design/
  *.dc.html, canvas.json               19 UI artboards + layout
  README.md                            design tokens and rules
functions/                             (to build) Firebase Cloud Functions — the brain
android/                               (to build) Kotlin / Jetpack Compose
ios/                                   (to build) Swift / SwiftUI + Live Activity extension
```

## Stack

| Piece | Choice |
|---|---|
| Backend | Firebase — Auth (phone OTP), Firestore, Cloud Functions (TypeScript), FCM |
| Routing / ETA | Google Routes API behind a swappable `RoutingProvider`; iOS drivers compute ETA on-device with MapKit so the server makes zero routing calls |
| iOS | Swift / SwiftUI, WidgetKit Live Activity |
| Android | Kotlin / Jetpack Compose, location foreground service |
| Firebase project | `fin-e8358` |

All alert decisions live in one pure, unit-tested `TripEngine` on the server, so both platforms behave identically and alerts fire even when the receiver's app is closed.

## Getting started

1. Read [docs/SETUP.md](docs/SETUP.md) — enable Phone auth, Firestore, Blaze, and the Routes API key.
2. Read the spec: [docs/superpowers/specs/2026-08-22-the-sync-design.md](docs/superpowers/specs/2026-08-22-the-sync-design.md)
3. Execute [docs/superpowers/plans/2026-08-22-m1-backend-functions.md](docs/superpowers/plans/2026-08-22-m1-backend-functions.md) task by task.

## Milestones

- **M1** Core loop — pairing, spots, trip engine, hybrid tracking, the five alerts. Real-drive testable.
- **M2** Surfaces — Live Activity, Android ongoing notification, live map, quick replies, Siri/Assistant intents.
- **M3** Automation — recurring schedules, "ping me when they leave", no-show, leave-by.
- **M4** Polish — fuzzy location, QR/NFC pairing, low-battery mode, account deletion, store listings.

## Platform note

Android and the backend build and test fully on Linux. iOS needs macOS + Xcode — the iOS plan is written to be executed there.
