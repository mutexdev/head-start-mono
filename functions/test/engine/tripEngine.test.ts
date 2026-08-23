// functions/test/engine/tripEngine.test.ts
import { step, EngineInput, EnginePatch } from '../../src/engine/tripEngine';
import { TripDoc, Position, initialAlerts } from '../../src/types';

const T0 = 1_700_000_000_000;
const SPOT = { lat: 0, lng: 0, radiusM: 100, name: 'Office' };

function trip(over: Partial<TripDoc> = {}): TripDoc {
  return {
    pairId: 'p', driverUid: 'd', receiverUid: 'r', spotId: 's', spot: SPOT, leadTimeMin: 3,
    state: 'driving', createdAt: T0, startedAt: T0, startPos: { lat: 0.1, lng: 0 },
    eta: { seconds: 1200, updatedAt: T0, approximate: false },
    routeDistanceM: 11_000, bands: { far: 6600, near: 3850, lead: 2750 },
    lastPos: { lat: 0.1, lng: 0, accuracyM: 10, speedMps: 0, ts: T0 },
    alerts: initialAlerts(), fuzzy: false, routingCalls: 1, phaseHint: 'far', lastRoutingCallAt: T0,
    ...over,
  };
}
const pos = (lat: number, ts: number, speed = 12, acc = 10): Position => ({ lat, lng: 0, accuracyM: acc, speedMps: speed, ts });
const run = (t: TripDoc, p: Position, freshEta?: number, now = p.ts) =>
  step({ trip: t, position: p, nowMs: now, freshEtaSec: freshEta, driverName: 'Mostafi' } as EngineInput);

describe('step: polling decision', () => {
  it('wants ETA when interval elapsed', () => {
    const r = run(trip(), pos(0.09, T0 + 60_000));
    expect(r.wantsEta).toBe(true);
  });
  it('does not want ETA before interval', () => {
    expect(run(trip(), pos(0.09, T0 + 30_000)).wantsEta).toBe(false);
  });
  it('sets phaseHint near inside the near band and wants ETA immediately', () => {
    const r = run(trip(), pos(0.03, T0 + 5_000)); // ~3.3km from spot < near 3850
    expect(r.patch.phaseHint).toBe('near');
    expect(r.wantsEta).toBe(true);
  });
});

describe('step: alert ladder', () => {
  it('fires tenMin once when eta <= 600', () => {
    const r = run(trip(), pos(0.05, T0 + 60_000), 590);
    expect(r.pushes.map(p => p.data.kind)).toEqual(['tenMin']);
    expect(r.patch.alerts?.tenMin).toBe(true);
    const again = run({ ...trip(), alerts: { ...initialAlerts(), tenMin: true } }, pos(0.04, T0 + 120_000), 500);
    expect(again.pushes).toHaveLength(0);
  });
  it('fires leadTime when eta <= lead minutes, and tenMin too if skipped', () => {
    const r = run(trip(), pos(0.02, T0 + 60_000), 170);
    expect(r.pushes.map(p => p.data.kind)).toEqual(['tenMin', 'leadTime']);
    expect(r.pushes[1].urgent).toBe(true);
  });
  it('fires slip when eta rises >=120s after tenMin', () => {
    const t = trip({ alerts: { ...initialAlerts(), tenMin: true, lastSlipEtaSec: 500 }, eta: { seconds: 500, updatedAt: T0, approximate: false } });
    const r = run(t, pos(0.04, T0 + 60_000), 640);
    expect(r.pushes.map(p => p.data.kind)).toEqual(['slip']);
    expect(r.patch.alerts?.slipCount).toBe(1);
    expect(r.patch.alerts?.lastSlipEtaSec).toBe(640);
  });
  it('re-arms leadTime when eta goes back above lead+2 min', () => {
    const t = trip({ alerts: { ...initialAlerts(), tenMin: true, leadTime: true, lastSlipEtaSec: 170 }, eta: { seconds: 170, updatedAt: T0, approximate: false } });
    const r = run(t, pos(0.02, T0 + 60_000), 420);
    expect(r.patch.alerts?.leadTime).toBe(false);
    expect(r.pushes.map(p => p.data.kind)).toEqual(['slip']);
  });
  it('applies ETA smoothing (rejects a sudden jump)', () => {
    const r = run(trip(), pos(0.09, T0 + 10_000), 1700, T0 + 10_000);
    expect(r.patch.eta?.seconds).toBe(1200);
    expect(r.patch.pendingEtaSec).toBe(1700);
  });
});

