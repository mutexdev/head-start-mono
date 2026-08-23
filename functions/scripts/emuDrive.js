#!/usr/bin/env node
/**
 * functions/scripts/emuDrive.js
 *
 * Drives the whole Headstart alert ladder against the Firebase Local Emulator
 * Suite and asserts every server decision, from the command line, in under a
 * minute — with no Blaze plan, no APNs key, no SMS and no Google Routes key.
 *
 *   npm run drive:happy                        # the ladder: started -> tenMin -> leadTime -> arrived
 *   npm run drive                              # every scenario
 *   npm run emu:exec -- "node scripts/emuDrive.js --scenario=slip --eta=server"
 *
 * Usage: node scripts/emuDrive.js --scenario=<name> [--eta=client|server]
 *
 *   --eta=client (default)  every position carries `etaSec` — the iOS MapKit path
 *                           (CLIENT_CONTRACT.md line 17 / ADDENDUM F). Zero
 *                           routing calls; bypasses the routing throttle entirely.
 *   --eta=server            positions omit `etaSec` — the Android path. The server
 *                           routes, throttled by ETA_POLL_SCALE=0.02 in
 *                           functions/.env.local (60/30/15 s -> 1.2/0.6/0.3 s).
 *
 * MUST be run inside a live emulator suite; `npm run emu:exec -- "<cmd>"` does that.
 *
 * ---------------------------------------------------------------------------
 * Three traps this script is deliberately shaped around
 * ---------------------------------------------------------------------------
 * 1. smoothEta silently swallows a first "interesting" ETA. startTrip stamps
 *    `eta.updatedAt = now`; a fix landing within 15 s with an ETA more than
 *    max(120 s, 25 %) away is HELD as `pendingEtaSec` and fires nothing — the
 *    trip just looks stuck. So the drive walks the ETA down gradually
 *    (~30 s per fix) instead of jumping. The `slip` scenario exploits the same
 *    machinery from the other side: two CONSECUTIVE fixes carrying the same
 *    raised ETA confirm the pending value and the slip alert fires.
 * 2. onPositionWrite drops any fix whose `ts` is <= the stored `lastPos.ts`,
 *    equal timestamps included. Every fix here uses a fresh `Date.now()` and is
 *    awaited to completion before the next one is written, so a burst can never
 *    race its predecessor's `alerts` object.
 * 3. Arrival needs a 20 s dwell and `speedMps < 2` inside `spot.radiusM`; the
 *    3-minute no-movement check is wall-clock too. The two arrival fixes are
 *    separated by a real 21 s sleep (the only wall-clock wait in the whole run);
 *    every other time threshold is crossed by back-dating a field with the admin
 *    SDK and POSTing debugRunHousekeeping with an injected `now`.
 */
'use strict';

const emu = require('./lib/emuClient');

// ---------------------------------------------------------------------------
// Fixtures
// ---------------------------------------------------------------------------

const DRIVER = {
  uid: 'emu-driver',
  phone: '+15550001111',
  name: 'Mostafi',
  platform: 'ios',
  token: 'emu-driver-token-0000000001', // registerPushToken requires >= 20 chars
};
const RECEIVER = {
  uid: 'emu-receiver',
  phone: '+15550002222',
  name: 'Sara',
  platform: 'android',
  token: 'emu-receiver-token-0000000001',
};

const SPOT = { name: 'Office', lat: 37.7749, lng: -122.4194, leadTimeMin: 3, radiusM: 100 };
/** ~6.3 km from SPOT, so the drive starts above the tenMin threshold (ETA ~678 s). */
const START = { lat: 37.7349, lng: -122.4694 };

const ROLE = { [DRIVER.uid]: 'driver', [RECEIVER.uid]: 'receiver' };
const roleOf = (uid) => ROLE[uid] || uid;

const DRIVE_STEPS = 20;
const DRIVE_SPACING_MS = 400;
const ARRIVAL_DWELL_SLEEP_MS = 21_000; // engine ARRIVE_DWELL_MS is 20 s

// ---------------------------------------------------------------------------
// Assertions + reporting
// ---------------------------------------------------------------------------

