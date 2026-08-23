// functions/test/triggers/housekeeping.emulator.test.ts
//
// The lost / timeout / resume / no-show ladder. onSchedule is NOT emulated, so
// this drives the extracted pure `runHousekeeping(nowMs)` directly — the same
// body debugRunHousekeeping exposes over HTTP for the driver script.
//
// Runs only under: npm run test:emu.
process.env.GCLOUD_PROJECT = 'fin-e8358';
process.env.FUNCTIONS_EMULATOR = 'true';

import { db, trips, users, debugPushes } from '../../src/io/firestore';
import { runHousekeeping, LOST_MS, TIMEOUT_MS, NO_SHOW_MS } from '../../src/triggers/housekeeping';
import { TripDoc, initialAlerts } from '../../src/types';

const T0 = 1_700_000_000_000;
const DRIVER = 'd1';
const RECEIVER = 'r1';
const NOW = 1_800_000_000_000;

async function wipe() {
  await db.recursiveDelete(trips());
  for (const name of ['users', '_debugPushes']) {
    const snap = await db.collection(name).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
  await users().doc(DRIVER).set({ phone: '+15550001111', displayName: 'Mostafi', platform: 'ios', fcmTokens: [], createdAt: T0 });
  await users().doc(RECEIVER).set({ phone: '+15550002222', displayName: 'Sara', platform: 'android', fcmTokens: [], createdAt: T0 });
}

async function trip(over: Partial<TripDoc>): Promise<string> {
  const doc: TripDoc = {
    pairId: 'p1', driverUid: DRIVER, receiverUid: RECEIVER, spotId: 's1',
    spot: { lat: 37.42, lng: -122.08, radiusM: 100, name: 'School gate' },
    leadTimeMin: 3, state: 'driving', createdAt: NOW - 60_000, startedAt: NOW - 60_000,
    alerts: { ...initialAlerts(), started: true }, fuzzy: false, routingCalls: 0, phaseHint: 'far',
    ...over,
  };
  const ref = await trips().add(doc);
  return ref.id;
}

const kinds = async () => (await debugPushes().get()).docs.map((d) => d.data() as any);

describe('runHousekeeping (emulator)', () => {
  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });
  beforeEach(wipe);

  it('does nothing to a healthy driving trip', async () => {
    const id = await trip({ lastPos: { lat: 37.4, lng: -122.06, accuracyM: 8, speedMps: 14, ts: NOW - 10_000 } });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 0, lost: 0, resumed: 0, noShow: 0 });
    expect((await trips().doc(id).get()).data()!.state).toBe('driving');
    expect(await kinds()).toHaveLength(0);
  });

  it('marks a silent driving trip lost and pushes both members once', async () => {
    const id = await trip({
      startedAt: NOW - 20 * 60_000,
      lastPos: { lat: 37.4, lng: -122.06, accuracyM: 8, speedMps: 14, ts: NOW - LOST_MS - 1000 },
    });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 0, lost: 1, resumed: 0, noShow: 0 });

    const t = (await trips().doc(id).get()).data()!;
    expect(t.state).toBe('lost');
    expect(t.lostNotified).toBe(true);

    const lost = (await kinds()).filter((p) => p.kind === 'lost');
    expect(lost.map((p) => p.toUid).sort()).toEqual([DRIVER, RECEIVER]);
    for (const p of lost) expect(p.data).toEqual({ kind: 'lost', tripId: id });
    // The receiver is told about the DRIVER, and vice versa.
    expect(lost.find((p) => p.toUid === RECEIVER)!.body).toContain('Mostafi');
    expect(lost.find((p) => p.toUid === DRIVER)!.body).toContain('Sara');

    // A lost trip is not re-notified on the next sweep.
    expect(await runHousekeeping(NOW + 1000)).toEqual({ timeout: 0, lost: 0, resumed: 0, noShow: 0 });
  });

  it('resumes a lost trip once a fresh position lands', async () => {
    const id = await trip({ state: 'lost', lostNotified: true, startedAt: NOW - 20 * 60_000 });
    await trips().doc(id).collection('positions').add({ lat: 37.4, lng: -122.06, accuracyM: 8, speedMps: 14, ts: NOW - 5_000 });

    expect(await runHousekeeping(NOW)).toEqual({ timeout: 0, lost: 0, resumed: 1, noShow: 0 });
    const t = (await trips().doc(id).get()).data()!;
    expect(t.state).toBe('driving');
    expect(t.lostNotified).toBe(false);
  });

  it('leaves a lost trip lost when its newest position is still stale', async () => {
    const id = await trip({ state: 'lost', lostNotified: true, startedAt: NOW - 20 * 60_000 });
    await trips().doc(id).collection('positions').add({ lat: 37.4, lng: -122.06, accuracyM: 8, speedMps: 14, ts: NOW - LOST_MS - 60_000 });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 0, lost: 0, resumed: 0, noShow: 0 });
    expect((await trips().doc(id).get()).data()!.state).toBe('lost');
  });

  it('times out a driving trip after three hours and pushes both members', async () => {
    const id = await trip({ startedAt: NOW - TIMEOUT_MS - 1000, lastPos: { lat: 37.4, lng: -122.06, accuracyM: 8, speedMps: 14, ts: NOW - 1000 } });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 1, lost: 0, resumed: 0, noShow: 0 });

    const t = (await trips().doc(id).get()).data()!;
    expect(t.state).toBe('timeout');
    expect(t.endedAt).toBe(NOW);
    const timeouts = (await kinds()).filter((p) => p.kind === 'timeout');
    expect(timeouts.map((p) => p.toUid).sort()).toEqual([DRIVER, RECEIVER]);
    for (const p of timeouts) expect(p.data).toEqual({ kind: 'timeout', tripId: id });
  });

  it('times out a lost trip too', async () => {
    const id = await trip({ state: 'lost', lostNotified: true, startedAt: NOW - TIMEOUT_MS - 1000 });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 1, lost: 0, resumed: 0, noShow: 0 });
    expect((await trips().doc(id).get()).data()!.state).toBe('timeout');
  });

  it('no-shows an armed trip 15 minutes past neededBy, once', async () => {
    const id = await trip({ state: 'armed', createdAt: NOW - 60_000, neededBy: NOW - NO_SHOW_MS - 1000 });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 0, lost: 0, resumed: 0, noShow: 1 });

    const t = (await trips().doc(id).get()).data()!;
    expect(t.noShowNotified).toBe(true);
    expect(t.state).toBe('armed');
    const noShow = (await kinds()).filter((p) => p.kind === 'noShow');
    expect(noShow).toHaveLength(1);
    expect(noShow[0].toUid).toBe(RECEIVER);
    expect(noShow[0].data).toEqual({ kind: 'noShow', tripId: id });

    expect((await runHousekeeping(NOW + 1000)).noShow).toBe(0);
  });

  it('still times out an armed trip that was already no-show notified', async () => {
    // The plan doc `continue`d here, which left such a trip armed forever.
    const id = await trip({ state: 'armed', noShowNotified: true, createdAt: NOW - TIMEOUT_MS - 1000 });
    expect(await runHousekeeping(NOW)).toEqual({ timeout: 1, lost: 0, resumed: 0, noShow: 0 });
    expect((await trips().doc(id).get()).data()!.state).toBe('timeout');
  });
});
