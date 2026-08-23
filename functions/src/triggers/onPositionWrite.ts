// functions/src/triggers/onPositionWrite.ts
//
// The only place the pure engine meets Firestore, routing and push.
//
// Four things here are load-bearing and easy to break:
//
//  1. ADDENDUM section J — the incoming `positions/{id}` document carries an
//     `expireAt: Timestamp` (the rules REQUIRE it). A Timestamp must never reach
//     `trips/{id}.lastPos` or `receiverView`: it is a hard decode failure for the
//     strict Swift/Kotlin decoders. The Position handed to step() is therefore
//     built field-by-field below from exactly {lat,lng,accuracyM,speedMps,ts,etaSec?}.
//  2. CLIENT_CONTRACT.md line 17 / ADDENDUM F — a client-supplied `etaSec` (iOS
//     MapKit) means ZERO routing calls. `lastRoutingCallAt` is still advanced so
//     the throttle treats it as a poll.
//  3. Concurrency — the engine patch is computed from a snapshot taken BEFORE the
//     transaction and contains the whole `alerts` object. Two positions landing
//     close together (5 s near-phase cadence, or an offline replay burst) would
//     otherwise clobber each other's slipCount and alert flags. The transaction
//     re-reads and bails out unless the trip is still `driving` AND this position
//     is strictly newer than the stored one — making the trigger a monotonic
//     last-writer-wins on `position.ts`, which is exactly the ordering the
//     contract's oldest-first offline-replay rule guarantees.
//  4. ETA_POLL_SCALE — the real 60/30/15 s routing throttles mean a 30-second
//     scripted drive would fetch one ETA and fire no alerts. The scale is read
//     HERE (the engine and eta.ts stay env-free and pure) and threaded into
//     every step() call.
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
// 'firebase-functions/logger', never the package root: the root index pulls in
// ESM-only `jose` transitively and the CJS jest runner cannot parse it.
import * as logger from 'firebase-functions/logger';
import { FieldValue } from 'firebase-admin/firestore';
import { db, trips, users } from '../io/firestore';
import { directions, GOOGLE_ROUTES_KEY } from '../io/routing';
import { sendAll } from '../io/push';
import { step, EnginePatch } from '../engine/tripEngine';
import { fallbackEtaSec } from '../engine/eta';
import { decodePolyline, polylineRemainingMeters, haversineMeters } from '../engine/geo';
import { Position, PushMessage, TripDoc } from '../types';

/** Compressed routing throttle for the emulator harness (functions/.env.local: 0.02). */
const etaPollScale = Number(process.env.ETA_POLL_SCALE ?? '1') || 1;

/**
 * Projects the raw Firestore document onto the exact Position shape the engine
 * accepts. `expireAt` — and anything else a future client starts sending — is
 * dropped here and can never reach `lastPos`. Returns undefined for a document
 * that is not a usable fix.
 */
export function toPosition(raw: Record<string, unknown> | undefined): Position | undefined {
  if (!raw) return undefined;
  const lat = Number(raw.lat);
  const lng = Number(raw.lng);
  const ts = Number(raw.ts);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !Number.isFinite(ts)) return undefined;
  const accuracyM = Number(raw.accuracyM);
  const speedMps = Number(raw.speedMps);
  const etaSec = Number(raw.etaSec);
  return {
    lat,
    lng,
    accuracyM: Number.isFinite(accuracyM) ? accuracyM : 0,
    speedMps: Number.isFinite(speedMps) ? speedMps : 0,
    ts,
    ...(Number.isFinite(etaSec) && etaSec > 0 ? { etaSec: Math.round(etaSec) } : {}),
  };
}

export function toUpdate(p: EnginePatch, extra: Record<string, unknown> = {}): Record<string, unknown> {
  const u: Record<string, unknown> = { ...extra };
  if (p.lastPos) u.lastPos = p.lastPos;
  if (p.phaseHint) u.phaseHint = p.phaseHint;
  if (p.eta) u.eta = p.eta;
  if (p.pendingEtaSec !== undefined) u.pendingEtaSec = p.pendingEtaSec === null ? FieldValue.delete() : p.pendingEtaSec;
  if (p.alerts) u.alerts = p.alerts;
  if (p.state) u.state = p.state;
  if (p.endedAt) u.endedAt = p.endedAt;
  if (p.receiverView) u.receiverView = p.receiverView;
  return u;
}

