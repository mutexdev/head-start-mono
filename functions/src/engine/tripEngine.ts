// functions/src/engine/tripEngine.ts
//
// PURITY CONTRACT — read before editing.
//
// This module holds every alert decision in the product: the tenMin / leadTime /
// slip / didYouLeave / arrived ladder. It is deliberately a pure function of its
// inputs so that the whole ladder can be unit-tested without an emulator, a
// clock, or a network — batches be6 (the onPositionWrite trigger) and be7 (the
// housekeeping sweep) both depend on that.
//
// Therefore this file MUST NOT:
//   - import anything from ../io/* (no firebase-admin, no Firestore, no FCM),
//   - call Date.now() or new Date() — the caller passes `nowMs`,
//   - read process.env — throttle scaling arrives as `EngineInput.etaPollScale`,
//   - perform any I/O, logging or mutation of its arguments.
//
// Allowed imports: ../types, ./geo, ./eta, ../messages. Nothing else.
import { Alerts, Eta, Phase, Position, PushMessage, ReceiverView, StoredPosition, TripDoc, TripState } from '../types';
import { haversineMeters } from './geo';
import { shouldPollEta, smoothEta } from './eta';
import { msg } from '../messages';

export interface EngineInput {
  trip: TripDoc;
  position: Position;
  nowMs: number;
  /** ETA returned by Google Routes (or fallback) for this step, if the caller fetched one */
  freshEtaSec?: number;
  freshEtaApproximate?: boolean;
  driverName: string;
  /**
   * Previous pending (unconfirmed) ETA from smoothing. Normally lives on the
   * trip document (`trip.pendingEtaSec`); this field lets a caller override it.
   */
  pendingEtaSec?: number;
  /**
   * Pure multiplier for the routing throttle, threaded straight through to
   * shouldPollEta. 1 = production. The emulator harness passes
   * Number(process.env.ETA_POLL_SCALE ?? '1') from the TRIGGER — never from
   * inside this module, which stays env-free.
   */
  etaPollScale?: number;
}

export interface EnginePatch {
  /**
   * Projected field-by-field from the incoming position — never spread. The
   * client's positions document carries `expireAt: Timestamp` (TTL) which must
   * not survive into the trip doc: a Timestamp inside `lastPos` is a hard decode
   * failure for the strict Swift/Kotlin decoders. See CLIENT_CONTRACT_ADDENDUM.md
   * section J.
   */
  lastPos?: StoredPosition;
  phaseHint?: Phase;
  eta?: Eta;
  pendingEtaSec?: number | null;
  alerts?: Alerts;
  state?: TripState;
  endedAt?: number;
  receiverView?: ReceiverView;
}

export interface EngineOutput {
  patch: EnginePatch;
  pushes: PushMessage[];
  /** true when the caller should fetch a fresh ETA and call step() again with it */
  wantsEta: boolean;
}

const MAX_ACCURACY_M = 100;
const MOVE_CHECK_AFTER_MS = 3 * 60_000;
const MOVE_MIN_M = 150;
const ARRIVE_SPEED_MPS = 2;
const ARRIVE_DWELL_MS = 20_000;
const SLIP_MIN_SEC = 120;

/**
 * Projects an incoming position onto exactly the six/seven keys the trip
 * document stores. Anything else on the input object — `expireAt`, or any field
 * a future client starts sending — is dropped here and can never reach
 * Firestore via `lastPos`.
 */
function projectPosition(p: Position): StoredPosition {
  const out: StoredPosition = {
    lat: p.lat,
    lng: p.lng,
    accuracyM: p.accuracyM,
    speedMps: p.speedMps,
    ts: p.ts,
    ...(p.etaSec !== undefined ? { etaSec: p.etaSec } : {}),
  };
  return out;
}

