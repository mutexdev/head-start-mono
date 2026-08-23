// STUB. The real implementation is docs/superpowers/plans/2026-08-22-m1-backend-functions.md. This exists only so the iOS client can be validated with no cloud and no billing.
//
// ---------------------------------------------------------------------------
// WHEN THIS RUNS: only when the repo root has no `firebase.json` / `functions/`.
// `ios/scripts/emulator-up.sh` ALWAYS prefers the real backend and says which one it
// chose. As of this batch the real backend exists, so this file is the cold spare.
//
// WHAT IT IS: the thinnest thing that satisfies docs/CLIENT_CONTRACT.md well enough for
// the iOS client to be exercised — correct request/response shapes, correct error codes
// (the contract code is the callable's `message`), the trip documents the client listens
// to, and a positions trigger that recomputes `eta`, `receiverView`, `phaseHint` and the
// `alerts` ladder crudely.
//
// WHAT IT IS NOT: it does not implement smoothEta, the slip ladder, housekeeping
// (lost/timeout/no-show), routing, `_debugPushes`, or anything's real thresholds. Do not
// port a line of it into `functions/`. Do not deploy it.
// ---------------------------------------------------------------------------

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

// Region pin FIRST: both client planners hard-code
// http://127.0.0.1:5001/<project>/us-central1/<name>.
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

initializeApp();
const db = getFirestore();

const now = () => Date.now();

