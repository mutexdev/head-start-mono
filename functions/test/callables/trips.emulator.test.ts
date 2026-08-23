// functions/test/callables/trips.emulator.test.ts
//
// Plan Task 13's emulator test, updated for what the emulator harness actually
// needs, plus the piece the plan doc never had: a REAL callable round-trip over
// HTTP with a genuine Bearer ID token, asserting the contract's response shapes
// and error codes exactly as a device would see them.
//
// Two deliberate changes from the plan's version:
//   * `ROUTING_STUB_SPEED_MPS='12'` rather than `ROUTING_STUB_ETA_SEC`. A FIXED
//     stub ETA can never walk the ladder from tenMin down to leadTime, so a run
//     against it looks green while proving nothing. The fixed-ETA behaviour is
//     still covered by its own case below, because production keeps that escape
//     hatch.
//   * Proves the two contract deviations this backend had to make:
//       CLIENT_CONTRACT.md line 17 / ADDENDUM F — a client etaSec means ZERO
//       routing calls (the plan called directions() unconditionally);
//       ADDENDUM G — endTrip pushes the OTHER member, never the caller.
//
// Runs only under: npm run test:emu.
process.env.GCLOUD_PROJECT = 'fin-e8358';
// Must be set BEFORE the modules under test are first used: it selects the
// distance-aware routing stub (no Routes key is ever read) and the
// FirestorePushSender sink that writes `_debugPushes`. `firebase emulators:exec`
// exports FIRESTORE_EMULATOR_HOST but not FUNCTIONS_EMULATOR to the exec'd
// process, so the test process has to declare it itself.
process.env.FUNCTIONS_EMULATOR = 'true';
process.env.ROUTING_STUB_SPEED_MPS = '12';
// firebase-admin picks the emulated Auth signer up from this at getAuth() time;
// set here so it is in place before src/io/firestore initialises the app below.
process.env.FIREBASE_AUTH_EMULATOR_HOST = '127.0.0.1:9099';

import type { CallableRequest } from 'firebase-functions/v2/https';
import { db, pairs, spots, trips, users, debugPushes } from '../../src/io/firestore';
import { startTrip, endTrip } from '../../src/callables/trips';
import { directions, DETOUR_FACTOR } from '../../src/io/routing';
import { haversineMeters, decodePolyline } from '../../src/engine/geo';

// Plain CommonJS, no types — the same module the driver script and both client
// planners use. tsconfig only compiles `src`, so this is never type-checked by
// tsc; ts-jest transpiles the surrounding test file only.
// eslint-disable-next-line @typescript-eslint/no-var-requires
const emu = require('../../scripts/lib/emuClient');

const T0 = 1_700_000_000_000;
const DRIVER = 'd1';
const RECEIVER = 'r1';

// A CallableRequest carries an express rawRequest we neither have nor need when
// invoking the handler directly via `.run()`.
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
    pairId: 'p1', name: 'School gate', lat: 37.42, lng: -122.08,
    radiusM: 100, leadTimeMin: 3, createdBy: RECEIVER, createdAt: T0,
  });
  return spot.id;
}

describe('routing stub selection (emulator)', () => {
  it('is distance-aware at ROUTING_STUB_SPEED_MPS, and returns a real polyline', async () => {
    const from = { lat: 37.7349, lng: -122.4694 };
    const to = { lat: 37.7749, lng: -122.4194 };
    const r = await directions(from, to);

    const expectedDistance = Math.round(haversineMeters(from, to) * DETOUR_FACTOR);
    expect(r.distanceM).toBe(expectedDistance);
    expect(r.etaSec).toBe(Math.round(expectedDistance / 12));
    // A genuinely encoded polyline, so the fallback remaining-distance path over
    // decodePolyline() is exercised rather than silently skipped.
    const pts = decodePolyline(r.polyline);
    expect(pts).toHaveLength(2);
    expect(pts[0].lat).toBeCloseTo(from.lat, 4);
    expect(pts[1].lng).toBeCloseTo(to.lng, 4);
  });

  it('ROUTING_STUB_ETA_SEC still forces a fixed ETA (production escape hatch)', async () => {
    process.env.ROUTING_STUB_ETA_SEC = '170';
    try {
      const r = await directions({ lat: 0, lng: 0 }, { lat: 1, lng: 1 });
      expect(r.etaSec).toBe(170);
      expect(r.distanceM).toBe(1700);
    } finally {
      delete process.env.ROUTING_STUB_ETA_SEC;
    }
  });
});

