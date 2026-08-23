// functions/test/triggers/onPositionWrite.emulator.test.ts
//
// Proves the four things batch be6 is actually responsible for:
//   * ADDENDUM J — `expireAt: Timestamp` never reaches trips/{id}.lastPos.
//   * ADDENDUM F — a client etaSec costs ZERO routing calls; no client etaSec
//     routes once and stores a polyline.
//   * the transaction's monotonic ts guard drops out-of-order / replayed fixes.
//   * the trigger is really wired into the Functions emulator: writing a real
//     `trips/{id}/positions/{id}` document moves the trip on its own.
//
// Runs only under: npm run test:emu.
process.env.GCLOUD_PROJECT = 'fin-e8358';
// Must be set BEFORE the modules under test are first used: it selects the
// distance-aware routing stub and the FirestorePushSender sink. `emulators:exec`
// does NOT export FUNCTIONS_EMULATOR to the exec'd process.
process.env.FUNCTIONS_EMULATOR = 'true';

import type { CallableRequest } from 'firebase-functions/v2/https';
import { Timestamp, QueryDocumentSnapshot } from 'firebase-admin/firestore';
import { db, pairs, spots, trips, users, debugPushes, positions } from '../../src/io/firestore';
import { startTrip } from '../../src/callables/trips';
import { onPositionWrite, toPosition } from '../../src/triggers/onPositionWrite';

const T0 = 1_700_000_000_000;
const DRIVER = 'd1';
const RECEIVER = 'r1';
const SPOT = { lat: 37.42, lng: -122.08 };

const asReq = (uid: string, data: Record<string, unknown>) =>
  ({ data, auth: { uid, token: {} }, rawRequest: {}, acceptsStreaming: false } as unknown as CallableRequest<any>);

async function wipe() {
  await db.recursiveDelete(trips());
  for (const name of ['pairs', 'spots', 'users', '_debugPushes']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

async function seed(): Promise<string> {
  await users().doc(DRIVER).set({ phone: '+15550001111', displayName: 'Mostafi', platform: 'ios', fcmTokens: [], createdAt: T0 });
  await users().doc(RECEIVER).set({ phone: '+15550002222', displayName: 'Sara', platform: 'android', fcmTokens: [], createdAt: T0 });
  await pairs().doc('p1').set({
    members: [DRIVER, RECEIVER], status: 'active', inviteCode: 'AAA111',
    createdBy: DRIVER, createdAt: T0, memberNames: { [DRIVER]: 'Mostafi', [RECEIVER]: 'Sara' },
  });
  const spot = await spots().add({
    pairId: 'p1', name: 'School gate', lat: SPOT.lat, lng: SPOT.lng,
    radiusM: 100, leadTimeMin: 3, createdBy: RECEIVER, createdAt: T0,
  });
  return spot.id;
}

/**
 * A position document exactly as the client writes it — `expireAt: Timestamp`
 * included — parked on a subcollection the trigger pattern does NOT match, so
 * `.run()` below is the only thing that processes it and the test stays
 * deterministic. The snapshot is a genuine Firestore snapshot, which is the
 * whole point: a hand-built literal could not carry a real Timestamp.
 */
async function fixture(tripId: string, p: Record<string, unknown>): Promise<QueryDocumentSnapshot> {
  const ref = trips().doc(tripId).collection('_fixtures').doc();
  await ref.set({ ...p, expireAt: Timestamp.fromMillis(Date.now() + 86_400_000) });
  return (await ref.get()) as QueryDocumentSnapshot;
}

const run = (tripId: string, snap: QueryDocumentSnapshot) =>
  onPositionWrite.run({ data: snap, params: { tripId, posId: snap.id } } as any);

/** Starts a driving trip and back-dates trip.eta so smoothEta accepts the next reading. */
async function driving(spotId: string, data: Record<string, unknown>): Promise<string> {
  const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, ...data }));
  await trips().doc(res.tripId).update({ 'eta.updatedAt': Date.now() - 60_000 });
  return res.tripId;
}