describe('step: arrival', () => {
  it('starts dwell when inside radius and slow', () => {
    const r = run(trip({ phaseHint: 'near' }), pos(0.0005, T0 + 600_000, 1));
    expect(r.patch.alerts?.arrivalDwellSince).toBe(T0 + 600_000);
    expect(r.pushes).toHaveLength(0);
  });
  it('arrives after 20s dwell', () => {
    const t = trip({ phaseHint: 'near', alerts: { ...initialAlerts(), tenMin: true, leadTime: true, arrivalDwellSince: T0 + 600_000 } });
    const r = run(t, pos(0.0005, T0 + 621_000, 0.5));
    expect(r.patch.state).toBe('arrived');
    expect(r.pushes.map(p => p.data.kind)).toEqual(['arrived']);
    expect(r.patch.endedAt).toBe(T0 + 621_000);
  });
  it('clears dwell if the driver speeds up again', () => {
    const t = trip({ phaseHint: 'near', alerts: { ...initialAlerts(), arrivalDwellSince: T0 + 600_000 } });
    const r = run(t, pos(0.0005, T0 + 610_000, 8));
    expect(r.patch.alerts?.arrivalDwellSince).toBeUndefined();
  });
});

describe('step: movement verification', () => {
  it('asks the driver once if no movement >=150m after 3 min', () => {
    const r = run(trip(), pos(0.1001, T0 + 181_000, 0));
    expect(r.pushes.map(p => p.data.kind)).toEqual(['didYouLeave']);
    expect(r.pushes[0].toUid).toBe('d');
    expect(r.patch.alerts?.didYouLeave).toBe(true);
  });
  it('does not ask if the driver moved', () => {
    const r = run(trip(), pos(0.09, T0 + 181_000, 10));
    expect(r.pushes.map(p => p.data.kind)).not.toContain('didYouLeave');
  });
});

describe('step: low accuracy and receiverView', () => {
  it('ignores fixes with accuracy > 100m except for lastPos timestamp', () => {
    const r = run(trip(), pos(0.05, T0 + 60_000, 12, 500), 590);
    expect(r.pushes).toHaveLength(0);
    expect(r.patch.lastPos?.ts).toBe(T0 + 60_000);
  });
  it('hides lastPos in receiverView when fuzzy and eta > 5 min', () => {
    const r = run(trip({ fuzzy: true }), pos(0.05, T0 + 60_000), 700);
    expect(r.patch.receiverView?.lastPos).toBeUndefined();
    expect(r.patch.receiverView?.etaSeconds).toBe(700);
  });
  it('shows lastPos when fuzzy and eta <= 5 min', () => {
    const r = run(trip({ fuzzy: true, alerts: { ...initialAlerts(), tenMin: true } }), pos(0.02, T0 + 60_000), 290);
    expect(r.patch.receiverView?.lastPos).toEqual({ lat: 0.02, lng: 0 });
  });
});

// ---------------------------------------------------------------------------
// Additions required by batch be3 (beyond the plan doc's original 16 tests).
// ---------------------------------------------------------------------------

describe('step: etaPollScale (pure throttle seam)', () => {
  it('defaults to scale 1 — 30s into a 60s interval it does not want an ETA', () => {
    const r = step({
      trip: trip(), position: pos(0.09, T0 + 30_000), nowMs: T0 + 30_000, driverName: 'Mostafi',
    });
    expect(r.wantsEta).toBe(false);
  });
  it('compresses the throttle when etaPollScale < 1', () => {
    // eta 1200s => base interval 60s; scale 0.02 => 1.2s, so 30s has elapsed.
    const r = step({
      trip: trip(), position: pos(0.09, T0 + 30_000), nowMs: T0 + 30_000, driverName: 'Mostafi',
      etaPollScale: 0.02,
    });
    expect(r.wantsEta).toBe(true);
  });
  it('stretches the throttle when etaPollScale > 1', () => {
    const r = step({
      trip: trip(), position: pos(0.09, T0 + 60_000), nowMs: T0 + 60_000, driverName: 'Mostafi',
      etaPollScale: 10,
    });
    expect(r.wantsEta).toBe(false);
  });
});

