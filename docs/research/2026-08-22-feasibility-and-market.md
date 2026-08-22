# The Sync — Feasibility & Market Research (2026-08-22)

Problem: Driver (Mostafi) picks up partner from office. Partner needs 3–4 min to walk to the pickup spot.
Goal: driver taps "I'm coming" → partner gets "started driving", "10 min away", and a self-configured "N min away — start walking" alert, from live route-based ETA.

## 1. Verdict
**Fully feasible for a solo dev. Year-one fixed cost ≈ $124 (Apple $99/yr + Play $25). Running cost at 2 users: $0/mo.**
Every hard piece (background GPS, route ETA, push, Live Activities) is commodity. The design risks are OS background limits and routing-API cost at scale.

## 2. Technical findings

### Background location
- **iOS**: `UIBackgroundModes: location` + "While Using" permission is enough because the driver starts the trip in the foreground (`allowsBackgroundLocationUpdates = true`). Blue status pill is expected. "Always" only needed to relaunch after force-quit — skip it for v1. App Review (5.1.1) requires a clear purpose string + graceful degradation.
- **Android**: foreground service with `foregroundServiceType="location"` + `FOREGROUND_SERVICE_LOCATION` (Android 14+). **Avoid `ACCESS_BACKGROUND_LOCATION`** — it triggers Play's permission-declaration review.
- Track only between "I'm coming" and arrival/timeout (hard cap ~3 h). 20-min trip ≈ 1–2% battery.
- OEM killers (Xiaomi/Huawei/OnePlus) still kill FGS; link dontkillmyapp.com in-app.
- Geofences alone will NOT work for a 3-min alert: iOS needs ~20 s dwell, Android Doze delays 2–6 min. Use hybrid (below).

### Framework
| Option | Verdict |
|---|---|
| **Expo (React Native) + expo-location/expo-task-manager** | Free, adequate for foreground-initiated short sessions. Needs dev build. **Recommended start.** |
| Transistor `react-native-background-geolocation` / `flutter_background_geolocation` | $399 one-time, best-in-class, OEM workarounds built in. Upgrade path if field failures. |
| Native Swift + Kotlin | Max control, 2 codebases. Live Activity needs a Swift WidgetKit extension anyway. |

### Push
- FCM free, unlimited, delivers to APNs.
- iOS Live Activity (Dynamic Island) countdown via `Text(timerInterval:)` ticks locally; push only when ETA shifts >1 min. Android: ongoing notification; Android 16 `ProgressStyle` Live Updates.

### ETA / routing cost
| Provider | Free tier | Paid |
|---|---|---|
| Mapbox Directions | **100k/mo** | $2/1k |
| Google Routes (Essentials) | 10k/mo | $5/1k ($10/1k traffic-aware Pro) |
| Apple MapKit `calculateETA` | free on-device (iOS only) | — |
| Self-hosted Valhalla/OSRM | VPS $10–40/mo | no live traffic |

Polling schedule: 60 s while ETA>10 min, 30 s 10→5, 15 s <5 → ~45 calls/trip. 2 users ≈ 2.7k/mo (free). 1,000 users/day ≈ 1.35M/mo → Mapbox ~$2.5k, so at scale use hybrid geofence (~10–15 calls/trip) or Valhalla.

### Hybrid tracking design (recommended)
1. "I'm coming" → 1 routing call → ETA + polyline. Push "started".
2. Place geofences on the polyline at ETA−12, ETA−7, threshold+2 min; run low-accuracy location (200 m filter) meanwhile.
3. Entering ETA−12 band → high-accuracy GPS + routing poll every 30 s, 15 s under 5 min. Fire "10 min" and final alert from server-side ETA with hysteresis.
4. 100 m destination geofence ends trip, stops tracking.
Final alert accuracy ≈ 15–30 s.

### Backend
| | 2 users | 1,000 users |
|---|---|---|
| Firebase (Firestore + Functions + FCM) | $0 | ~$5–25/mo |
| Supabase | $0 (pauses when idle) | $25/mo |
| Go/Node on VPS | $5 | $10–20 + Valhalla |

Data model: `trips {driverId, riderId, destination, state, lastPos, eta, alertsSent[], thresholds}`.