class Report {
  constructor(name, mode) {
    this.name = name;
    this.mode = mode;
    this.t0 = Date.now();
    this.results = [];
  }

  mark() { this.t0 = Date.now(); }

  ok(label, cond, detail) {
    this.results.push({ label, pass: !!cond, detail: cond ? '' : (detail || '') });
    return !!cond;
  }

  eq(label, actual, expected) {
    const a = JSON.stringify(actual);
    const e = JSON.stringify(expected);
    return this.ok(label, a === e, `expected ${e}, got ${a}`);
  }

  get failed() { return this.results.filter((r) => !r.pass).length; }
}

function printPushTable(rep, rows) {
  const head = ['t+', 'kind', 'to', 'urgent', 'channel', 'body'];
  const body = rows.map((r) => [
    `${((r.sentAt - rep.t0) / 1000).toFixed(1)}s`,
    String(r.kind),
    roleOf(r.toUid),
    r.urgent ? 'URGENT' : '-',
    String(r.androidChannelId),
    String(r.body).slice(0, 44),
  ]);
  const widths = head.map((h, i) => Math.max(h.length, ...body.map((b) => b[i].length), 1));
  const line = (cells) => '  ' + cells.map((c, i) => c.padEnd(widths[i])).join('  ').trimEnd();

  console.log(`\n  _debugPushes for "${rep.name}" (${rows.length} row${rows.length === 1 ? '' : 's'}, ordered by sentAt)`);
  console.log(line(head));
  console.log('  ' + widths.map((w) => '-'.repeat(w)).join('  '));
  if (rows.length === 0) console.log('  (none)');
  for (const b of body) console.log(line(b));
}

function printResults(rep) {
  console.log('');
  for (const r of rep.results) {
    console.log(`  ${r.pass ? 'PASS' : 'FAIL'}  ${r.label}${r.pass ? '' : `\n          ${r.detail}`}`);
  }
  const n = rep.results.length;
  const bad = rep.failed;
  console.log(`\n  ${bad === 0 ? 'PASS' : 'FAIL'}  scenario "${rep.name}" (eta=${rep.mode}) — ${n - bad}/${n} assertions passed`);
}

// ---------------------------------------------------------------------------
// Shared setup
// ---------------------------------------------------------------------------

/**
 * wipe -> sign both members in -> registerPushToken -> createPair -> acceptPair
 * -> upsertSpot. Every scenario starts from here, so `all` gets its wipe between
 * scenarios for free.
 */
async function setup(rep) {
  await emu.wipe();
  const driverToken = await emu.signIn(DRIVER.uid, DRIVER.phone);
  const receiverToken = await emu.signIn(RECEIVER.uid, RECEIVER.phone);

  const regD = await emu.call('registerPushToken', driverToken, {
    token: DRIVER.token, platform: DRIVER.platform, displayName: DRIVER.name,
  });
  const regR = await emu.call('registerPushToken', receiverToken, {
    token: RECEIVER.token, platform: RECEIVER.platform, displayName: RECEIVER.name,
  });

  const pair = await emu.call('createPair', driverToken, {});
  const accepted = await emu.call('acceptPair', receiverToken, { code: pair.inviteCode });
  const spot = await emu.call('upsertSpot', receiverToken, Object.assign({ pairId: pair.pairId }, SPOT));

  if (rep) {
    rep.eq('registerPushToken(driver) -> {ok:true}', regD, { ok: true });
    rep.eq('registerPushToken(receiver) -> {ok:true}', regR, { ok: true });
    rep.ok('createPair -> {pairId, inviteCode(6)}',
      typeof pair.pairId === 'string' && typeof pair.inviteCode === 'string' && pair.inviteCode.length === 6,
      JSON.stringify(pair));
    rep.eq('acceptPair -> {pairId} (same pair)', accepted, { pairId: pair.pairId });
    rep.ok('upsertSpot -> {spotId}', typeof spot.spotId === 'string', JSON.stringify(spot));
  }

  return {
    driverToken,
    receiverToken,
    pairId: pair.pairId,
    inviteCode: pair.inviteCode,
    spotId: spot.spotId,
  };
}