describe('trip callables (emulator)', () => {
  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });
  beforeEach(wipe);

  it('startTrip with a client etaSec makes ZERO routing calls', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));

    expect(res.existing).toBe(false);
    expect(res.etaSeconds).toBe(900);
    expect(res.bands).toEqual(expect.objectContaining({ far: expect.any(Number), near: expect.any(Number), lead: expect.any(Number) }));

    const trip = (await trips().doc(res.tripId).get()).data()!;
    expect(trip.routingCalls).toBe(0);
    expect(trip.routePolyline).toBeUndefined();
    expect(trip.lastRoutingCallAt).toBeUndefined();
    expect(trip.eta).toEqual({ seconds: 900, updatedAt: expect.any(Number), approximate: false });
    // haversine(from, spot) * 1.3, per ADDENDUM F.
    expect(trip.routeDistanceM).toBeGreaterThan(10_000);
    expect(trip.state).toBe('driving');
  });

  it('startTrip without a client etaSec routes once', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03 }));
    const trip = (await trips().doc(res.tripId).get()).data()!;
    expect(trip.routingCalls).toBe(1);
    expect(typeof trip.routePolyline).toBe('string');
    expect(trip.lastRoutingCallAt).toEqual(expect.any(Number));
  });

  it('startTrip on an already-driving trip returns existing: true', async () => {
    const spotId = await seed();
    const first: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));
    const second: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.34, lng: -122.04, etaSec: 800 }));
    expect(second.existing).toBe(true);
    expect(second.tripId).toBe(first.tripId);
    expect(second.etaSeconds).toBe(900);
  });

  it('every trip-scoped push carries data.tripId', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));
    const pushes = (await debugPushes().get()).docs.map((d) => d.data() as any);
    expect(pushes).toHaveLength(1);
    expect(pushes[0].toUid).toBe(RECEIVER);
    expect(pushes[0].data).toEqual({ kind: 'started', tripId: res.tripId });
  });

  it('endTrip(arrived) called by the DRIVER pushes the receiver', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));
    await endTrip.run(asReq(DRIVER, { tripId: res.tripId, reason: 'arrived' }));
    const pushes = (await debugPushes().get()).docs.map((d) => d.data() as any);
    const arrived = pushes.filter((p) => p.kind === 'arrived');
    expect(arrived).toHaveLength(1);
    expect(arrived[0].toUid).toBe(RECEIVER);
    expect((await trips().doc(res.tripId).get()).data()!.state).toBe('arrived');
  });

  it('endTrip called by the RECEIVER pushes the DRIVER, not themselves', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));
    await endTrip.run(asReq(RECEIVER, { tripId: res.tripId, reason: 'cancelled' }));
    const cancelled = (await debugPushes().get()).docs.map((d) => d.data() as any).filter((p) => p.kind === 'cancelled');
    expect(cancelled).toHaveLength(1);
    expect(cancelled[0].toUid).toBe(DRIVER);
    expect(cancelled[0].data.tripId).toBe(res.tripId);
  });

  it('endTrip(arrived) called by the RECEIVER pushes the DRIVER, not themselves', async () => {
    const spotId = await seed();
    const res: any = await startTrip.run(asReq(DRIVER, { spotId, lat: 37.33, lng: -122.03, etaSec: 900 }));
    await endTrip.run(asReq(RECEIVER, { tripId: res.tripId, reason: 'arrived' }));
    const arrived = (await debugPushes().get()).docs.map((d) => d.data() as any).filter((p) => p.kind === 'arrived');
    expect(arrived).toHaveLength(1);
    expect(arrived[0].toUid).toBe(DRIVER);
    // Regression: the receiver-initiated call must not word the alert as if the
    // RECEIVER (Sara) arrived — msg.arrived's subject is always the driver.
    expect(arrived[0].title).toBe('Mostafi has arrived');
  });
});