/** The contract's error codes travel as the callable `message`, not as the status. */
function fail(code, status = 'failed-precondition') {
  return new HttpsError(status, code);
}
function uidOf(request) {
  const uid = request.auth && request.auth.uid;
  if (!uid) throw fail('sign-in required', 'unauthenticated');
  return uid;
}
function num(v) {
  return typeof v === 'number' && Number.isFinite(v);
}
function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, Math.round(v)));
}
const R = 6371000;
function haversine(aLat, aLng, bLat, bLng) {
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(bLat - aLat);
  const dLng = toRad(bLng - aLng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(aLat)) * Math.cos(toRad(bLat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.min(1, Math.sqrt(s)));
}
/** Mirrors functions/src/engine/eta.ts bandsFor(). */
function bandsFor(distanceM, etaSec, leadTimeMin) {
  const v = distanceM / Math.max(etaSec, 1);
  const m = (min) => Math.min(distanceM, Math.round(min * 60 * v));
  return { far: m(12), near: m(7), lead: m(leadTimeMin + 2) };
}
const INVITE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
function inviteCode() {
  let out = '';
  for (let i = 0; i < 6; i++) {
    out += INVITE_ALPHABET[Math.floor(Math.random() * INVITE_ALPHABET.length)];
  }
  return out;
}

async function activePairFor(uid) {
  const snap = await db
    .collection('pairs')
    .where('members', 'array-contains', uid)
    .where('status', '==', 'active')
    .limit(1)
    .get();
  return snap.empty ? null : snap.docs[0];
}

// ── the twelve M1 callables (CLIENT_CONTRACT_ADDENDUM.md §A) ────────────────

exports.registerPushToken = onCall(async (request) => {
  const uid = uidOf(request);
  const { token, platform, displayName } = request.data || {};
  if (typeof token !== 'string' || token.length < 20) throw fail('bad-token');
  if (platform !== 'ios' && platform !== 'android') throw fail('bad-token');
  const name = (displayName || '').trim();
  await db.collection('users').doc(uid).set(
    { tokens: FieldValue.arrayUnion(token), platform, ...(name ? { displayName: name } : {}) },
    { merge: true }
  );
  // ADDENDUM §M — memberNames is denormalised so neither side reads the other's user doc.
  if (name) {
    const pairs = await db.collection('pairs').where('members', 'array-contains', uid).get();
    await Promise.all(
      pairs.docs.map((d) => d.ref.set({ memberNames: { [uid]: name } }, { merge: true }))
    );
  }
  return { ok: true };
});

exports.createPair = onCall(async (request) => {
  const uid = uidOf(request);
  if (await activePairFor(uid)) throw fail('not-paired');
  const name = ((await db.collection('users').doc(uid).get()).get('displayName') || '').trim();
  const code = inviteCode();
  const ref = await db.collection('pairs').add({
    members: [uid],
    memberNames: name ? { [uid]: name } : {},
    status: 'pending',
    inviteCode: code,
    createdBy: uid,
    createdAt: now(),
  });
  return { pairId: ref.id, inviteCode: code };
});

exports.acceptPair = onCall(async (request) => {
  const uid = uidOf(request);
  const code = String((request.data || {}).code || '').toUpperCase();
  const snap = await db.collection('pairs').where('inviteCode', '==', code).limit(1).get();
  if (snap.empty) throw fail('bad-code');
  const doc = snap.docs[0];
  if (doc.get('createdBy') === uid) throw fail('own-code');
  if (doc.get('status') !== 'pending') throw fail('bad-code');
  const name = ((await db.collection('users').doc(uid).get()).get('displayName') || '').trim();
  await doc.ref.set(
    {
      members: FieldValue.arrayUnion(uid),
      memberNames: { ...(doc.get('memberNames') || {}), ...(name ? { [uid]: name } : {}) },
      status: 'active',
    },
    { merge: true }
  );
  return { pairId: doc.id };
});

exports.revokePair = onCall(async (request) => {
  const uid = uidOf(request);
  const pairId = String((request.data || {}).pairId || '');
  const doc = await db.collection('pairs').doc(pairId).get();
  if (!doc.exists || !(doc.get('members') || []).includes(uid)) throw fail('not-paired');
  await doc.ref.set({ status: 'revoked' }, { merge: true });
  return { ok: true };
});

exports.upsertSpot = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const pair = await activePairFor(uid);
  if (!pair || pair.id !== d.pairId) throw fail('not-paired');
  const name = String(d.name || '').trim();
  if (!name || name.length > 40) throw fail('bad-name');
  if (!num(d.lat) || !num(d.lng) || Math.abs(d.lat) > 90 || Math.abs(d.lng) > 180) {
    throw fail('bad-coords');
  }
  const body = {
    pairId: pair.id,
    name,
    lat: d.lat,
    lng: d.lng,
    radiusM: clamp(num(d.radiusM) ? d.radiusM : 100, 50, 500),
    leadTimeMin: clamp(num(d.leadTimeMin) ? d.leadTimeMin : 3, 1, 30),
    createdBy: uid,
  };
  if (d.spotId) {
    await db.collection('spots').doc(String(d.spotId)).set(body, { merge: true });
    return { spotId: String(d.spotId) };
  }
  const ref = await db.collection('spots').add({ ...body, createdAt: now() });
  return { spotId: ref.id };
});

exports.deleteSpot = onCall(async (request) => {
  const uid = uidOf(request);
  const spotId = String((request.data || {}).spotId || '');
  const doc = await db.collection('spots').doc(spotId).get();
  if (!doc.exists) throw fail('spot-not-found');
  const pair = await activePairFor(uid);
  if (!pair || pair.id !== doc.get('pairId')) throw fail('not-paired');
  await doc.ref.delete();
  return { ok: true };
});