/** startTrip from START. In client mode the caller's own ETA is supplied (iOS). */
async function startTrip(ctx, rep, mode) {
  const data = { spotId: ctx.spotId, lat: START.lat, lng: START.lng };
  if (mode === 'client') data.etaSec = emu.stubEtaSec(emu.haversineMeters(START, SPOT));
  const res = await emu.call('startTrip', ctx.driverToken, data);
  if (rep) {
    rep.ok('startTrip -> {tripId, bands{far,near,lead}, etaSeconds, existing:false}',
      typeof res.tripId === 'string' && res.existing === false &&
      typeof res.etaSeconds === 'number' && res.bands &&
      typeof res.bands.far === 'number' && typeof res.bands.near === 'number' && typeof res.bands.lead === 'number',
      JSON.stringify(res));
  }
  return res;
}

/**
 * Replays the drive. Each fix is awaited to completion, then padded out to
 * DRIVE_SPACING_MS of wall clock so the run looks like a real drive.
 * `stopKind` breaks out as soon as that push kind has been recorded.
 */
async function drive(tripId, mode, stopKind) {
  const pts = emu.lerpRoute(START, SPOT, DRIVE_STEPS);
  for (let i = 0; i < pts.length; i++) {
    const began = Date.now();
    const p = pts[i];
    const fix = { lat: p.lat, lng: p.lng, accuracyM: 8, speedMps: 12, ts: Date.now() };
    if (mode === 'client') fix.etaSec = emu.stubEtaSec(emu.haversineMeters(p, SPOT));

    const res = await emu.writeAndAwait(tripId, fix);
    if (!res.processed) return { index: i, at: p, stopped: res.reason };

    if (stopKind) {
      const rows = await emu.pushes();
      if (rows.some((r) => r.kind === stopKind)) return { index: i, at: p, stopped: stopKind };
    }
    const spent = Date.now() - began;
    if (spent < DRIVE_SPACING_MS) await emu.sleep(DRIVE_SPACING_MS - spent);
  }
  return { index: pts.length - 1, at: pts[pts.length - 1], stopped: null };
}

/** Two fixes inside spot.radiusM at walking speed, 21 s apart -> the engine's arrival dwell. */
async function arrive(tripId, mode) {
  const at = { lat: SPOT.lat, lng: SPOT.lng, accuracyM: 8, speedMps: 0.5 };
  const first = Object.assign({ ts: Date.now() }, at);
  if (mode === 'client') first.etaSec = 1;
  await emu.writeAndAwait(tripId, first);
  await emu.sleep(ARRIVAL_DWELL_SLEEP_MS);
  const second = Object.assign({ ts: Date.now() }, at);
  if (mode === 'client') second.etaSec = 1;
  await emu.writeAndAwait(tripId, second);
}

const kindsOf = (rows) => rows.map((r) => r.kind);

// ---------------------------------------------------------------------------
// Scenarios
// ---------------------------------------------------------------------------

/**
 * The headline: started -> tenMin -> leadTime -> arrived, all addressed to the
 * receiver, leadTime the only urgent one (ADDENDUM C).
 */