/**
 * The only test that goes through the wire the way a phone does: a real ID token
 * from the Auth emulator, a real HTTP POST to
 * http://127.0.0.1:5001/fin-e8358/us-central1/<name>, and the callable envelope
 * `{data:{...}}` -> `{result:{...}}`.
 *
 * `.run()` in the suite above bypasses auth, the express layer and the callable
 * envelope entirely, so it cannot catch a wrong response shape or a broken error
 * code. This can, and both client planners code against exactly these shapes.
 */
describe('callable round-trip over HTTP with a real ID token (emulator)', () => {
  const D = { uid: 'rt-driver', phone: '+15550001111', name: 'Mostafi' };
  const R = { uid: 'rt-receiver', phone: '+15550002222', name: 'Sara' };

  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });

  it('createPair -> acceptPair -> upsertSpot -> startTrip -> endTrip', async () => {
    await emu.wipe();
    const dTok: string = await emu.signIn(D.uid, D.phone);
    const rTok: string = await emu.signIn(R.uid, R.phone);

    expect(await emu.call('registerPushToken', dTok, {
      token: 'rt-driver-token-0000000001', platform: 'ios', displayName: D.name,
    })).toEqual({ ok: true });
    expect(await emu.call('registerPushToken', rTok, {
      token: 'rt-receiver-token-0000000001', platform: 'android', displayName: R.name,
    })).toEqual({ ok: true });

    const pair = await emu.call('createPair', dTok, {});
    expect(pair).toEqual({
      pairId: expect.any(String),
      inviteCode: expect.stringMatching(/^[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}$/),
    });

    // Contract error codes arrive as the callable's *message*.
    await expect(emu.call('acceptPair', rTok, { code: 'ZZZZZZ' }))
      .rejects.toMatchObject({ contractCode: 'bad-code' });
    await expect(emu.call('acceptPair', rTok, { code: 'nope' }))
      .rejects.toMatchObject({ contractCode: 'bad-code' });
    await expect(emu.call('acceptPair', dTok, { code: pair.inviteCode }))
      .rejects.toMatchObject({ contractCode: 'own-code' });

    expect(await emu.call('acceptPair', rTok, { code: pair.inviteCode })).toEqual({ pairId: pair.pairId });

    const spot = await emu.call('upsertSpot', rTok, {
      pairId: pair.pairId, name: 'Office', lat: 37.7749, lng: -122.4194, leadTimeMin: 3, radiusM: 100,
    });
    expect(spot).toEqual({ spotId: expect.any(String) });

    const trip = await emu.call('startTrip', dTok, {
      spotId: spot.spotId, lat: 37.7349, lng: -122.4694, etaSec: 677,
    });
    expect(trip).toEqual({
      tripId: expect.any(String),
      bands: { far: expect.any(Number), near: expect.any(Number), lead: expect.any(Number) },
      etaSeconds: 677,
      existing: false,
    });

    // memberNames is populated for BOTH members from the pair callables alone
    // (ADDENDUM M) — no client ever reads the other user's document.
    expect((await pairs().doc(pair.pairId).get()).data()!.memberNames)
      .toEqual({ [D.uid]: D.name, [R.uid]: R.name });

    expect(await emu.call('endTrip', dTok, { tripId: trip.tripId, reason: 'arrived' })).toEqual({ ok: true });
    expect((await trips().doc(trip.tripId).get()).data()!.state).toBe('arrived');
  });
});