/** ADDENDUM §F — a client `etaSec` means ZERO routing calls. The stub has no router at all. */
exports.startTrip = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const pair = await activePairFor(uid);
  if (!pair) throw fail('not-paired');
  const other = (pair.get('members') || []).find((m) => m !== uid);
  const spotDoc = await db.collection('spots').doc(String(d.spotId || '')).get();
  if (!spotDoc.exists) throw fail('spot-not-found');
  if (!num(d.lat) || !num(d.lng)) throw fail('bad-coords');

  const live = await db
    .collection('trips')
    .where('pairId', '==', pair.id)
    .where('state', 'in', ['armed', 'driving'])
    .limit(1)
    .get();

  const spot = {
    lat: spotDoc.get('lat'),
    lng: spotDoc.get('lng'),
    radiusM: spotDoc.get('radiusM'),
    name: spotDoc.get('name'),
  };
  const leadTimeMin = spotDoc.get('leadTimeMin') || 3;
  const distanceM = haversine(d.lat, d.lng, spot.lat, spot.lng) * 1.3;
  const etaSec = num(d.etaSec) && d.etaSec > 0 ? Math.round(d.etaSec) : Math.round(distanceM / 12);
  const bands = bandsFor(distanceM, etaSec, leadTimeMin);
  const t = now();

  if (!live.empty) {
    const existing = live.docs[0];
    await existing.ref.set(
      { state: 'driving', driverUid: uid, receiverUid: other, startedAt: t, bands },
      { merge: true }
    );
    return { tripId: existing.id, bands, etaSeconds: etaSec, existing: true };
  }

  const ref = await db.collection('trips').add({
    pairId: pair.id,
    driverUid: uid,
    receiverUid: other,
    spotId: spotDoc.id,
    spot,
    leadTimeMin,
    state: 'driving',
    createdAt: t,
    startedAt: t,
    eta: { seconds: etaSec, updatedAt: t, approximate: false },
    bands,
    phaseHint: 'far',
    distanceM,
    routingCalls: 0,
    fuzzy: d.fuzzy === true,
    receiverView: {
      etaSeconds: etaSec,
      progressPct: 0,
      updatedAt: t,
      ...(d.fuzzy === true ? {} : { point: { lat: d.lat, lng: d.lng } }),
    },
    alerts: { started: true, slipCount: 0 },
  });
  return { tripId: ref.id, bands, etaSeconds: etaSec, existing: false };
});

exports.armTrip = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const pair = await activePairFor(uid);
  if (!pair) throw fail('not-paired');
  const other = (pair.get('members') || []).find((m) => m !== uid);
  const spotDoc = await db.collection('spots').doc(String(d.spotId || '')).get();
  if (!spotDoc.exists) throw fail('spot-not-found');
  const live = await db
    .collection('trips')
    .where('pairId', '==', pair.id)
    .where('state', 'in', ['armed', 'driving'])
    .limit(1)
    .get();
  if (!live.empty) throw fail('trip-active');
  const ref = await db.collection('trips').add({
    pairId: pair.id,
    driverUid: other,
    receiverUid: uid,
    spotId: spotDoc.id,
    spot: {
      lat: spotDoc.get('lat'),
      lng: spotDoc.get('lng'),
      radiusM: spotDoc.get('radiusM'),
      name: spotDoc.get('name'),
    },
    leadTimeMin: spotDoc.get('leadTimeMin') || 3,
    state: 'armed',
    createdAt: now(),
    phaseHint: 'far',
    ...(num(d.neededBy) ? { neededBy: d.neededBy } : {}),
    alerts: { slipCount: 0 },
  });
  return { tripId: ref.id };
});

exports.endTrip = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const reason = d.reason === 'arrived' ? 'arrived' : 'cancelled';
  const doc = await db.collection('trips').doc(String(d.tripId || '')).get();
  if (!doc.exists) throw fail('trip-not-found');
  if (![doc.get('driverUid'), doc.get('receiverUid')].includes(uid)) throw fail('not-paired');
  await doc.ref.set({ state: reason, endedAt: now() }, { merge: true });
  return { ok: true };
});

exports.sendReply = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const kinds = ['fiveMore', 'takeYourTime', 'atSpot', 'custom'];
  if (!kinds.includes(d.kind)) throw fail('bad-reply');
  const text = String(d.text || '').trim();
  if (d.kind === 'custom' && !text) throw fail('bad-reply');   // ADDENDUM §O
  const doc = await db.collection('trips').doc(String(d.tripId || '')).get();
  if (!doc.exists) throw fail('trip-not-found');
  await doc.ref.collection('replies').add({
    fromUid: uid,
    kind: d.kind,
    text: text.slice(0, 120),
    ts: now(),
  });
  return { ok: true };
});