export const onPositionWrite = onDocumentCreated(
  { document: 'trips/{tripId}/positions/{posId}', secrets: [GOOGLE_ROUTES_KEY] },
  async (event) => {
    const tripId = event.params.tripId;
    // NEVER `event.data?.data() as Position` — that keeps `expireAt: Timestamp`.
    const position = toPosition(event.data?.data() as Record<string, unknown> | undefined);
    if (!position) return;
    const ref = trips().doc(tripId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const trip = snap.data() as TripDoc & { pendingEtaSec?: number };
    if (trip.state !== 'driving') return;
    if (trip.lastPos && position.ts <= trip.lastPos.ts) return; // out-of-order replay

    const driver = (await users().doc(trip.driverUid).get()).data();
    const driverName = driver?.displayName ?? 'Your driver';
    const nowMs = Date.now();

    // Pass 1: no ETA → the engine tells us whether to fetch one.
    let out = step({ trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec, etaPollScale });
    let extra: Record<string, unknown> = {};

    // On-device ETA (iOS MapKit) present → use it, no routing call at all.
    const clientEta = position.etaSec;
    if (clientEta !== undefined && Number.isFinite(clientEta) && clientEta > 0) {
      out = step({
        trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec, etaPollScale,
        freshEtaSec: Math.round(clientEta), freshEtaApproximate: !!driver?.lowBattery,
      });
      extra = { lastRoutingCallAt: nowMs }; // counts as a poll for throttling purposes
    } else if (out.wantsEta) {
      let freshEtaSec: number;
      let approximate = false;
      try {
        const r = await directions(position, trip.spot);
        freshEtaSec = r.etaSec;
        // keep the polyline fresh so the remaining-distance fallback stays meaningful
        extra = { lastRoutingCallAt: nowMs, routingCalls: FieldValue.increment(1), routePolyline: r.polyline };
      } catch (e) {
        logger.warn('routing failed; using fallback', { tripId, err: String(e) });
        // trip.routePolyline is ABSENT on trips started with a client etaSec
        // (ADDENDUM F) — the haversine branch is the normal iOS case, not an edge case.
        const remaining = trip.routePolyline
          ? polylineRemainingMeters(decodePolyline(trip.routePolyline), position)
          : haversineMeters(position, trip.spot) * 1.3;
        const avgSpeed = trip.lastPos && position.ts > trip.lastPos.ts
          ? haversineMeters(position, trip.lastPos) / ((position.ts - trip.lastPos.ts) / 1000)
          : position.speedMps;
        freshEtaSec = fallbackEtaSec(remaining, avgSpeed);
        approximate = true;
        extra = { lastRoutingCallAt: nowMs };
      }
      if (driver?.lowBattery) approximate = true;
      out = step({
        trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec, etaPollScale,
        freshEtaSec, freshEtaApproximate: approximate,
      });
    }

    // Idempotency + ordering: re-read inside a transaction, drop pushes already
    // sent, and refuse to write at all if we lost the race.
    const pushes = await db.runTransaction<PushMessage[]>(async (tx) => {
      const fresh = (await tx.get(ref)).data() as TripDoc | undefined;
      if (!fresh) return [];
      if (fresh.state !== 'driving') return [];
      // A newer position already landed (or this one is a replay): its patch was
      // computed from a strictly fresher snapshot, so ours must not overwrite it.
      if (fresh.lastPos && position.ts <= fresh.lastPos.ts) return [];
      const already = fresh.alerts;
      const keep = out.pushes.filter((p) => {
        const k = p.data.kind;
        if (k === 'tenMin') return !already.tenMin;
        if (k === 'leadTime') return !already.leadTime;
        if (k === 'arrived') return !already.arrived;
        if (k === 'didYouLeave') return !already.didYouLeave;
        if (k === 'slip') return (out.patch.alerts?.slipCount ?? 0) > already.slipCount;
        return true;
      });
      tx.update(ref, toUpdate(out.patch, extra));
      return keep;
    });

    // ADDENDUM D: every trip-scoped push carries data.tripId.
    await sendAll(pushes, { tripId });
  },
);
