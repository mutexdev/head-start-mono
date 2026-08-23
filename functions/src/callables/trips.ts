// functions/src/callables/trips.ts
//
// Trip lifecycle callables. Three contract rules are load-bearing here:
//   * CLIENT_CONTRACT.md line 17 / ADDENDUM section F — a valid client `etaSec`
//     means ZERO routing calls. The branch below must never touch provider().
//   * ADDENDUM section G — `arrived`/`cancelled` push the OTHER member.
//   * ADDENDUM section D — every trip-scoped push carries `data.tripId`, which
//     the push layer injects from the `ctx` argument: sendPush(m, { tripId }).
import { onCall, HttpsError } from 'firebase-functions/v2/https';
// 'firebase-functions/logger', never the package root: the root index pulls in
// ESM-only `jose` transitively and the CJS jest runner cannot parse it.
import * as logger from 'firebase-functions/logger';
import { trips, spots, users, replies, now } from '../io/firestore';
import { directions, GOOGLE_ROUTES_KEY, ROUTING_PROVIDER, DETOUR_FACTOR } from '../io/routing';
import { sendPush } from '../io/push';
import { uidOf, requireActivePair, otherMember } from './auth';
import { bandsFor, fallbackEtaSec } from '../engine/eta';
import { haversineMeters } from '../engine/geo';
import { msg, replyText } from '../messages';
import { TripDoc, initialAlerts, ReplyKind, LatLng } from '../types';

async function activeTripFor(pairId: string) {
  const q = await trips()
    .where('pairId', '==', pairId)
    .where('state', 'in', ['armed', 'driving'])
    .limit(1)
    .get();
  return q.empty ? null : q.docs[0];
}

async function nameOf(uid: string): Promise<string> {
  return (await users().doc(uid).get()).data()?.displayName ?? 'Your driver';
}

/** What startTrip resolved for the route, and how many routing calls it cost. */
interface StartRoute {
  etaSec: number;
  distanceM: number;
  polyline?: string;
  approximate: boolean;
  routingCalls: 0 | 1;
  /** Only set when a routing call was actually attempted — it throttles the next poll. */
  routedAt: boolean;
}

/**
 * CLIENT_CONTRACT.md line 17: "`etaSec` = on-device ETA (iOS MapKit); when sent
 * the server makes no routing call." The plan doc called directions()
 * unconditionally and overwrote the ETA afterwards, which burns a Routes quota
 * call per iOS trip and fails the trip when routing is down even though the
 * client already had a perfectly good ETA. The contract wins.
 */
async function resolveStartRoute(from: LatLng, spot: LatLng, clientEtaRaw: unknown): Promise<StartRoute> {
  const clientEta = Number(clientEtaRaw);
  if (Number.isFinite(clientEta) && clientEta > 0) {
    return {
      etaSec: Math.round(clientEta),
      distanceM: Math.round(haversineMeters(from, spot) * DETOUR_FACTOR),
      polyline: undefined,
      approximate: false,
      routingCalls: 0,
      routedAt: false,
    };
  }
  try {
    const r = await directions(from, spot);
    return {
      etaSec: r.etaSec,
      distanceM: Math.round(r.distanceM),
      polyline: r.polyline,
      approximate: false,
      routingCalls: 1,
      routedAt: true,
    };
  } catch (e) {
    logger.error('routing failed at start', { provider: ROUTING_PROVIDER.value(), err: String(e) });
    const distanceM = Math.round(haversineMeters(from, spot) * DETOUR_FACTOR);
    return {
      etaSec: fallbackEtaSec(distanceM, 10),
      distanceM,
      polyline: undefined,
      approximate: true,
      routingCalls: 0,
      routedAt: true,
    };
  }
}

export const startTrip = onCall({ secrets: [GOOGLE_ROUTES_KEY] }, async (req) => {
  const uid = uidOf(req);
  const spotId = String(req.data?.spotId ?? '');
  const from = { lat: Number(req.data?.lat), lng: Number(req.data?.lng) };
  if (!Number.isFinite(from.lat) || !Number.isFinite(from.lng)) throw new HttpsError('invalid-argument', 'bad-coords');
  const spotSnap = await spots().doc(spotId).get();
  if (!spotSnap.exists) throw new HttpsError('not-found', 'spot-not-found');
  const spot = spotSnap.data()!;
  const pair = await requireActivePair(spot.pairId, uid);
  const receiverUid = otherMember(pair, uid);

  const existing = await activeTripFor(spot.pairId);
  if (existing && existing.data().state === 'driving') {
    // ADDENDUM section E: the client attaches to the running trip and must not
    // replay first-start UI.
    const d = existing.data();
    return { tripId: existing.id, bands: d.bands, etaSeconds: d.eta?.seconds, existing: true };
  }

  const t = now();
  const route = await resolveStartRoute(from, spot, req.data?.etaSec);
  const bands = bandsFor(route.distanceM, route.etaSec, spot.leadTimeMin);
  const driverName = await nameOf(uid);
  const fuzzy = !!req.data?.fuzzy;

  const doc: TripDoc = {
    pairId: spot.pairId, driverUid: uid, receiverUid, spotId,
    spot: { lat: spot.lat, lng: spot.lng, radiusM: spot.radiusM, name: spot.name },
    leadTimeMin: spot.leadTimeMin, state: 'driving', createdAt: t, startedAt: t, startPos: from,
    eta: { seconds: route.etaSec, updatedAt: t, approximate: route.approximate },
    // Conditional spread, not `routePolyline: undefined`: the admin SDK rejects
    // undefined values outright ("Cannot use 'undefined' as a Firestore value").
    ...(route.polyline ? { routePolyline: route.polyline } : {}),
    routeDistanceM: route.distanceM,
    bands, alerts: { ...initialAlerts(), started: true }, fuzzy,
    ...(route.routedAt ? { lastRoutingCallAt: t } : {}),
    routingCalls: route.routingCalls, phaseHint: 'far',
    receiverView: { etaSeconds: route.etaSec, progressPct: 0, ...(fuzzy ? {} : { lastPos: from }) },
  };

  let tripId: string;
  if (existing) { // armed -> driving
    await existing.ref.set(doc, { merge: true });
    tripId = existing.id;
  } else {
    tripId = (await trips().add(doc)).id;
  }
  await sendPush(msg.started(receiverUid, driverName, route.etaSec, spot.name, route.approximate), { tripId });
  return { tripId, bands, etaSeconds: route.etaSec, existing: false };
});

