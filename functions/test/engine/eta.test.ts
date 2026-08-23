// functions/test/engine/eta.test.ts
import { pollIntervalSec, shouldPollEta, smoothEta, fallbackEtaSec, bandsFor } from '../../src/engine/eta';

describe('pollIntervalSec', () => {
  it('is 60s above 10 min', () => expect(pollIntervalSec(601)).toBe(60));
  it('is 30s between 5 and 10 min', () => { expect(pollIntervalSec(600)).toBe(30); expect(pollIntervalSec(301)).toBe(30); });
  it('is 15s under 5 min', () => expect(pollIntervalSec(300)).toBe(15));
  it('applies the emulator scale multiplier', () => expect(pollIntervalSec(601, 0.02)).toBe(1.2));
});

describe('shouldPollEta', () => {
  const now = 1_000_000_000;
  it('polls when never polled', () => expect(shouldPollEta(undefined, 900, now, 'far')).toBe(true));
  it('respects interval', () => {
    expect(shouldPollEta(now - 59_000, 900, now, 'far')).toBe(false);
    expect(shouldPollEta(now - 60_000, 900, now, 'far')).toBe(true);
  });
  it('polls immediately on first near-phase fix regardless of interval', () => {
    expect(shouldPollEta(now - 1_000, 900, now, 'near', true)).toBe(true);
  });
  it('polls under the compressed emulator scale', () => {
    expect(shouldPollEta(now - 2_000, 900, now, 'far', false, 0.02)).toBe(true);
  });
});

describe('smoothEta', () => {
  const t0 = 1_000_000_000;
  it('accepts first reading', () => {
    expect(smoothEta(undefined, 800, t0, undefined)).toEqual({ seconds: 800, pending: undefined });
  });
  it('accepts a small change', () => {
    const prev = { seconds: 800, updatedAt: t0, approximate: false };
    expect(smoothEta(prev, 720, t0 + 10_000, undefined).seconds).toBe(720);
  });
  it('rejects a jump >max(120s,25%) within 15s, holding it as pending', () => {
    const prev = { seconds: 800, updatedAt: t0, approximate: false };
    const r = smoothEta(prev, 1100, t0 + 10_000, undefined);
    expect(r.seconds).toBe(800);
    expect(r.pending).toBe(1100);
  });
  it('accepts the jump when the next reading agrees with the pending one', () => {
    const prev = { seconds: 800, updatedAt: t0, approximate: false };
    const r = smoothEta(prev, 1090, t0 + 12_000, 1100);
    expect(r.seconds).toBe(1090);
    expect(r.pending).toBeUndefined();
  });
  it('accepts a big jump after 15s have passed', () => {
    const prev = { seconds: 800, updatedAt: t0, approximate: false };
    expect(smoothEta(prev, 1100, t0 + 16_000, undefined).seconds).toBe(1100);
  });
});

describe('fallbackEtaSec', () => {
  it('uses remaining distance over avg speed, floor 8 m/s', () => {
    expect(fallbackEtaSec(1600, 4)).toBe(200);   // 8 m/s floor
    expect(fallbackEtaSec(1600, 16)).toBe(100);
  });
});

describe('bandsFor', () => {
  it('maps minutes-before-arrival to meters using route avg speed', () => {
    // 12000 m route, 1200 s → 10 m/s
    const b = bandsFor(12_000, 1_200, 3);
    expect(b.far).toBe(7_200);   // 12 min * 60 * 10
    expect(b.near).toBe(4_200);  // 7 min
    expect(b.lead).toBe(3_000);  // (3+2) min
  });
  it('never exceeds route distance', () => {
    const b = bandsFor(3_000, 300, 3);
    expect(b.far).toBe(3_000);
  });
});
