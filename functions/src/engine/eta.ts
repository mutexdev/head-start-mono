// functions/src/engine/eta.ts
import { Bands, Eta, Phase } from '../types';

/**
 * Seconds to wait between routing calls, given the current ETA.
 *
 * `scale` is a pure multiplier used by the emulator harness to compress the
 * 60/30/15 s throttles (ETA_POLL_SCALE=0.02 turns them into 1.2/0.6/0.3 s) so a
 * 30-second scripted drive can actually walk the alert ladder. It is a
 * parameter, never an environment read — this module stays pure. The default of
 * 1 keeps production behaviour and every original unit test unchanged.
 */
export function pollIntervalSec(etaSec: number, scale = 1): number {
  const base = etaSec > 600 ? 60 : etaSec > 300 ? 30 : 15;
  return base * scale;
}

export function shouldPollEta(
  lastCallAtMs: number | undefined,
  etaSec: number,
  nowMs: number,
  phase: Phase,
  justEnteredNear = false,
  scale = 1,
): boolean {
  if (lastCallAtMs === undefined) return true;
  if (phase === 'near' && justEnteredNear) return true;
  return nowMs - lastCallAtMs >= pollIntervalSec(etaSec, scale) * 1000;
}

export interface SmoothResult { seconds: number; pending: number | undefined }

/**
 * Rejects a fresh ETA that jumps by more than max(120s, 25%) within 15s of the
 * previous accepted value unless two consecutive readings agree (within 10%).
 */
export function smoothEta(
  prev: Eta | undefined,
  fresh: number,
  nowMs: number,
  pending: number | undefined,
): SmoothResult {
  if (!prev) return { seconds: fresh, pending: undefined };
  const delta = Math.abs(fresh - prev.seconds);
  const threshold = Math.max(120, prev.seconds * 0.25);
  const recent = nowMs - prev.updatedAt < 15_000;
  if (delta <= threshold || !recent) return { seconds: fresh, pending: undefined };
  if (pending !== undefined && Math.abs(fresh - pending) <= pending * 0.1) {
    return { seconds: fresh, pending: undefined };
  }
  return { seconds: prev.seconds, pending: fresh };
}

export function fallbackEtaSec(remainingMeters: number, avgSpeedMps: number): number {
  return Math.round(remainingMeters / Math.max(avgSpeedMps, 8));
}

export function bandsFor(routeDistanceM: number, routeEtaSec: number, leadTimeMin: number): Bands {
  const v = routeDistanceM / Math.max(routeEtaSec, 1);
  const m = (min: number) => Math.min(routeDistanceM, Math.round(min * 60 * v));
  return { far: m(12), near: m(7), lead: m(leadTimeMin + 2) };
}