export const endTrip = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const reason = req.data?.reason === 'arrived' ? 'arrived' : 'cancelled';
  const ref = trips().doc(tripId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid && trip.receiverUid !== uid) throw new HttpsError('permission-denied', 'not-paired');
  if (!['armed', 'driving'].includes(trip.state)) return { ok: true, alreadyEnded: true };
  await ref.update({ state: reason, endedAt: now(), 'alerts.arrived': reason === 'arrived' });
  const name = await nameOf(uid);
  // ADDENDUM section G: whoever ends the trip does NOT get pushed their own action.
  const other = uid === trip.driverUid ? trip.receiverUid : trip.driverUid;
  // msg.arrived's `driver` parameter is always about the DRIVER, regardless of
  // who called endTrip — a receiver-initiated arrival must still read "<driver>
  // has arrived", not "<receiver> has arrived". msg.cancelled's `by` parameter
  // is genuinely the caller (whoever cancelled), so that one keeps `name`.
  const driverName = reason === 'arrived' && uid !== trip.driverUid ? await nameOf(trip.driverUid) : name;
  await sendPush(
    reason === 'arrived' ? msg.arrived(other, driverName, trip.spot.name) : msg.cancelled(other, name),
    { tripId },
  );
  return { ok: true };
});

export const armTrip = onCall(async (req) => {
  const uid = uidOf(req);
  const spotId = String(req.data?.spotId ?? '');
  const spotSnap = await spots().doc(spotId).get();
  if (!spotSnap.exists) throw new HttpsError('not-found', 'spot-not-found');
  const spot = spotSnap.data()!;
  const pair = await requireActivePair(spot.pairId, uid);
  const driverUid = otherMember(pair, uid);
  const existing = await activeTripFor(spot.pairId);
  if (existing) throw new HttpsError('already-exists', 'trip-active');
  const t = now();
  const neededBy = Number.isFinite(Number(req.data?.neededBy)) ? Number(req.data.neededBy) : undefined;
  const doc: TripDoc = {
    pairId: spot.pairId, driverUid, receiverUid: uid, spotId,
    spot: { lat: spot.lat, lng: spot.lng, radiusM: spot.radiusM, name: spot.name },
    leadTimeMin: spot.leadTimeMin, state: 'armed', createdAt: t, alerts: initialAlerts(), fuzzy: false,
    routingCalls: 0, phaseHint: 'far', ...(neededBy ? { neededBy } : {}),
  };
  const ref = await trips().add(doc);
  await sendPush(msg.armed(driverUid, await nameOf(uid), spot.name), { tripId: ref.id });
  return { tripId: ref.id };
});

export const sendReply = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const kind = String(req.data?.kind ?? 'custom') as ReplyKind;
  const snap = await trips().doc(tripId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid && trip.receiverUid !== uid) throw new HttpsError('permission-denied', 'not-paired');
  const text = kind === 'custom'
    ? String(req.data?.text ?? '').trim().slice(0, 140)
    : (replyText[kind]?.(trip.spot.name) ?? '');
  // `bad-reply` is NOT in CLIENT_CONTRACT.md's error list; ADDENDUM section O
  // makes it real and both clients map it. See functions/README.md.
  if (!text) throw new HttpsError('invalid-argument', 'bad-reply');
  await replies(tripId).add({ fromUid: uid, kind, text, ts: now() });
  const other = uid === trip.driverUid ? trip.receiverUid : trip.driverUid;
  await sendPush(msg.reply(other, await nameOf(uid), text), { tripId });
  return { ok: true };
});

export const setRunningLate = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const extraMin = Math.min(60, Math.max(1, Math.round(Number(req.data?.extraMin ?? 5))));
  const snap = await trips().doc(tripId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid) throw new HttpsError('permission-denied', 'driver-only');
  await replies(tripId).add({ fromUid: uid, kind: 'runningLate', text: `About ${extraMin} more min`, ts: now() });
  await sendPush(msg.runningLate(trip.receiverUid, await nameOf(uid), extraMin), { tripId });
  return { ok: true };
});
