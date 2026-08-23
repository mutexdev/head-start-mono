// functions/src/types.ts
//
// Dependency-free shared document/message types. This module MUST NOT import
// firebase-admin (or anything else) — the engine, the scripts and the tests all
// pull it in and it has to stay a pure type surface.

export type Platform = 'ios' | 'android';
export type PairStatus = 'pending' | 'active' | 'revoked';
export type TripState = 'armed' | 'driving' | 'arrived' | 'cancelled' | 'timeout' | 'lost';
export type Phase = 'far' | 'near';
export type ReplyKind = 'fiveMore' | 'takeYourTime' | 'atSpot' | 'runningLate' | 'custom';

/** Which sink the push layer delivers to. `firestore` writes `_debugPushes/{id}` under the emulator. */
export type PushSink = 'fcm' | 'firestore';

export interface LatLng { lat: number; lng: number }

export interface UserDoc {
  phone: string;
  displayName: string;
  platform: Platform;
  fcmTokens: string[];
  liveActivityPushToken?: string;
  lowBattery?: boolean;
  createdAt: number;
}

export interface PairDoc {
  members: [string, string] | [string];
  status: PairStatus;
  inviteCode: string;
  createdBy: string;
  createdAt: number;
  /**
   * Denormalised `uid -> displayName` for every member. Required from the first
   * write (see CLIENT_CONTRACT.md: clients render the partner's name from here
   * instead of reading the other user's document). Populated with the creator in
   * createPair, completed with both members in acceptPair, and kept in step by
   * syncDisplayNameToPairs.
   */
  memberNames: Record<string, string>;
}

export interface SpotDoc {
  pairId: string;
  name: string;
  lat: number;
  lng: number;
  radiusM: number;
  leadTimeMin: number;
  createdBy: string;
  createdAt: number;
}

/**
 * A location fix. This is also the wire shape the driver writes to
 * `trips/{tripId}/positions/{autoId}` — except that the client additionally
 * sends `expireAt: Timestamp` (TTL), which is deliberately NOT modelled here.
 */
export interface Position {
  lat: number;
  lng: number;
  accuracyM: number;
  speedMps: number;
  ts: number; // epoch ms
  /** Optional ETA computed on-device (e.g. iOS MapKit). When present the server skips its routing call. */
  etaSec?: number;
}

/**
 * The projection of an incoming position that is stored on `trips/{id}.lastPos`.
 * Structurally identical to `Position`, and deliberately so: the incoming
 * Firestore document carries a `expireAt: Timestamp` that must NOT survive into
 * the trip document (a Timestamp inside `lastPos` is a hard decode failure for
 * the strict Swift/Kotlin decoders on both clients).
 *
 * Contract for the trigger and the engine: build the value field-by-field from
 * exactly `{ lat, lng, accuracyM, speedMps, ts, etaSec? }` — never spread the
 * raw snapshot data into `lastPos`.
 */
export type StoredPosition = Position;

export interface Eta {
  seconds: number;
  updatedAt: number;
  approximate: boolean;
}

export interface Bands { far: number; near: number; lead: number } // meters from destination

export interface Alerts {
  started: boolean;
  tenMin: boolean;
  leadTime: boolean;
  arrived: boolean;
  didYouLeave: boolean;
  slipCount: number;
  lastSlipEtaSec?: number;
  /** ts when we first saw the driver inside the arrival radius at low speed */
  arrivalDwellSince?: number;
}

export interface ReceiverView {
  etaSeconds: number;
  progressPct: number;
  lastPos?: LatLng;
}

export interface TripDoc {
  pairId: string;
  driverUid: string;
  receiverUid: string;
  spotId: string;
  spot: { lat: number; lng: number; radiusM: number; name: string };
  leadTimeMin: number;
  state: TripState;
  createdAt: number;
  startedAt?: number;
  endedAt?: number;
  startPos?: LatLng;
  eta?: Eta;
  /** A fresh ETA reading held back by smoothEta until a second reading agrees with it. */
  pendingEtaSec?: number;
  routePolyline?: string;
  routeDistanceM?: number;
  bands?: Bands;
  lastPos?: StoredPosition;
  alerts: Alerts;
  fuzzy: boolean;
  neededBy?: number;
  lastRoutingCallAt?: number;
  routingCalls: number;
  phaseHint: Phase;
  receiverView?: ReceiverView;
  lostNotified?: boolean;
  noShowNotified?: boolean;
}

export interface ReplyDoc {
  fromUid: string;
  kind: ReplyKind;
  text?: string;
  ts: number;
}

export interface ScheduleDoc {
  pairId: string;
  spotId: string;
  driverUid: string;
  receiverUid: string;
  days: number[];      // 0=Sun..6=Sat
  timeLocal: string;   // "HH:mm"
  tz: string;          // IANA
  enabled: boolean;
  lastFiredDate?: string; // "YYYY-MM-DD" in tz
}

export interface PushMessage {
  toUid: string;
  title: string;
  body: string;
  /**
   * data payload; all values strings per FCM.
   *
   * Message builders only ever set `kind`. The push layer additionally injects
   * `data.tripId` for every trip-scoped push (from its `ctx` argument) — see
   * CLIENT_CONTRACT_ADDENDUM.md section D. Keep this a flat
   * `Record<string, string>`: FCM rejects non-string data values.
   */
  data: Record<string, string>;
  /** lead-time alert uses high priority + distinct channel/sound */
  urgent?: boolean;
}

export const initialAlerts = (): Alerts => ({
  started: false, tenMin: false, leadTime: false, arrived: false, didYouLeave: false, slipCount: 0,
});