describe('step: lastPos projection (no expireAt / unknown-field leak)', () => {
  it('drops expireAt and any unknown field from patch.lastPos', () => {
    const dirty = {
      lat: 0.05, lng: 0, accuracyM: 10, speedMps: 12, ts: T0 + 60_000,
      expireAt: { seconds: 1_800_000_000, nanoseconds: 0 },
      hacked: 'nope',
    } as unknown as Position;
    const r = run(trip(), dirty, 590);
    expect(Object.keys(r.patch.lastPos!)).not.toContain('expireAt');
    expect(Object.keys(r.patch.lastPos!)).not.toContain('hacked');
    expect('expireAt' in (r.patch.lastPos as object)).toBe(false);
    expect(r.patch.lastPos).toEqual({ lat: 0.05, lng: 0, accuracyM: 10, speedMps: 12, ts: T0 + 60_000 });
  });
  it('drops expireAt on the low-accuracy early-return path too', () => {
    const dirty = {
      lat: 0.05, lng: 0, accuracyM: 500, speedMps: 12, ts: T0 + 60_000,
      expireAt: { seconds: 1_800_000_000, nanoseconds: 0 },
    } as unknown as Position;
    const r = run(trip(), dirty, 590);
    expect('expireAt' in (r.patch.lastPos as object)).toBe(false);
  });
  it('keeps an on-device etaSec when the client supplied one', () => {
    const p: Position = { lat: 0.05, lng: 0, accuracyM: 10, speedMps: 12, ts: T0 + 60_000, etaSec: 590 };
    const r = run(trip(), p, 590);
    expect(r.patch.lastPos).toEqual({ lat: 0.05, lng: 0, accuracyM: 10, speedMps: 12, ts: T0 + 60_000, etaSec: 590 });
  });
});

describe('step: progressPct is always a sane percentage', () => {
  it('stays within 0..100 when routeDistanceM is undefined', () => {
    const r = run(trip({ routeDistanceM: undefined }), pos(0.05, T0 + 60_000), 590);
    const pct = r.patch.receiverView!.progressPct;
    expect(pct).toBeGreaterThanOrEqual(0);
    expect(pct).toBeLessThanOrEqual(100);
    expect(Number.isFinite(pct)).toBe(true);
  });
  it('stays within 0..100 when routeDistanceM is zero', () => {
    const r = run(trip({ routeDistanceM: 0 }), pos(0.05, T0 + 60_000), 590);
    const pct = r.patch.receiverView!.progressPct;
    expect(pct).toBeGreaterThanOrEqual(0);
    expect(pct).toBeLessThanOrEqual(100);
  });
  it('reports high progress when nearly at the spot', () => {
    const r = run(trip({ alerts: { ...initialAlerts(), tenMin: true } }), pos(0.001, T0 + 60_000), 120);
    expect(r.patch.receiverView!.progressPct).toBeGreaterThan(95);
    expect(r.patch.receiverView!.progressPct).toBeLessThanOrEqual(100);
  });
});

describe('step: arrived is NOT urgent (CLIENT_CONTRACT_ADDENDUM section C)', () => {
  it('emits arrived with a falsy urgent flag', () => {
    const t = trip({ phaseHint: 'near', alerts: { ...initialAlerts(), tenMin: true, leadTime: true, arrivalDwellSince: T0 + 600_000 } });
    const r = run(t, pos(0.0005, T0 + 621_000, 0.5));
    expect(r.pushes).toHaveLength(1);
    expect(r.pushes[0].data.kind).toBe('arrived');
    expect(r.pushes[0].urgent).toBeFalsy();
  });
  it('leadTime is the only urgent push the engine can emit', () => {
    const r = run(trip(), pos(0.02, T0 + 60_000), 170);
    expect(r.pushes.filter(p => p.urgent).map(p => p.data.kind)).toEqual(['leadTime']);
  });
});

/** Applies an EnginePatch onto a trip the way the be6 trigger will. */
function apply(t: TripDoc, patch: EnginePatch): TripDoc {
  const next: TripDoc = { ...t };
  if (patch.lastPos) next.lastPos = patch.lastPos;
  if (patch.phaseHint) next.phaseHint = patch.phaseHint;
  if (patch.eta) next.eta = patch.eta;
  if (patch.pendingEtaSec !== undefined) next.pendingEtaSec = patch.pendingEtaSec ?? undefined;
  if (patch.alerts) next.alerts = patch.alerts;
  if (patch.state) next.state = patch.state;
  if (patch.endedAt !== undefined) next.endedAt = patch.endedAt;
  if (patch.receiverView) next.receiverView = patch.receiverView;
  return next;
}