exports.setRunningLate = onCall(async (request) => {
  const uid = uidOf(request);
  const d = request.data || {};
  const doc = await db.collection('trips').doc(String(d.tripId || '')).get();
  if (!doc.exists) throw fail('trip-not-found');
  if (doc.get('driverUid') !== uid) throw fail('driver-only');
  const extraMin = clamp(num(d.extraMin) ? d.extraMin : 5, 1, 60);
  const eta = doc.get('eta') || { seconds: 0 };
  await doc.ref.set(
    { eta: { ...eta, seconds: (eta.seconds || 0) + extraMin * 60, updatedAt: now() } },
    { merge: true }
  );
  return { ok: true };
});

exports.setLowBattery = onCall(async (request) => {
  const uid = uidOf(request);
  await db.collection('users').doc(uid).set(
    { lowBattery: (request.data || {}).lowBattery === true },
    { merge: true }
  );
  return { ok: true };
});

// ── the positions trigger ──────────────────────────────────────────────────
//
// Crude on purpose. It recomputes just enough for the client to be exercised:
// eta from the position's own etaSec (iOS always sends one) or a 12 m/s stub,
// receiverView, phaseHint, and a monotonic alerts ladder ending in `arrived`.

const ARRIVE_SPEED_MPS = 2;
const ARRIVE_DWELL_MS = 20000;

exports.onPositionWrite = onDocumentCreated('trips/{tripId}/positions/{posId}', async (event) => {
  const p = event.data && event.data.data();
  if (!p) return;
  const ref = db.collection('trips').doc(event.params.tripId);
  const snap = await ref.get();
  if (!snap.exists || snap.get('state') !== 'driving') return;

  const trip = snap.data();
  const last = trip.lastPos;
  if (last && typeof last.ts === 'number' && p.ts <= last.ts) return;   // strictly increasing

  const spot = trip.spot;
  const distToSpot = haversine(p.lat, p.lng, spot.lat, spot.lng);
  const etaSec = num(p.etaSec) ? Math.round(p.etaSec) : Math.round((distToSpot * 1.3) / 12);
  const t = now();
  const alerts = { ...(trip.alerts || {}) };
  const startDistance = num(trip.distanceM) ? trip.distanceM : Math.max(distToSpot, 1);
  const patch = {
    // ADDENDUM §J — projected field by field. Never spread the incoming document: it
    // carries `expireAt: Timestamp`, and a Timestamp in lastPos is a hard decode failure
    // for the strict Swift/Kotlin decoders.
    lastPos: {
      lat: p.lat,
      lng: p.lng,
      accuracyM: p.accuracyM,
      speedMps: p.speedMps,
      ts: p.ts,
      ...(num(p.etaSec) ? { etaSec: p.etaSec } : {}),
    },
    eta: { seconds: etaSec, updatedAt: t, approximate: false },
    phaseHint: trip.bands && distToSpot <= trip.bands.near ? 'near' : 'far',
    receiverView: {
      etaSeconds: etaSec,
      progressPct: clamp(100 * (1 - distToSpot / startDistance), 0, 100),
      updatedAt: t,
      ...(trip.fuzzy === true ? {} : { point: { lat: p.lat, lng: p.lng } }),
    },
  };

  if (!alerts.tenMin && etaSec <= 600) alerts.tenMin = true;
  if (!alerts.leadTime && etaSec <= (trip.leadTimeMin || 3) * 60) alerts.leadTime = true;
  if (!alerts.arrived) {
    if (distToSpot <= spot.radiusM && p.speedMps < ARRIVE_SPEED_MPS) {
      if (alerts.arrivalDwellSince === undefined) {
        alerts.arrivalDwellSince = t;
      } else if (t - alerts.arrivalDwellSince >= ARRIVE_DWELL_MS) {
        alerts.arrived = true;
        patch.state = 'arrived';
        patch.endedAt = t;
        delete alerts.arrivalDwellSince;
      }
    } else {
      delete alerts.arrivalDwellSince;
    }
  }
  patch.alerts = alerts;   // whole-object set, so a deleted dwell key really disappears
  await ref.set(patch, { merge: true });
});