async function scHappy(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  await drive(trip.tripId, mode);
  await arrive(trip.tripId, mode);

  const rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'arrived'), 15_000);
  printPushTable(rep, rows);

  rep.eq('push ladder is exactly [started, tenMin, leadTime, arrived]',
    kindsOf(rows), ['started', 'tenMin', 'leadTime', 'arrived']);
  rep.eq('every push is addressed to the receiver',
    rows.map((r) => roleOf(r.toUid)), rows.map(() => 'receiver'));

  const lead = rows.find((r) => r.kind === 'leadTime');
  rep.ok('leadTime.urgent === true', lead && lead.urgent === true, JSON.stringify(lead));
  rep.ok("leadTime.androidChannelId === 'sync_urgent'",
    lead && lead.androidChannelId === 'sync_urgent', JSON.stringify(lead && lead.androidChannelId));
  rep.ok("leadTime.apnsInterruptionLevel === 'time-sensitive'",
    lead && lead.apnsInterruptionLevel === 'time-sensitive', JSON.stringify(lead && lead.apnsInterruptionLevel));
  rep.eq("every other push is sync_updates / active",
    rows.filter((r) => r.kind !== 'leadTime').map((r) => `${r.androidChannelId}/${r.apnsInterruptionLevel}/${r.urgent}`),
    rows.filter((r) => r.kind !== 'leadTime').map(() => 'sync_updates/active/false'));
  rep.eq('every push carries data.tripId',
    rows.map((r) => r.data && r.data.tripId), rows.map(() => trip.tripId));

  const t = await emu.getTrip(trip.tripId);
  rep.eq('trip.state === arrived', t && t.state, 'arrived');
  rep.eq('trip.alerts {started,tenMin,leadTime,arrived} all true',
    t && { started: t.alerts.started, tenMin: t.alerts.tenMin, leadTime: t.alerts.leadTime, arrived: t.alerts.arrived },
    { started: true, tenMin: true, leadTime: true, arrived: true });
  rep.eq('trip.alerts.slipCount === 0 (ETA only ever improved)', t && t.alerts.slipCount, 0);

  // The two routing paths differ in exactly one observable way; prove which one ran.
  if (mode === 'client') {
    rep.eq('client ETA path made ZERO routing calls (ADDENDUM F)', t && t.routingCalls, 0);
    rep.ok('client ETA path stored no routePolyline', t && t.routePolyline === undefined, String(t && t.routePolyline));
  } else {
    rep.ok('server ETA path made routing calls', t && t.routingCalls > 1, `routingCalls=${t && t.routingCalls}`);
    rep.ok('server ETA path stored a routePolyline', t && typeof t.routePolyline === 'string', String(t && t.routePolyline));
  }
}

/** Two consecutive fixes with the SAME raised ETA confirm the pending value -> slip. */
async function scSlip(rep) {
  const ctx = await setup(rep);
  rep.mark();
  // Forced client mode: the scenario is *about* the engine's ETA smoothing, and a
  // client-supplied etaSec is the only way to inject an exact value.
  const trip = await startTrip(ctx, rep, 'client');

  const stop = await drive(trip.tripId, 'client', 'tenMin');
  rep.eq('drive reached tenMin before the slip injection', stop.stopped, 'tenMin');

  const before = await emu.getTrip(trip.tripId);
  const raised = before.eta.seconds + 240;
  const at = stop.at;

  // 1st fix: smoothEta HOLDS the jump as pendingEtaSec and fires nothing.
  await emu.writeAndAwait(trip.tripId, { lat: at.lat, lng: at.lng, accuracyM: 8, speedMps: 3, ts: Date.now(), etaSec: raised });
  const held = await emu.getTrip(trip.tripId);
  rep.eq('1st raised fix is HELD (eta unchanged)', held.eta.seconds, before.eta.seconds);
  rep.eq('1st raised fix stored pendingEtaSec', held.pendingEtaSec, raised);

  // 2nd identical fix confirms it.
  await emu.writeAndAwait(trip.tripId, { lat: at.lat, lng: at.lng, accuracyM: 8, speedMps: 3, ts: Date.now(), etaSec: raised });

  const rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'slip'), 10_000);
  printPushTable(rep, rows);

  const slip = rows.filter((r) => r.kind === 'slip');
  rep.eq('exactly one slip push', slip.length, 1);
  rep.eq('slip is addressed to the receiver', slip[0] && roleOf(slip[0].toUid), 'receiver');
  rep.eq('slip is not urgent (ADDENDUM C)', slip[0] && slip[0].androidChannelId, 'sync_updates');

  const after = await emu.getTrip(trip.tripId);
  rep.eq('2nd raised fix ACCEPTED (eta === raised)', after.eta.seconds, raised);
  rep.ok('trip.alerts.slipCount >= 1', after.alerts.slipCount >= 1, `slipCount=${after.alerts.slipCount}`);
  rep.ok('pendingEtaSec cleared', after.pendingEtaSec === undefined, String(after.pendingEtaSec));
}