describe('onPositionWrite (emulator)', () => {
  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });
  beforeEach(wipe);

  it('never lets expireAt reach lastPos or receiverView', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    const snap = await fixture(tripId, { lat: 37.41, lng: -122.07, accuracyM: 8, speedMps: 14, ts: Date.now(), etaSec: 120 });
    expect(snap.data().expireAt).toBeInstanceOf(Timestamp);

    await run(tripId, snap);

    const t = (await trips().doc(tripId).get()).data()!;
    expect(Object.keys(t.lastPos!).sort()).toEqual(['accuracyM', 'etaSec', 'lat', 'lng', 'speedMps', 'ts']);
    expect((t.lastPos as any).expireAt).toBeUndefined();
    expect(t.receiverView).toEqual(expect.objectContaining({ etaSeconds: 120, lastPos: { lat: 37.41, lng: -122.07 } }));
  });

  it('a client etaSec costs zero routing calls but still advances the throttle', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    const before = (await trips().doc(tripId).get()).data()!;
    expect(before.routingCalls).toBe(0);
    expect(before.lastRoutingCallAt).toBeUndefined();

    await run(tripId, await fixture(tripId, { lat: 37.40, lng: -122.06, accuracyM: 8, speedMps: 14, ts: Date.now(), etaSec: 300 }));

    const t = (await trips().doc(tripId).get()).data()!;
    expect(t.routingCalls).toBe(0);
    expect(t.routePolyline).toBeUndefined();
    expect(t.lastRoutingCallAt).toEqual(expect.any(Number));
    expect(t.eta!.seconds).toBe(300);
  });

  it('no client etaSec routes once and refreshes the polyline', async () => {
    const tripId = await driving(await seed(), {}); // server routing at start => routingCalls 1
    await run(tripId, await fixture(tripId, { lat: 37.40, lng: -122.06, accuracyM: 8, speedMps: 14, ts: Date.now() }));

    const t = (await trips().doc(tripId).get()).data()!;
    expect(t.routingCalls).toBe(2);
    expect(typeof t.routePolyline).toBe('string');
    expect(t.eta!.approximate).toBe(false);
  });

  it('walks the alert ladder and stamps every push with data.tripId', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    // ~1.43 km out: stub eta = haversine*1.3/12 ≈ 155 s → tenMin AND leadTime (3 min).
    await run(tripId, await fixture(tripId, { lat: 37.4325, lng: -122.084, accuracyM: 8, speedMps: 14, ts: Date.now() }));

    // Auto-ids are random, so a plain collection read is name-ordered, not send-ordered.
    const pushes = (await debugPushes().get()).docs.map((d) => d.data() as any);
    const kinds = pushes.map((p) => p.kind).sort();
    expect(kinds).toEqual(['leadTime', 'started', 'tenMin']);
    for (const p of pushes) expect(p.data.tripId).toBe(tripId);
    // ADDENDUM C: leadTime is the only urgent kind.
    expect(pushes.filter((p) => p.urgent).map((p) => p.kind)).toEqual(['leadTime']);

    // Idempotent: replaying an equivalent, newer fix must not re-fire either alert.
    await run(tripId, await fixture(tripId, { lat: 37.4325, lng: -122.084, accuracyM: 8, speedMps: 14, ts: Date.now() + 1000 }));
    expect((await debugPushes().get()).docs.map((d) => (d.data() as any).kind).sort()).toEqual(kinds);
  });

  it('drops an out-of-order fix without writing', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    const t1 = Date.now();
    await run(tripId, await fixture(tripId, { lat: 37.40, lng: -122.06, accuracyM: 8, speedMps: 14, ts: t1, etaSec: 300 }));
    const after = (await trips().doc(tripId).get()).data()!;

    // Older ts, wildly different location — must be ignored entirely.
    await run(tripId, await fixture(tripId, { lat: 37.10, lng: -121.90, accuracyM: 8, speedMps: 14, ts: t1 - 5000, etaSec: 4000 }));

    const t = (await trips().doc(tripId).get()).data()!;
    expect(t.lastPos).toEqual(after.lastPos);
    expect(t.eta).toEqual(after.eta);
  });

  it('ignores positions once the trip is no longer driving', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    await trips().doc(tripId).update({ state: 'cancelled' });
    await run(tripId, await fixture(tripId, { lat: 37.40, lng: -122.06, accuracyM: 8, speedMps: 14, ts: Date.now() }));
    const t = (await trips().doc(tripId).get()).data()!;
    expect(t.lastPos).toBeUndefined();
  });

  it('fires for real when a positions document is written (emulator wiring)', async () => {
    const tripId = await driving(await seed(), { etaSec: 900 });
    const ts = Date.now();
    await positions(tripId).add({
      lat: 37.41, lng: -122.07, accuracyM: 8, speedMps: 14, ts, etaSec: 200,
      expireAt: Timestamp.fromMillis(ts + 86_400_000) as any,
    });

    const deadline = Date.now() + 20_000;
    let t = (await trips().doc(tripId).get()).data()!;
    while (!t.lastPos && Date.now() < deadline) {
      await new Promise((r) => setTimeout(r, 300));
      t = (await trips().doc(tripId).get()).data()!;
    }
    expect(t.lastPos).toEqual({ lat: 37.41, lng: -122.07, accuracyM: 8, speedMps: 14, ts, etaSec: 200 });
  });
});

describe('toPosition (pure projection)', () => {
  it('keeps exactly the contract keys and drops everything else', () => {
    expect(toPosition({ lat: 1, lng: 2, accuracyM: 3, speedMps: 4, ts: 5, expireAt: Timestamp.fromMillis(9) }))
      .toEqual({ lat: 1, lng: 2, accuracyM: 3, speedMps: 4, ts: 5 });
    expect(toPosition({ lat: 1, lng: 2, accuracyM: 3, speedMps: 4, ts: 5, etaSec: 60.4 }))
      .toEqual({ lat: 1, lng: 2, accuracyM: 3, speedMps: 4, ts: 5, etaSec: 60 });
  });

  it('rejects a document without usable coordinates or timestamp', () => {
    expect(toPosition(undefined)).toBeUndefined();
    expect(toPosition({ lat: 1, lng: 2 })).toBeUndefined();
    expect(toPosition({ lat: 'x', lng: 2, ts: 5 })).toBeUndefined();
  });
});