## 3. Competitive landscape
| Product | Receiver-defined "N min away" alert? | Gap |
|---|---|---|
| Apple Maps Share ETA | No (start / significant delay / arrival) | iOS-only, must use Apple Maps nav |
| Google Maps trip progress | No (geofence arrive/leave only) | no lead-time |
| Waze Share drive | No | must use Waze; too many taps while driving |
| Find My | Radius only, not minutes | distance ≠ traffic time; always-on |
| Life360 (96M MAU, $487M rev) | No; place geofences, No-Show alerts | always-on, "stalkerware" reputation, subscription |
| Glympse | Consumer no; enterprise PRO yes (B2B) | battery, ads, 4-h cap |
| OMW – On My Way (iOS indie) | not advertised | no Android, own nav |
| eta app (iOS indie) | "smart notifications", unclear | few ratings |
| PikMyKid/FetchKids | alerts to school staff only | B2B school-licensed |

**Key insight: no consumer app offers a receiver-configured, route-ETA-based "X minutes away" alert.** It exists only in B2B (Glympse PRO "tech is 10 min away") and Uber's fixed "1 min away". Nobody in the indie niche is visibly monetizing.

## 4. What users complain about / praise (review mining)
Complaints: battery drain from always-on; notifications silently not firing (Apple Share ETA, Find My, Google link-sharing); jumpy ETA; creepy surveillance; too many taps while driving (Waze); ecosystem lock-in; ads in a utility; hard-to-cancel subs; arbitrary caps; login friction; "location active" nags.
Praise: no account for recipient; trip-scoped auto-expiring sharing; automatic milestones with zero mid-trip taps; lock-screen Live Activity ETAs; fuzzy location; curbside "on my way" → prep (Target Drive Up).
Lesson from Target: verify "I'm coming" with real movement, show a trustworthy ETA, not a self-reported one.

## 5. Prioritized feature list
**Must-have (v1)**
1. One-tap "I'm coming" with preset recipient per destination; Siri/Assistant intent; CarPlay/Auto-safe big button.
2. Recipient push, or SMS link fallback; phone-number onboarding, no account required for recipient.
3. Reliable milestones: started → 10 min → receiver-set N min ("start walking") → arrived; re-alert if ETA slips >2 min ("stay inside, +6 min").
4. Trip-scoped sharing only; auto-stop on arrival/timeout; both see "sharing on".
5. Route-based, smoothed ETA; battery-aware hybrid tracking; low-battery fallback to last-known ETA.

**Nice-to-have (v2)**
6. Recurring schedules (daily 5:30 pm auto-arm) + "ping me when they leave work" reverse trigger / no-show alert.
7. Two-way quick replies ("5 more min", "take your time", "I'm at gate B").
8. Live Activity / Android ongoing notification / Watch.
9. Saved pickup spots with walk-time → lead time auto-derived.
10. Multiple receivers each with own lead time (carpool, kids).

**Delight (v3)**
11. "Running late" auto-message; calendar "leave now"; QR/NFC pairing at spot; fuzzy location before final leg; 30-day auto-delete history.

## 6. Privacy principles
Driver initiates; window closes on arrival; nothing persists by default; symmetric visibility; no "location active" nags; revocable any time.

## 7. Monetization
Free core 1:1 forever, no ads. Optional one-time/low annual unlock for recurring routes, multi-receiver, household. Possible B2B tier for tradespeople ("tech is 10 min out") where Glympse PRO is enterprise-priced.

## 8. Recommended stack
Expo (RN, TypeScript) + expo-location FGS/background mode → Firebase (Firestore + Cloud Functions + FCM) → Mapbox Directions (100k free) → Swift WidgetKit Live Activity, Android ongoing notification.

## Sources
See agent reports; main: transistorsoft pricing, firebase.google.com/pricing, docs.mapbox.com/accounts/guides/pricing, radar.com/blog/limitations-of-ios-geofencing, support.google.com/googleplay/android-developer/answer/9799150, support.apple.com Share ETA guide, techcrunch.com Life360 No-Show (2025-08-20), apps.apple.com OMW id6768796616, waze.uservoice.com 38926804, discussions.apple.com/thread/254023892, vice.com partner location-sharing roundup.