/** No movement 3 min after startTrip -> didYouLeave, addressed to the DRIVER. */
async function scNoMove(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  // Wall clock, so back-date rather than wait three minutes.
  await emu.tripRef(trip.tripId).update({ startedAt: Date.now() - 4 * 60_000 });

  const near = { lat: START.lat + 0.0004, lng: START.lng }; // ~45 m from startPos, < 150 m
  const fix = { lat: near.lat, lng: near.lng, accuracyM: 8, speedMps: 0.4, ts: Date.now() };
  if (mode === 'client') fix.etaSec = emu.stubEtaSec(emu.haversineMeters(near, SPOT));
  await emu.writeAndAwait(trip.tripId, fix);

  const rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'didYouLeave'), 10_000);
  printPushTable(rep, rows);

  const dyl = rows.filter((r) => r.kind === 'didYouLeave');
  rep.eq('exactly one didYouLeave push', dyl.length, 1);
  rep.eq('didYouLeave is addressed to the DRIVER', dyl[0] && roleOf(dyl[0].toUid), 'driver');
  rep.eq('didYouLeave carries data.tripId', dyl[0] && dyl[0].data.tripId, trip.tripId);

  const t = await emu.getTrip(trip.tripId);
  rep.eq('trip.alerts.didYouLeave === true', t.alerts.didYouLeave, true);
}

/** No fix for 5 minutes -> state 'lost' + one push per member. */
async function scLost(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  const p = emu.lerpRoute(START, SPOT, DRIVE_STEPS)[0];
  const fix = { lat: p.lat, lng: p.lng, accuracyM: 8, speedMps: 12, ts: Date.now() };
  if (mode === 'client') fix.etaSec = emu.stubEtaSec(emu.haversineMeters(p, SPOT));
  const first = await emu.writeAndAwait(trip.tripId, fix);
  rep.ok('first fix was processed by onPositionWrite', first.processed, JSON.stringify(first.reason));

  // Both have to be back-dated. runHousekeeping's resume rule re-reads
  // `positions` ordered by ts for every lost trip and flips it straight back to
  // `driving` if the newest fix is younger than LOST_MS — so back-dating only
  // trip.lastPos.ts marks the trip lost and then un-marks it inside the SAME
  // sweep. A real five-minute blackout has no fresh positions either.
  const backdated = Date.now() - 6 * 60_000;
  await emu.tripRef(trip.tripId).update({ 'lastPos.ts': backdated });
  const posDocs = await emu.tripRef(trip.tripId).collection('positions').get();
  await Promise.all(posDocs.docs.map((d) => d.ref.update({ ts: backdated })));

  const counts = await emu.runHousekeeping(Date.now());
  rep.eq('debugRunHousekeeping reported lost: 1', counts.lost, 1);
  rep.eq('the same sweep did NOT resume it (no fresh positions)', counts.resumed, 0);

  const rows = await emu.waitForPushes((r) => r.filter((p2) => p2.kind === 'lost').length >= 2, 10_000);
  printPushTable(rep, rows);

  const lost = rows.filter((r) => r.kind === 'lost');
  rep.eq('two lost pushes, one per member', lost.length, 2);
  rep.eq('lost pushes reach both members',
    lost.map((r) => roleOf(r.toUid)).sort(), ['driver', 'receiver']);

  const t = await emu.getTrip(trip.tripId);
  rep.eq("trip.state === 'lost'", t.state, 'lost');
  rep.eq('trip.lostNotified === true (one-shot)', t.lostNotified, true);

  const again = await emu.runHousekeeping(Date.now());
  rep.eq('a second sweep is a no-op (lostNotified is one-shot)', again.lost, 0);

  // Positions resume -> lost flips back to driving. onPositionWrite ignores any
  // trip that is not `driving`, so only the sweep can do this.
  const resume = emu.lerpRoute(START, SPOT, DRIVE_STEPS)[1];
  await emu.writePosition(trip.tripId, {
    lat: resume.lat, lng: resume.lng, accuracyM: 8, speedMps: 12, ts: Date.now(),
  });
  const third = await emu.runHousekeeping(Date.now());
  rep.eq('a fresh fix resumes the trip', third.resumed, 1);
  const resumed = await emu.getTrip(trip.tripId);
  rep.eq("trip.state is back to 'driving'", resumed.state, 'driving');
  rep.eq('lostNotified was cleared so a later blackout re-alerts', resumed.lostNotified, false);
}

