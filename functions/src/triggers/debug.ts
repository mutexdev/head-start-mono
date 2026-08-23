// functions/src/triggers/debug.ts
//
// EMULATOR-ONLY endpoints. Both return 404 unless FUNCTIONS_EMULATOR === 'true'
// or ENABLE_DEBUG_ENDPOINTS === '1', so they are inert even if someone later
// deploys them.
//
// They exist because `onSchedule('every 1 minutes')` is not emulated —
// firebase-tools maps a scheduled function onto the Pub/Sub topic
// `firebase-schedule-<name>` and ignores it when the Pub/Sub emulator is absent.
// Rather than adding another Java process and another port just to publish a
// protobuf tick, `debugRunHousekeeping` calls the same pure
// `runHousekeeping(nowMs)` with an injectable clock, so the driver script can
// cross the 5-minute-lost and 3-hour-timeout thresholds instantly.
// See CLIENT_CONTRACT_ADDENDUM.md, "Scheduled functions are not emulated".
import { onRequest } from 'firebase-functions/v2/https';
import { runHousekeeping } from './housekeeping';

export const enabled = (env: NodeJS.ProcessEnv = process.env): boolean =>
  env.FUNCTIONS_EMULATOR === 'true' || env.ENABLE_DEBUG_ENDPOINTS === '1';

/**
 * POST/GET; `now` may be given as `?now=<epochMs>` or as a JSON body `{ now }`.
 * Defaults to the real clock. A non-numeric `now` falls back to the real clock
 * rather than poisoning every comparison with NaN (NaN > x is false, so a
 * NaN clock would silently make the whole sweep a no-op and look like a pass).
 */
export const debugRunHousekeeping = onRequest(async (req, res) => {
  if (!enabled()) { res.status(404).send('not found'); return; }
  const raw = req.query.now ?? (req.body as { now?: unknown } | undefined)?.now;
  const parsed = Number(raw);
  const nowMs = Number.isFinite(parsed) && parsed > 0 ? parsed : Date.now();
  const counts = await runHousekeeping(nowMs);
  res.json({ ok: true, nowMs, ...counts });
});

/** Liveness + a readout of the stub configuration the harness depends on. */
export const debugPing = onRequest(async (_req, res) => {
  if (!enabled()) { res.status(404).send('not found'); return; }
  res.json({
    ok: true,
    sink: process.env.PUSH_SINK ?? null,
    etaPollScale: process.env.ETA_POLL_SCALE ?? null,
    stubSpeed: process.env.ROUTING_STUB_SPEED_MPS ?? null,
  });
});
