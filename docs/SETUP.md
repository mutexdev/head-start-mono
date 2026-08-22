# The Sync — one-time cloud setup (project `fin-e8358`)

Do these once, before deploying Cloud Functions. Steps marked **(you)** need your credentials/billing and cannot be automated.

## 1. CLI + login **(you)**
```bash
npm install -g firebase-tools
firebase login
firebase use fin-e8358
```
If `firebase use` errors, run `firebase projects:list` and confirm `fin-e8358` is listed for this account.

## 2. Enable Firebase services **(you)**
In https://console.firebase.google.com/project/fin-e8358 :
- **Build → Authentication → Get started → Sign-in method → Phone → Enable.**
  Add your two test phone numbers under *Phone numbers for testing* to avoid SMS costs while developing.
- **Build → Firestore Database → Create database → Production mode →** pick the region closest to you (e.g. `asia-south1`). Region is permanent.
- **Run → Messaging (Cloud Messaging)** — enabled by default; nothing to click yet. The APNs auth key gets uploaded here later, once the iOS app exists (Project settings → Cloud Messaging → Apple app configuration).

## 3. Upgrade to Blaze **(you)**
https://console.firebase.google.com/project/fin-e8358/usage/details → **Modify plan → Blaze**.
Required because Cloud Functions cannot make outbound HTTP calls (Google Routes API) on the free Spark plan. Free monthly quotas still apply — expected bill at 2 users: **$0**. Set a budget alert at $5 while you're at it.

## 4. Enable the Routes API and create a key **(you)**
This is a *Google Cloud* setting, not a Firebase one — same project id.

1. Open https://console.cloud.google.com/apis/library/routes.googleapis.com?project=fin-e8358
2. Click **Enable**.
3. Go to https://console.cloud.google.com/apis/credentials?project=fin-e8358
4. **+ Create credentials → API key**. Copy the key.
5. Click **Edit API key** on the new key:
   - Name it `the-sync-routes`.
   - **Application restrictions: None** (server-side calls from Cloud Functions have no referrer/IP you can pin reliably).
   - **API restrictions: Restrict key → select "Routes API" only.** ← important, this is what stops a leaked key from being usable elsewhere.
   - Save.

Free tier: 10,000 Compute Routes calls/month (Essentials SKU). Your usage at ~45 calls/trip, 2 trips/day ≈ 2,700/month → free. iOS drivers with on-device MapKit ETA use ~1 call/trip.

## 5. Store the key as a Functions secret **(you)**
Never commit it; never paste it into chat. From the repo root:
```bash
firebase functions:secrets:set GOOGLE_ROUTES_KEY --project fin-e8358
```
It prompts for the value, stores it in Google Secret Manager, and the functions read it via `defineSecret('GOOGLE_ROUTES_KEY')`.

Verify:
```bash
firebase functions:secrets:access GOOGLE_ROUTES_KEY --project fin-e8358
```

## 6. Local emulator prerequisites
- Java 11+ (`java -version`) — required by the Firestore emulator.
- No secret needed locally: tests set `ROUTING_STUB_ETA_SEC` and never call Google.

## 7. Quick sanity check of the key (optional)
```bash
curl -s -X POST 'https://routes.googleapis.com/directions/v2:computeRoutes' \
  -H 'Content-Type: application/json' \
  -H "X-Goog-Api-Key: $GOOGLE_ROUTES_KEY" \
  -H 'X-Goog-FieldMask: routes.duration,routes.distanceMeters' \
  -d '{"origin":{"location":{"latLng":{"latitude":23.8103,"longitude":90.4125}}},"destination":{"location":{"latLng":{"latitude":23.7806,"longitude":90.4193}}},"travelMode":"DRIVE","routingPreference":"TRAFFIC_AWARE"}'
```
Expected: JSON with `"duration": "NNNs"` and `distanceMeters`. Errors: `403 PERMISSION_DENIED` → API not enabled or key restricted wrong; `400` → malformed body.

## Later (not needed for M1 backend)
- **iOS**: Apple Developer Program ($99/yr), APNs auth key uploaded to Firebase, bundle id registered.
- **Android**: Play Console ($25 one-time), `google-services.json` downloaded from Firebase after registering the Android app.

## Cost summary
| Item | Now | At ~1,000 users |
|---|---|---|
| Firebase (Firestore, Functions, FCM) | $0 | ~$5–25/mo |
| Google Routes API | $0 (under 10k) | swap to self-hosted Valhalla (~$20/mo VPS) |
| Apple Developer | $99/yr | $99/yr |
| Google Play | $25 once | — |