/** 3 hours since startedAt -> state 'timeout' + one push per member. */
async function scTimeout(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  await emu.tripRef(trip.tripId).update({ startedAt: Date.now() - 4 * 3_600_000 });
  const counts = await emu.runHousekeeping(Date.now());
  rep.eq('debugRunHousekeeping reported timeout: 1', counts.timeout, 1);

  const rows = await emu.waitForPushes((r) => r.filter((p) => p.kind === 'timeout').length >= 2, 10_000);
  printPushTable(rep, rows);

  const to = rows.filter((r) => r.kind === 'timeout');
  rep.eq('two timeout pushes, one per member', to.length, 2);
  rep.eq('timeout pushes reach both members', to.map((r) => roleOf(r.toUid)).sort(), ['driver', 'receiver']);

  const t = await emu.getTrip(trip.tripId);
  rep.eq("trip.state === 'timeout'", t.state, 'timeout');
  rep.ok('trip.endedAt was stamped', typeof t.endedAt === 'number', String(t.endedAt));
}

/** Receiver arms -> 'armed' to the driver; 15 min with no start -> 'noShow' to the receiver. */
async function scArm(rep) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await emu.call('armTrip', ctx.receiverToken, { spotId: ctx.spotId });
  rep.ok('armTrip -> {tripId}', typeof trip.tripId === 'string', JSON.stringify(trip));

  let rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'armed'), 10_000);
  const armed = rows.filter((r) => r.kind === 'armed');
  rep.eq('exactly one armed push', armed.length, 1);
  rep.eq('armed is addressed to the DRIVER', armed[0] && roleOf(armed[0].toUid), 'driver');

  await emu.tripRef(trip.tripId).update({ createdAt: Date.now() - 16 * 60_000 });
  const counts = await emu.runHousekeeping(Date.now());
  rep.eq('debugRunHousekeeping reported noShow: 1', counts.noShow, 1);

  rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'noShow'), 10_000);
  printPushTable(rep, rows);

  const noShow = rows.filter((r) => r.kind === 'noShow');
  rep.eq('exactly one noShow push', noShow.length, 1);
  rep.eq('noShow is addressed to the RECEIVER', noShow[0] && roleOf(noShow[0].toUid), 'receiver');

  const t = await emu.getTrip(trip.tripId);
  rep.eq("trip is still 'armed'", t.state, 'armed');
  rep.eq('trip.noShowNotified === true (one-shot)', t.noShowNotified, true);
}

/** endTrip('cancelled') by the RECEIVER pushes the DRIVER, never the caller (ADDENDUM G). */
async function scCancel(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  const res = await emu.call('endTrip', ctx.receiverToken, { tripId: trip.tripId, reason: 'cancelled' });
  rep.eq('endTrip -> {ok:true}', res, { ok: true });

  const rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'cancelled'), 10_000);
  printPushTable(rep, rows);

  const cancelled = rows.filter((r) => r.kind === 'cancelled');
  rep.eq('exactly one cancelled push', cancelled.length, 1);
  rep.eq('cancelled is addressed to the DRIVER, not the caller', cancelled[0] && roleOf(cancelled[0].toUid), 'driver');
  rep.eq('cancelled carries data.tripId', cancelled[0] && cancelled[0].data.tripId, trip.tripId);

  const t = await emu.getTrip(trip.tripId);
  rep.eq("trip.state === 'cancelled'", t.state, 'cancelled');
}