describe('step: the full happy ladder, driven sequentially', () => {
  // Each row is one position write, threading the previous patch back into the trip.
  const drive: { label: string; lat: number; atMs: number; speed: number; eta?: number; expect: string[] }[] = [
    { label: '20 min out',            lat: 0.08,   atMs: 60_000,  speed: 12,  eta: 900, expect: [] },
    { label: '12 min out',            lat: 0.06,   atMs: 120_000, speed: 12,  eta: 700, expect: [] },
    { label: 'under 10 min',          lat: 0.05,   atMs: 180_000, speed: 12,  eta: 590, expect: ['tenMin'] },
    { label: 'entering the near band', lat: 0.03,  atMs: 240_000, speed: 12,  eta: 400, expect: [] },
    { label: 'under lead time',       lat: 0.015,  atMs: 300_000, speed: 12,  eta: 170, expect: ['leadTime'] },
    { label: 'pulling in, dwell starts', lat: 0.0005, atMs: 360_000, speed: 1, expect: [] },
    { label: 'still there 21s later', lat: 0.0005, atMs: 381_000, speed: 0.5, expect: ['arrived'] },
  ];

  it('fires tenMin -> leadTime -> arrived exactly once each, in order, with no duplicates', () => {
    let t = trip();
    const emitted: string[] = [];
    const perStep: string[][] = [];

    for (const s of drive) {
      const ts = T0 + s.atMs;
      const out = step({
        trip: t, position: pos(s.lat, ts, s.speed), nowMs: ts,
        freshEtaSec: s.eta, driverName: 'Mostafi',
      });
      const kinds = out.pushes.map(p => p.data.kind);
      perStep.push(kinds);
      emitted.push(...kinds);
      t = apply(t, out.patch);
    }

    // Per-step expectations, so a failure names the exact leg of the drive.
    expect(perStep).toEqual(drive.map(s => s.expect));

    // The whole sequence, in order.
    expect(emitted).toEqual(['tenMin', 'leadTime', 'arrived']);

    // No duplicates anywhere in the run.
    expect(new Set(emitted).size).toBe(emitted.length);

    // Terminal state, and the flags that make the ladder idempotent.
    expect(t.state).toBe('arrived');
    expect(t.endedAt).toBe(T0 + 381_000);
    expect(t.alerts.tenMin).toBe(true);
    expect(t.alerts.leadTime).toBe(true);
    expect(t.alerts.arrived).toBe(true);
    expect(t.alerts.slipCount).toBe(0);
    expect(t.alerts.didYouLeave).toBe(false);
    expect(t.phaseHint).toBe('near');
    // lastPos survived seven writes without picking up a stray key.
    expect(Object.keys(t.lastPos!).sort()).toEqual(['accuracyM', 'lat', 'lng', 'speedMps', 'ts']);
  });

  it('emits nothing further once arrived (a late duplicate fix is inert)', () => {
    let t = trip();
    for (const s of drive) {
      const ts = T0 + s.atMs;
      const out = step({ trip: t, position: pos(s.lat, ts, s.speed), nowMs: ts, freshEtaSec: s.eta, driverName: 'Mostafi' });
      t = apply(t, out.patch);
    }
    const late = step({ trip: t, position: pos(0.0005, T0 + 400_000, 0.5), nowMs: T0 + 400_000, driverName: 'Mostafi' });
    expect(late.pushes).toHaveLength(0);
    expect(late.patch.state).toBeUndefined();
  });
});

describe('step: slip then recovery does not re-fire leadTime', () => {
  it('keeps leadTime armed when the slip stays at or below (leadTimeMin+2)*60', () => {
    // leadTimeMin 3 => re-arm threshold is 300s. A slip to 290s is a slip but not a re-arm.
    const t0 = trip({
      alerts: { ...initialAlerts(), tenMin: true, leadTime: true, lastSlipEtaSec: 170 },
      eta: { seconds: 170, updatedAt: T0, approximate: false },
    });
    const slipped = run(t0, pos(0.02, T0 + 60_000), 290);
    expect(slipped.pushes.map(p => p.data.kind)).toEqual(['slip']);
    expect(slipped.patch.alerts?.leadTime).toBe(true); // still armed => cannot re-fire
    expect(slipped.patch.alerts?.slipCount).toBe(1);

    // Recovery: ETA drops back under the lead time. leadTime must NOT fire again.
    const t1 = apply(t0, slipped.patch);
    const recovered = run(t1, pos(0.015, T0 + 120_000), 150);
    expect(recovered.pushes.map(p => p.data.kind)).toEqual([]);
    expect(recovered.patch.alerts?.leadTime).toBe(true);
  });

  it('re-fires leadTime only after the ETA exceeded (leadTimeMin+2)*60', () => {
    const t0 = trip({
      alerts: { ...initialAlerts(), tenMin: true, leadTime: true, lastSlipEtaSec: 170 },
      eta: { seconds: 170, updatedAt: T0, approximate: false },
    });
    // 420 > 300 => slip AND re-arm.
    const slipped = run(t0, pos(0.02, T0 + 60_000), 420);
    expect(slipped.pushes.map(p => p.data.kind)).toEqual(['slip']);
    expect(slipped.patch.alerts?.leadTime).toBe(false);

    const t1 = apply(t0, slipped.patch);
    const recovered = run(t1, pos(0.015, T0 + 120_000), 150);
    expect(recovered.pushes.map(p => p.data.kind)).toEqual(['leadTime']);
    expect(recovered.patch.alerts?.leadTime).toBe(true);
  });
});
