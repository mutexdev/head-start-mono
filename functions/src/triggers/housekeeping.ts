// functions/src/triggers/housekeeping.ts
//
// The lost / timeout / no-show sweep.
//
// The body lives in the plain exported `runHousekeeping(nowMs)` rather than
// inside the onSchedule closure for one concrete reason: firebase-tools converts
// an onSchedule function into a Pub/Sub topic trigger and, without the Pub/Sub
// emulator, logs
//   `functions[us-central1-housekeeping]: function ignored because the pubsub
//    emulator does not exist or is not running`
// — i.e. the entire ladder would be unvalidatable locally. `runHousekeeping`
// takes `nowMs` as an argument (never Date.now() internally) so the emulator-only
// `debugRunHousekeeping` endpoint in ./debug.ts can drive the 5-minute-lost and
// 3-hour-timeout thresholds instantly, with no waiting and no clock mocking.
// See CLIENT_CONTRACT_ADDENDUM.md, "Scheduled functions are not emulated".
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { trips, users } from '../io/firestore';
import { sendPush } from '../io/push';
import { msg } from '../messages';

export const LOST_MS = 5 * 60_000;
export const TIMEOUT_MS = 3 * 60 * 60_000;
export const NO_SHOW_MS = 15 * 60_000;

export interface HousekeepingCounts {
  timeout: number;
  lost: number;
  resumed: number;
  noShow: number;
}

async function nameOf(uid: string): Promise<string> {
  return (await users().doc(uid).get()).data()?.displayName ?? 'Your driver';
}

/**
 * One sweep. Pure with respect to the clock: everything is decided against the
 * passed-in `nowMs`. Returns how many trips each rule touched, which is what the
 * debug endpoint and the driver script assert on.
 */
export async function runHousekeeping(nowMs: number): Promise<HousekeepingCounts> {
  const counts: HousekeepingCounts = { timeout: 0, lost: 0, resumed: 0, noShow: 0 };
  const now = nowMs;

  const driving = await trips().where('state', '==', 'driving').get();
  for (const d of driving.docs) {
    const t = d.data();
    const started = t.startedAt ?? t.createdAt;
    if (now - started > TIMEOUT_MS) {
      await d.ref.update({ state: 'timeout', endedAt: now });
      counts.timeout += 1;
      // ADDENDUM D: trip-scoped pushes carry data.tripId.
      await Promise.all([
        sendPush(msg.timeout(t.driverUid), { tripId: d.id }),
        sendPush(msg.timeout(t.receiverUid), { tripId: d.id }),
      ]);
      continue;
    }
    const lastTs = t.lastPos?.ts ?? started;
    if (now - lastTs > LOST_MS && !t.lostNotified) {
      await d.ref.update({ state: 'lost', lostNotified: true });
      counts.lost += 1;
      const [dn, rn] = await Promise.all([nameOf(t.driverUid), nameOf(t.receiverUid)]);
      await Promise.all([
        sendPush(msg.lost(t.receiverUid, dn), { tripId: d.id }),
        sendPush(msg.lost(t.driverUid, rn), { tripId: d.id }),
      ]);
    }
  }

  // lost → driving again if positions resumed. onPositionWrite ignores any trip
  // that is not `driving`, so the resume has to happen here.
  const lost = await trips().where('state', '==', 'lost').get();
  for (const d of lost.docs) {
    const t = d.data();
    const started = t.startedAt ?? t.createdAt;
    if (now - started > TIMEOUT_MS) {
      await d.ref.update({ state: 'timeout', endedAt: now });
      counts.timeout += 1;
      continue;
    }
    const latest = await d.ref.collection('positions').orderBy('ts', 'desc').limit(1).get();
    const ts = latest.empty ? 0 : (latest.docs[0].data().ts as number);
    if (now - ts <= LOST_MS) {
      await d.ref.update({ state: 'driving', lostNotified: false });
      counts.resumed += 1;
    }
  }

  const armed = await trips().where('state', '==', 'armed').get();
  for (const d of armed.docs) {
    const t = d.data();
    if (!t.noShowNotified) {
      const deadline = (t.neededBy ?? t.createdAt) + NO_SHOW_MS;
      if (now > deadline) {
        await d.ref.update({ noShowNotified: true });
        counts.noShow += 1;
        await sendPush(msg.noShow(t.receiverUid, await nameOf(t.driverUid)), { tripId: d.id });
      }
    }
    if (now - t.createdAt > TIMEOUT_MS) {
      await d.ref.update({ state: 'timeout', endedAt: now });
      counts.timeout += 1;
    }
  }

  return counts;
}

/**
 * Production entry point. NOT emulated — see the file header; locally the same
 * body runs through debugRunHousekeeping.
 */
export const housekeeping = onSchedule('every 1 minutes', async () => {
  await runHousekeeping(Date.now());
});