/** sendReply (receiver -> driver), setRunningLate (driver -> receiver, driver-only). */
async function scReply(rep, mode) {
  const ctx = await setup(rep);
  rep.mark();
  const trip = await startTrip(ctx, rep, mode);

  const r1 = await emu.call('sendReply', ctx.receiverToken, { tripId: trip.tripId, kind: 'fiveMore' });
  rep.eq('sendReply -> {ok:true}', r1, { ok: true });

  let rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'reply'), 10_000);
  const reply = rows.filter((r) => r.kind === 'reply');
  rep.eq('exactly one reply push', reply.length, 1);
  rep.eq('reply is addressed to the DRIVER', reply[0] && roleOf(reply[0].toUid), 'driver');
  rep.eq('reply body is the canned fiveMore text', reply[0] && reply[0].body, '5 more minutes please');

  const r2 = await emu.call('setRunningLate', ctx.driverToken, { tripId: trip.tripId, extraMin: 7 });
  rep.eq('setRunningLate -> {ok:true}', r2, { ok: true });

  rows = await emu.waitForPushes((r) => r.some((p) => p.kind === 'runningLate'), 10_000);
  printPushTable(rep, rows);

  const late = rows.filter((r) => r.kind === 'runningLate');
  rep.eq('exactly one runningLate push', late.length, 1);
  rep.eq('runningLate is addressed to the RECEIVER', late[0] && roleOf(late[0].toUid), 'receiver');
  rep.eq('runningLate body carries extraMin', late[0] && late[0].body, 'About 7 more min');

  // Contract error codes come back as the callable's *message*.
  let code = '(no error thrown)';
  try {
    await emu.call('setRunningLate', ctx.receiverToken, { tripId: trip.tripId, extraMin: 7 });
  } catch (e) {
    code = e.contractCode;
  }
  rep.eq("setRunningLate by the receiver fails with 'driver-only'", code, 'driver-only');

  let badReply = '(no error thrown)';
  try {
    await emu.call('sendReply', ctx.receiverToken, { tripId: trip.tripId, kind: 'custom', text: '   ' });
  } catch (e) {
    badReply = e.contractCode;
  }
  rep.eq("sendReply with empty custom text fails with 'bad-reply' (ADDENDUM O)", badReply, 'bad-reply');
}

// ---------------------------------------------------------------------------
// Runner
// ---------------------------------------------------------------------------

const SCENARIOS = {
  happy: { run: (rep, mode) => scHappy(rep, mode), desc: 'started -> tenMin -> leadTime -> arrived' },
  happyServer: { run: (rep) => scHappy(rep, 'server'), forceMode: 'server', desc: 'the same ladder on the SERVER routing path' },
  slip: { run: (rep) => scSlip(rep), forceMode: 'client', desc: 'ETA jumps +240 s, confirmed -> slip' },
  noMove: { run: (rep, mode) => scNoMove(rep, mode), desc: 'no movement 3 min after start -> didYouLeave' },
  lost: { run: (rep, mode) => scLost(rep, mode), desc: 'no fix for 5 min -> lost' },
  timeout: { run: (rep, mode) => scTimeout(rep, mode), desc: '3 h since start -> timeout' },
  arm: { run: (rep) => scArm(rep), desc: 'armTrip -> armed, then 15 min -> noShow' },
  cancel: { run: (rep, mode) => scCancel(rep, mode), desc: 'receiver cancels -> cancelled to the DRIVER' },
  reply: { run: (rep, mode) => scReply(rep, mode), desc: 'sendReply / setRunningLate / driver-only' },
};

const ORDER = ['happy', 'happyServer', 'slip', 'noMove', 'lost', 'timeout', 'arm', 'cancel', 'reply'];

function parseArgs(argv) {
  const out = { scenario: 'happy', eta: 'client' };
  for (const a of argv) {
    const m = /^--([a-zA-Z]+)=(.*)$/.exec(a);
    if (!m) continue;
    if (m[1] === 'scenario') out.scenario = m[2];
    else if (m[1] === 'eta') out.eta = m[2];
  }
  return out;
}