export function step(input: EngineInput): EngineOutput {
  const { trip, position, nowMs, driverName } = input;
  const pushes: PushMessage[] = [];
  const alerts: Alerts = { ...trip.alerts };
  const patch: EnginePatch = { lastPos: projectPosition(position) };
  const spot = trip.spot;
  const etaPollScale = input.etaPollScale ?? 1;

  // 1. Ignore garbage fixes but still record liveness.
  if (position.accuracyM > MAX_ACCURACY_M) {
    return { patch, pushes, wantsEta: false };
  }

  const distToSpot = haversineMeters(position, spot);

  // 2. Phase.
  let phase: Phase = trip.phaseHint;
  let justEnteredNear = false;
  if (phase === 'far' && trip.bands && distToSpot <= trip.bands.near) {
    phase = 'near';
    justEnteredNear = true;
    patch.phaseHint = 'near';
  }

  // 3. Movement verification (driver side).
  if (
    !alerts.didYouLeave && trip.startedAt !== undefined && trip.startPos &&
    nowMs - trip.startedAt >= MOVE_CHECK_AFTER_MS &&
    haversineMeters(position, trip.startPos) < MOVE_MIN_M
  ) {
    alerts.didYouLeave = true;
    pushes.push(msg.didYouLeave(trip.driverUid));
  }

  // 4. ETA: apply fresh reading with smoothing, else decide whether to poll.
  let eta: Eta | undefined = trip.eta;
  let wantsEta = false;
  if (input.freshEtaSec !== undefined) {
    const s = smoothEta(trip.eta, input.freshEtaSec, nowMs, input.pendingEtaSec ?? trip.pendingEtaSec);
    eta = { seconds: s.seconds, updatedAt: nowMs, approximate: !!input.freshEtaApproximate };
    patch.eta = eta;
    patch.pendingEtaSec = s.pending ?? null;
  } else {
    wantsEta = shouldPollEta(
      trip.lastRoutingCallAt, trip.eta?.seconds ?? 0, nowMs, phase, justEnteredNear, etaPollScale,
    );
  }

  // 5. Alert ladder (only when we have a fresh, accepted ETA this step).
  if (patch.eta && eta) {
    const sec = eta.seconds;
    const leadSec = trip.leadTimeMin * 60;
    const a = eta.approximate;

    // slip + re-arm
    if (alerts.tenMin) {
      const base = alerts.lastSlipEtaSec ?? trip.eta?.seconds ?? sec;
      if (sec - base >= SLIP_MIN_SEC) {
        alerts.slipCount += 1;
        alerts.lastSlipEtaSec = sec;
        pushes.push(msg.slip(trip.receiverUid, driverName, sec, a));
        if (alerts.leadTime && sec > (trip.leadTimeMin + 2) * 60) alerts.leadTime = false;
      }
    }
    if (!alerts.tenMin && sec <= 600) {
      alerts.tenMin = true;
      alerts.lastSlipEtaSec = sec;
      pushes.push(msg.tenMin(trip.receiverUid, driverName, sec, a));
    }
    if (!alerts.leadTime && sec <= leadSec) {
      alerts.leadTime = true;
      pushes.push(msg.leadTime(trip.receiverUid, driverName, sec, a));
    }
    // keep lastSlipEtaSec tracking the latest accepted eta when it improves
    if (alerts.tenMin && alerts.lastSlipEtaSec !== undefined && sec < alerts.lastSlipEtaSec) {
      alerts.lastSlipEtaSec = sec;
    }

    // receiver projection
    const total = trip.routeDistanceM ?? distToSpot;
    const view: ReceiverView = {
      etaSeconds: sec,
      progressPct: Math.max(0, Math.min(100, Math.round((1 - distToSpot / Math.max(total, 1)) * 100))),
    };
    if (!trip.fuzzy || sec <= 300) view.lastPos = { lat: position.lat, lng: position.lng };
    patch.receiverView = view;
  }

  // 6. Arrival detection.
  if (!alerts.arrived) {
    if (distToSpot <= spot.radiusM && position.speedMps < ARRIVE_SPEED_MPS) {
      if (alerts.arrivalDwellSince === undefined) {
        alerts.arrivalDwellSince = nowMs;
      } else if (nowMs - alerts.arrivalDwellSince >= ARRIVE_DWELL_MS) {
        alerts.arrived = true;
        patch.state = 'arrived';
        patch.endedAt = nowMs;
        pushes.push(msg.arrived(trip.receiverUid, driverName, spot.name));
        wantsEta = false;
      }
    } else if (alerts.arrivalDwellSince !== undefined) {
      delete alerts.arrivalDwellSince;
    }
  }

  patch.alerts = alerts;
  return { patch, pushes, wantsEta };
}