function printHeader(args, names) {
  console.log('');
  console.log('  Headstart emulator drive');
  console.log(`  project ${emu.PROJECT_ID}   region ${emu.REGION}   eta=${args.eta}`);
  console.log('');
  console.log(`  callables            ${emu.URLS.callableBase}/<name>`);
  console.log(`  auth emulator        ${emu.URLS.authEmulator}`);
  console.log(`  firestore emulator   ${emu.URLS.firestoreEmulator}`);
  console.log(`  functions emulator   ${emu.URLS.functionsEmulator}`);
  console.log(`  emulator UI          ${emu.URLS.emulatorUi}`);
  console.log(`  housekeeping         POST ${emu.URLS.debugRunHousekeeping}?now=<epochMs>`);
  console.log(`  OTP codes            GET  ${emu.URLS.verificationCodes}`);
  console.log('');
  console.log(`  identities           ${DRIVER.phone} ${DRIVER.name} (driver, ${DRIVER.uid})`);
  console.log(`                       ${RECEIVER.phone} ${RECEIVER.name} (receiver, ${RECEIVER.uid})`);
  console.log(`  spot                 ${SPOT.name} ${SPOT.lat},${SPOT.lng} lead ${SPOT.leadTimeMin} min radius ${SPOT.radiusM} m`);
  console.log(`  scenarios            ${names.join(', ')}`);
}

async function preflight() {
  const res = await fetch(emu.URLS.debugPing).catch((e) => {
    throw new Error(
      `cannot reach the Functions emulator at ${emu.URLS.functionsEmulator} (${e.message}).\n` +
      '  Run this inside a live suite:  npm run emu:exec -- "node scripts/emuDrive.js --scenario=happy"',
    );
  });
  if (!res.ok) throw new Error(`debugPing -> ${res.status}; the debug endpoints are disabled (need FUNCTIONS_EMULATOR=true or ENABLE_DEBUG_ENDPOINTS=1)`);
  return res.json();
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  const names = args.scenario === 'all' ? ORDER.slice() : [args.scenario];

  for (const n of names) {
    if (!SCENARIOS[n]) {
      console.error(`unknown scenario "${n}". Known: ${ORDER.join(', ')}, all`);
      process.exit(2);
    }
  }
  if (args.eta !== 'client' && args.eta !== 'server') {
    console.error(`--eta must be client or server, got "${args.eta}"`);
    process.exit(2);
  }

  emu.init();
  printHeader(args, names);
  const ping = await preflight();
  console.log(`  debugPing            ${JSON.stringify(ping)}`);

  const runStart = Date.now();
  const summary = [];
  let failures = 0;

  for (const name of names) {
    const sc = SCENARIOS[name];
    const mode = sc.forceMode || args.eta;
    const rep = new Report(name, mode);
    console.log(`\n${'='.repeat(78)}\n  scenario ${name} — ${sc.desc}${sc.forceMode ? `  [eta forced to ${sc.forceMode}]` : ''}\n${'='.repeat(78)}`);
    const began = Date.now();
    try {
      await sc.run(rep, mode);
    } catch (e) {
      rep.ok(`scenario threw: ${e && e.message ? e.message : e}`, false, e && e.stack ? e.stack : '');
    }
    printResults(rep);
    const secs = ((Date.now() - began) / 1000).toFixed(1);
    summary.push({ name, mode, total: rep.results.length, failed: rep.failed, secs });
    failures += rep.failed;
  }

  console.log(`\n${'='.repeat(78)}`);
  for (const s of summary) {
    console.log(`  ${s.failed === 0 ? 'PASS' : 'FAIL'}  ${s.name.padEnd(12)} eta=${s.mode.padEnd(7)} ${String(s.total - s.failed)}/${s.total} assertions  ${s.secs}s`);
  }
  console.log(`${'='.repeat(78)}`);
  console.log(`  ${failures === 0 ? 'ALL SCENARIOS PASSED' : `${failures} ASSERTION(S) FAILED`} in ${((Date.now() - runStart) / 1000).toFixed(1)}s\n`);

  process.exit(failures === 0 ? 0 : 1);
}

main().catch((e) => {
  console.error(`\n  FATAL  ${e && e.stack ? e.stack : e}\n`);
  process.exit(1);
});
