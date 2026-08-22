# The Sync — M1 Backend (Cloud Functions) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Firebase backend for milestone M1: pairing, spots, trip lifecycle, the pure `TripEngine` alert ladder, route ETA (Google Routes API behind a `RoutingProvider` interface, with optional on-device ETA from the driver's phone) with throttling/fallback, FCM pushes, and the lost/timeout scheduler — fully unit-tested and deployable.

**Architecture:** A single Cloud Functions (TypeScript, Node 20, firebase-functions v2) project. All alert decisions live in a pure, side-effect-free `TripEngine.step()` that takes (trip, position, now, freshEta?) and returns (patch, pushes, wantsEta). Thin wrappers (Firestore trigger, callables, scheduler) do I/O around it. Clients only ever write `trips/{id}/positions/*`; everything else goes through callables.

**Tech Stack:** Firebase (Auth phone, Firestore, Functions v2, FCM), TypeScript 5, Jest + ts-jest, Google Routes API (Compute Routes v2) behind a swappable `RoutingProvider`, firebase-functions-test not used (engine is pure; callables tested against the Firestore emulator).

**Spec:** `docs/superpowers/specs/2026-08-22-the-sync-design.md`

**Sibling plans (written after this one lands):** `m1-ios.md`, `m1-android.md`, then M2–M4.

---

## File structure

```
firebase.json                 emulators + functions + firestore config
.firebaserc                   project alias (user fills project id)
firestore.rules               security rules
firestore.indexes.json        composite indexes
functions/
  package.json, tsconfig.json, jest.config.js, .eslintrc.cjs
  src/
    types.ts                  Firestore document shapes + enums (single source of truth)
    messages.ts               all push copy (title/body builders)
    engine/
      eta.ts                  pollIntervalSec, shouldPollEta, smoothEta, fallbackEtaSec, bandsFor
      geo.ts                  haversineMeters, polylineRemainingMeters, decodePolyline
      tripEngine.ts           step(): alert ladder + state transitions (pure)
    io/
      firestore.ts            admin init + typed collection helpers
      routing.ts              RoutingProvider interface; googleRoutes impl; stub for tests; directions(from,to)
      push.ts                 sendToUser(uid, msg), prune invalid tokens
    callables/
      pairs.ts                createPair, acceptPair, revokePair
      spots.ts                upsertSpot, deleteSpot
      trips.ts                startTrip, endTrip, armTrip, sendReply, setRunningLate
      tokens.ts               registerPushToken
    triggers/
      onPositionWrite.ts      Firestore trigger → engine → writes + pushes
      housekeeping.ts         every-minute: lost / timeout / armed no-show
    index.ts                  exports
  test/
    io/routing.test.ts
    engine/eta.test.ts
    engine/geo.test.ts
    engine/tripEngine.test.ts
    messages.test.ts
    callables/trips.emulator.test.ts   (runs only with FIRESTORE_EMULATOR_HOST)
docs/testing/real-drive-checklist.md
```

Conventions: ESM off (CommonJS, simplest for Functions). Times are epoch **milliseconds** (`number`) inside the engine; Firestore `Timestamp` only at the I/O boundary. Distances meters, ETA seconds.

---

### Task 1: Project scaffold

**Files:**
- Create: `firebase.json`, `.firebaserc`, `firestore.indexes.json`, `functions/package.json`, `functions/tsconfig.json`, `functions/jest.config.js`, `functions/.gitignore`, `functions/src/index.ts`

- [ ] **Step 1: Create root Firebase config**

`firebase.json`:
```json
{
  "functions": { "source": "functions", "runtime": "nodejs20", "predeploy": ["npm --prefix functions run build"] },
  "firestore": { "rules": "firestore.rules", "indexes": "firestore.indexes.json" },
  "emulators": {
    "auth": { "port": 9099 },
    "functions": { "port": 5001 },
    "firestore": { "port": 8080 },
    "ui": { "enabled": true }
  }
}
```

`.firebaserc`:
```json
{ "projects": { "default": "fin-e8358" } }
```
(Replace `fin-e8358` with the real project id after `firebase projects:create`.)

`firestore.indexes.json`:
```json
{
  "indexes": [
    { "collectionGroup": "trips", "queryScope": "COLLECTION",
      "fields": [ { "fieldPath": "pairId", "order": "ASCENDING" }, { "fieldPath": "state", "order": "ASCENDING" } ] },
    { "collectionGroup": "trips", "queryScope": "COLLECTION",
      "fields": [ { "fieldPath": "state", "order": "ASCENDING" }, { "fieldPath": "lastPos.ts", "order": "ASCENDING" } ] }
  ],
  "fieldOverrides": [
    { "collectionGroup": "positions", "fieldPath": "expireAt", "ttl": true, "indexes": [] }
  ]
}
```

- [ ] **Step 2: Create functions package**

`functions/package.json`:
```json
{
  "name": "the-sync-functions",
  "private": true,
  "main": "lib/index.js",
  "engines": { "node": "20" },
  "scripts": {
    "build": "tsc",
    "test": "jest",
    "test:emu": "firebase emulators:exec --only firestore,auth \"jest --testMatch '**/*.emulator.test.ts'\"",
    "serve": "npm run build && firebase emulators:start",
    "deploy": "firebase deploy --only functions,firestore"
  },
  "dependencies": {
    "firebase-admin": "^12.6.0",
    "firebase-functions": "^6.1.0"
  },
  "devDependencies": {
    "@types/jest": "^29.5.12",
    "jest": "^29.7.0",
    "ts-jest": "^29.2.5",
    "typescript": "^5.6.3"
  }
}
```

`functions/tsconfig.json`:
```json
{
  "compilerOptions": {
    "target": "ES2022", "module": "commonjs", "lib": ["ES2022"],
    "outDir": "lib", "rootDir": "src", "strict": true, "esModuleInterop": true,
    "sourceMap": true, "skipLibCheck": true
  },
  "include": ["src"]
}
```

`functions/jest.config.js`:
```js
module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  roots: ['<rootDir>/test'],
  testPathIgnorePatterns: ['\\.emulator\\.test\\.ts$'],
};
```

`functions/.gitignore`:
```
node_modules
lib
*.log
```

`functions/src/index.ts`:
```ts
export {};
```

- [ ] **Step 3: Install and verify build**

Run: `cd functions && npm install && npm run build && npx jest --passWithNoTests`
Expected: `tsc` exits 0, Jest prints "No tests found" and exits 0.

- [ ] **Step 4: Commit**

```bash
git add firebase.json .firebaserc firestore.indexes.json functions
git commit -m "chore: scaffold Firebase functions project"
```

---

### Task 2: Shared types

**Files:**
- Create: `functions/src/types.ts`

- [ ] **Step 1: Write types**

```ts
// functions/src/types.ts
export type Platform = 'ios' | 'android';
export type PairStatus = 'pending' | 'active' | 'revoked';
export type TripState = 'armed' | 'driving' | 'arrived' | 'cancelled' | 'timeout' | 'lost';
export type Phase = 'far' | 'near';
export type ReplyKind = 'fiveMore' | 'takeYourTime' | 'atSpot' | 'runningLate' | 'custom';

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

export interface Position {
  lat: number;
  lng: number;
  accuracyM: number;
  speedMps: number;
  ts: number; // epoch ms
  /** Optional ETA computed on-device (e.g. iOS MapKit). When present the server skips its routing call. */
  etaSec?: number;
}

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
  routePolyline?: string;
  routeDistanceM?: number;
  bands?: Bands;
  lastPos?: Position;
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
  /** data payload; all values strings per FCM */
  data: Record<string, string>;
  /** lead-time alert uses high priority + distinct channel/sound */
  urgent?: boolean;
}

export const initialAlerts = (): Alerts => ({
  started: false, tenMin: false, leadTime: false, arrived: false, didYouLeave: false, slipCount: 0,
});
```

- [ ] **Step 2: Build**

Run: `cd functions && npm run build`
Expected: exit 0.

- [ ] **Step 3: Commit**

```bash
git add functions/src/types.ts
git commit -m "feat(functions): add Firestore document types"
```

---

### Task 3: Geo helpers

**Files:**
- Create: `functions/src/engine/geo.ts`
- Test: `functions/test/engine/geo.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// functions/test/engine/geo.test.ts
import { haversineMeters, decodePolyline, polylineRemainingMeters } from '../../src/engine/geo';

describe('haversineMeters', () => {
  it('is ~0 for identical points', () => {
    expect(haversineMeters({ lat: 1, lng: 1 }, { lat: 1, lng: 1 })).toBeCloseTo(0, 3);
  });
  it('is ~111km per degree latitude', () => {
    const d = haversineMeters({ lat: 0, lng: 0 }, { lat: 1, lng: 0 });
    expect(d).toBeGreaterThan(110_000);
    expect(d).toBeLessThan(112_000);
  });
});

describe('decodePolyline', () => {
  it('decodes the Google reference example (precision 5)', () => {
    const pts = decodePolyline('_p~iF~ps|U_ulLnnqC_mqNvxq`@');
    expect(pts).toHaveLength(3);
    expect(pts[0].lat).toBeCloseTo(38.5, 3);
    expect(pts[0].lng).toBeCloseTo(-120.2, 3);
    expect(pts[2].lat).toBeCloseTo(43.252, 3);
    expect(pts[2].lng).toBeCloseTo(-126.453, 3);
  });
});

describe('polylineRemainingMeters', () => {
  // straight line north along lng 0 from lat 0 to lat 0.02 (~2.2km), 3 vertices
  const line = [{ lat: 0, lng: 0 }, { lat: 0.01, lng: 0 }, { lat: 0.02, lng: 0 }];
  it('returns full length at the start', () => {
    const m = polylineRemainingMeters(line, { lat: 0, lng: 0 });
    expect(m).toBeGreaterThan(2_200);
    expect(m).toBeLessThan(2_250);
  });
  it('returns roughly half from the midpoint', () => {
    const m = polylineRemainingMeters(line, { lat: 0.01, lng: 0.0001 });
    expect(m).toBeGreaterThan(1_100);
    expect(m).toBeLessThan(1_125);
  });
  it('returns 0 at the end', () => {
    expect(polylineRemainingMeters(line, { lat: 0.02, lng: 0 })).toBeLessThan(5);
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest test/engine/geo.test.ts`
Expected: FAIL — cannot find module '../../src/engine/geo'.

- [ ] **Step 3: Implement**

```ts
// functions/src/engine/geo.ts
import { LatLng } from '../types';

const R = 6_371_000;
const toRad = (d: number) => (d * Math.PI) / 180;

export function haversineMeters(a: LatLng, b: LatLng): number {
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const s =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(a.lat)) * Math.cos(toRad(b.lat)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(s));
}

/** Decodes a Google/Google Routes encoded polyline (precision 5). */
export function decodePolyline(encoded: string): LatLng[] {
  const pts: LatLng[] = [];
  let index = 0, lat = 0, lng = 0;
  while (index < encoded.length) {
    for (const which of ['lat', 'lng'] as const) {
      let shift = 0, result = 0, byte: number;
      do {
        byte = encoded.charCodeAt(index++) - 63;
        result |= (byte & 0x1f) << shift;
        shift += 5;
      } while (byte >= 0x20);
      const delta = result & 1 ? ~(result >> 1) : result >> 1;
      if (which === 'lat') lat += delta; else lng += delta;
    }
    pts.push({ lat: lat / 1e5, lng: lng / 1e5 });
  }
  return pts;
}

/** Distance along the polyline from the vertex nearest `pos` to the end. */
export function polylineRemainingMeters(line: LatLng[], pos: LatLng): number {
  if (line.length === 0) return 0;
  let nearest = 0, best = Infinity;
  for (let i = 0; i < line.length; i++) {
    const d = haversineMeters(line[i], pos);
    if (d < best) { best = d; nearest = i; }
  }
  let sum = 0;
  for (let i = nearest; i < line.length - 1; i++) sum += haversineMeters(line[i], line[i + 1]);
  return sum;
}
```

- [ ] **Step 4: Run tests**

Run: `cd functions && npx jest test/engine/geo.test.ts`
Expected: PASS (6 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/src/engine/geo.ts functions/test/engine/geo.test.ts
git commit -m "feat(functions): add geo helpers (haversine, polyline)"
```

---

### Task 4: ETA helpers (polling, smoothing, fallback, bands)

**Files:**
- Create: `functions/src/engine/eta.ts`
- Test: `functions/test/engine/eta.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// functions/test/engine/eta.test.ts
import { pollIntervalSec, shouldPollEta, smoothEta, fallbackEtaSec, bandsFor } from '../../src/engine/eta';

describe('pollIntervalSec', () => {
  it('is 60s above 10 min', () => expect(pollIntervalSec(601)).toBe(60));
  it('is 30s between 5 and 10 min', () => { expect(pollIntervalSec(600)).toBe(30); expect(pollIntervalSec(301)).toBe(30); });
  it('is 15s under 5 min', () => expect(pollIntervalSec(300)).toBe(15));
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest test/engine/eta.test.ts`
Expected: FAIL — cannot find module.

- [ ] **Step 3: Implement**

```ts
// functions/src/engine/eta.ts
import { Bands, Eta, Phase } from '../types';

export function pollIntervalSec(etaSec: number): number {
  if (etaSec > 600) return 60;
  if (etaSec > 300) return 30;
  return 15;
}

export function shouldPollEta(
  lastCallAtMs: number | undefined,
  etaSec: number,
  nowMs: number,
  phase: Phase,
  justEnteredNear = false,
): boolean {
  if (lastCallAtMs === undefined) return true;
  if (phase === 'near' && justEnteredNear) return true;
  return nowMs - lastCallAtMs >= pollIntervalSec(etaSec) * 1000;
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
```

- [ ] **Step 4: Run tests**

Run: `cd functions && npx jest test/engine/eta.test.ts`
Expected: PASS (13 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/src/engine/eta.ts functions/test/engine/eta.test.ts
git commit -m "feat(functions): add ETA polling, smoothing, fallback and band helpers"
```

---

### Task 5: Push message copy

**Files:**
- Create: `functions/src/messages.ts`
- Test: `functions/test/messages.test.ts`

- [ ] **Step 1: Write failing test**

```ts
// functions/test/messages.test.ts
import { msg } from '../src/messages';

describe('messages', () => {
  it('started includes driver and rounded minutes', () => {
    const m = msg.started('r1', 'Mostafi', 1330, 'Office');
    expect(m.toUid).toBe('r1');
    expect(m.title).toBe('Mostafi started driving');
    expect(m.body).toBe('ETA 22 min to Office');
    expect(m.data.kind).toBe('started');
  });
  it('leadTime is urgent', () => {
    const m = msg.leadTime('r1', 'Mostafi', 170);
    expect(m.urgent).toBe(true);
    expect(m.title).toBe('Start walking now');
    expect(m.body).toBe('Mostafi is 3 min away');
  });
  it('appends (approx.) when approximate', () => {
    expect(msg.tenMin('r1', 'Mostafi', 590, true).body).toBe('Mostafi is 10 min away (approx.)');
  });
  it('slip says stay inside', () => {
    expect(msg.slip('r1', 'Mostafi', 480).body).toBe('Traffic — now 8 min, stay inside');
  });
});
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest test/messages.test.ts`
Expected: FAIL — cannot find module.

- [ ] **Step 3: Implement**

```ts
// functions/src/messages.ts
import { PushMessage } from './types';

const min = (sec: number) => Math.max(1, Math.round(sec / 60));
const approx = (a?: boolean) => (a ? ' (approx.)' : '');

function build(toUid: string, kind: string, title: string, body: string, extra: Record<string, string> = {}, urgent = false): PushMessage {
  return { toUid, title, body, data: { kind, ...extra }, urgent };
}

export const msg = {
  started: (toUid: string, driver: string, etaSec: number, spotName: string, a?: boolean) =>
    build(toUid, 'started', `${driver} started driving`, `ETA ${min(etaSec)} min to ${spotName}${approx(a)}`),
  tenMin: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'tenMin', `${driver} is close`, `${driver} is ${min(etaSec)} min away${approx(a)}`),
  leadTime: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'leadTime', 'Start walking now', `${driver} is ${min(etaSec)} min away${approx(a)}`, {}, true),
  slip: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'slip', `${driver} is delayed`, `Traffic — now ${min(etaSec)} min, stay inside${approx(a)}`),
  arrived: (toUid: string, driver: string, spotName: string) =>
    build(toUid, 'arrived', `${driver} has arrived`, `Waiting at ${spotName}`, {}, true),
  lost: (toUid: string, other: string) =>
    build(toUid, 'lost', 'Connection lost', `No location from ${other} for 5 min`),
  timeout: (toUid: string) =>
    build(toUid, 'timeout', 'Trip ended', 'The trip timed out after 3 hours'),
  cancelled: (toUid: string, by: string) =>
    build(toUid, 'cancelled', 'Trip cancelled', `${by} cancelled the pickup`),
  didYouLeave: (toUid: string) =>
    build(toUid, 'didYouLeave', 'Did you leave?', 'No movement detected. Tap to confirm or cancel.'),
  armed: (toUid: string, receiver: string, spotName: string) =>
    build(toUid, 'armed', `${receiver} is waiting`, `Tap when you leave for ${spotName}`),
  noShow: (toUid: string, driver: string) =>
    build(toUid, 'noShow', 'No trip started yet', `${driver} hasn't started driving`),
  runningLate: (toUid: string, driver: string, extraMin: number) =>
    build(toUid, 'runningLate', `${driver} is running late`, `About ${extraMin} more min`),
  reply: (toUid: string, from: string, text: string) =>
    build(toUid, 'reply', from, text),
};

export const replyText: Record<string, (spotName: string) => string> = {
  fiveMore: () => '5 more minutes please',
  takeYourTime: () => 'Take your time',
  atSpot: (spot) => `I'm at ${spot}`,
};
```

- [ ] **Step 4: Run tests**

Run: `cd functions && npx jest test/messages.test.ts`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add functions/src/messages.ts functions/test/messages.test.ts
git commit -m "feat(functions): add push message copy"
```

---

### Task 6: TripEngine (pure alert ladder)

**Files:**
- Create: `functions/src/engine/tripEngine.ts`
- Test: `functions/test/engine/tripEngine.test.ts`

- [ ] **Step 1: Write failing tests**

```ts
// functions/test/engine/tripEngine.test.ts
import { step, EngineInput } from '../../src/engine/tripEngine';
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
```

- [ ] **Step 2: Run to verify failure**

Run: `cd functions && npx jest test/engine/tripEngine.test.ts`
Expected: FAIL — cannot find module.

- [ ] **Step 3: Implement**

```ts
// functions/src/engine/tripEngine.ts
import { Alerts, Eta, Phase, Position, PushMessage, ReceiverView, TripDoc, TripState } from '../types';
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
  /** previous pending (unconfirmed) ETA from smoothing; stored on trip by caller */
  pendingEtaSec?: number;
}

export interface EnginePatch {
  lastPos?: Position;
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

export function step(input: EngineInput): EngineOutput {
  const { trip, position, nowMs, driverName } = input;
  const pushes: PushMessage[] = [];
  const alerts: Alerts = { ...trip.alerts };
  const patch: EnginePatch = { lastPos: position };
  const spot = trip.spot;

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
    const s = smoothEta(trip.eta, input.freshEtaSec, nowMs, input.pendingEtaSec);
    eta = { seconds: s.seconds, updatedAt: nowMs, approximate: !!input.freshEtaApproximate };
    patch.eta = eta;
    patch.pendingEtaSec = s.pending ?? null;
  } else {
    wantsEta = shouldPollEta(trip.lastRoutingCallAt, trip.eta?.seconds ?? 0, nowMs, phase, justEnteredNear);
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
```

- [ ] **Step 4: Run tests**

Run: `cd functions && npx jest test/engine/tripEngine.test.ts`
Expected: PASS (16 tests). If "clears dwell" fails because `alerts.arrivalDwellSince` is `undefined` rather than absent, the `delete` handles it — check the test uses `toBeUndefined()`.

- [ ] **Step 5: Commit**

```bash
git add functions/src/engine/tripEngine.ts functions/test/engine/tripEngine.test.ts
git commit -m "feat(functions): add pure TripEngine alert ladder"
```

---

### Task 7: I/O adapters — Firestore, Google Routes, Push

**Files:**
- Create: `functions/src/io/firestore.ts`, `functions/src/io/routing.ts`, `functions/src/io/push.ts`
- Test: `functions/test/io/routing.test.ts`

- [ ] **Step 1: Firestore helpers**

```ts
// functions/src/io/firestore.ts
import { initializeApp, getApps } from 'firebase-admin/app';
import { getFirestore, Firestore, DocumentReference, CollectionReference } from 'firebase-admin/firestore';
import { PairDoc, SpotDoc, TripDoc, UserDoc, ScheduleDoc, ReplyDoc, Position } from '../types';

if (getApps().length === 0) initializeApp();
export const db: Firestore = getFirestore();

const col = <T>(name: string) => db.collection(name) as CollectionReference<T>;
export const users = () => col<UserDoc>('users');
export const pairs = () => col<PairDoc>('pairs');
export const spots = () => col<SpotDoc>('spots');
export const trips = () => col<TripDoc>('trips');
export const schedules = () => col<ScheduleDoc>('schedules');
export const positions = (tripId: string) => trips().doc(tripId).collection('positions') as CollectionReference<Position & { expireAt: Date }>;
export const replies = (tripId: string) => trips().doc(tripId).collection('replies') as CollectionReference<ReplyDoc>;

export async function getOrThrow<T>(ref: DocumentReference<T>, code: string): Promise<T> {
  const snap = await ref.get();
  if (!snap.exists) throw new Error(code);
  return snap.data() as T;
}

export const now = () => Date.now();
```

- [ ] **Step 2: Routing provider (Google Routes API default, swappable)**

```ts
// functions/src/io/routing.ts
import { defineSecret, defineString } from 'firebase-functions/params';
import { LatLng } from '../types';

export const GOOGLE_ROUTES_KEY = defineSecret('GOOGLE_ROUTES_KEY');
/** 'google' (default) | 'stub'. Add 'valhalla' etc. later by implementing RoutingProvider. */
export const ROUTING_PROVIDER = defineString('ROUTING_PROVIDER', { default: 'google' });

export interface RouteResult { etaSec: number; distanceM: number; polyline: string }
export interface RoutingProvider { directions(from: LatLng, to: LatLng): Promise<RouteResult> }

/** Google Routes API — Compute Routes v2, traffic-aware. 10k free calls/month on the Essentials SKU. */
export class GoogleRoutesProvider implements RoutingProvider {
  constructor(private readonly apiKey: string) {}
  async directions(from: LatLng, to: LatLng): Promise<RouteResult> {
    const res = await fetch('https://routes.googleapis.com/directions/v2:computeRoutes', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'X-Goog-Api-Key': this.apiKey,
        'X-Goog-FieldMask': 'routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline',
      },
      body: JSON.stringify({
        origin: { location: { latLng: { latitude: from.lat, longitude: from.lng } } },
        destination: { location: { latLng: { latitude: to.lat, longitude: to.lng } } },
        travelMode: 'DRIVE',
        routingPreference: 'TRAFFIC_AWARE',
        polylineEncoding: 'ENCODED_POLYLINE',
      }),
    });
    if (!res.ok) throw new Error(`google-routes ${res.status}`);
    const json = (await res.json()) as { routes?: { duration: string; distanceMeters: number; polyline: { encodedPolyline: string } }[] };
    const r = json.routes?.[0];
    if (!r) throw new Error('google-routes no-route');
    return { etaSec: parseDurationSec(r.duration), distanceM: Math.round(r.distanceMeters), polyline: r.polyline.encodedPolyline };
  }
}

/** Google returns durations as "1234s" (or "1234.5s"). */
export function parseDurationSec(d: string): number {
  const n = Number(String(d).replace(/s$/, ''));
  if (!Number.isFinite(n)) throw new Error(`bad duration ${d}`);
  return Math.round(n);
}

/** Test/emulator stub: fixed ETA from ROUTING_STUB_ETA_SEC, distance = eta * 10 m/s. */
export class StubProvider implements RoutingProvider {
  constructor(private readonly etaSec: number) {}
  async directions(): Promise<RouteResult> {
    return { etaSec: this.etaSec, distanceM: this.etaSec * 10, polyline: '??_ibE??_ibE' };
  }
}

export function provider(): RoutingProvider {
  if (process.env.ROUTING_STUB_ETA_SEC) return new StubProvider(Number(process.env.ROUTING_STUB_ETA_SEC));
  switch (ROUTING_PROVIDER.value()) {
    case 'google': return new GoogleRoutesProvider(GOOGLE_ROUTES_KEY.value());
    default: throw new Error(`unknown ROUTING_PROVIDER ${ROUTING_PROVIDER.value()}`);
  }
}

export const directions = (from: LatLng, to: LatLng) => provider().directions(from, to);
```

Test: `functions/test/io/routing.test.ts`
```ts
import { parseDurationSec, StubProvider } from '../../src/io/routing';

describe('routing', () => {
  it('parses Google duration strings', () => {
    expect(parseDurationSec('1234s')).toBe(1234);
    expect(parseDurationSec('1234.6s')).toBe(1235);
    expect(() => parseDurationSec('abc')).toThrow();
  });
  it('stub returns fixed eta', async () => {
    const r = await new StubProvider(170).directions({ lat: 0, lng: 0 }, { lat: 1, lng: 1 });
    expect(r.etaSec).toBe(170);
    expect(r.distanceM).toBe(1700);
  });
});
```

Run: `cd functions && npx jest test/io/routing.test.ts` → PASS (2 tests).

- [ ] **Step 3: Push sender**

```ts
// functions/src/io/push.ts
import { getMessaging } from 'firebase-admin/messaging';
import { FieldValue } from 'firebase-admin/firestore';
import { PushMessage } from '../types';
import { users } from './firestore';
import { logger } from 'firebase-functions';

export async function sendPush(m: PushMessage): Promise<void> {
  const snap = await users().doc(m.toUid).get();
  const tokens = snap.data()?.fcmTokens ?? [];
  if (tokens.length === 0) { logger.warn('no tokens', { uid: m.toUid, kind: m.data.kind }); return; }

  const res = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: m.title, body: m.body },
    data: m.data,
    android: {
      priority: 'high',
      notification: { channelId: m.urgent ? 'sync_urgent' : 'sync_updates', sound: m.urgent ? 'urgent' : 'default' },
    },
    apns: {
      headers: { 'apns-priority': '10', ...(m.urgent ? { 'apns-push-type': 'alert' } : {}) },
      payload: { aps: { sound: m.urgent ? 'urgent.caf' : 'default', 'interruption-level': m.urgent ? 'time-sensitive' : 'active' } },
    },
  });

  const dead = res.responses
    .map((r, i) => (!r.success && r.error?.code === 'messaging/registration-token-not-registered' ? tokens[i] : null))
    .filter((t): t is string => t !== null);
  if (dead.length) await users().doc(m.toUid).update({ fcmTokens: FieldValue.arrayRemove(...dead) });
}

export async function sendAll(msgs: PushMessage[]): Promise<void> {
  await Promise.all(msgs.map(sendPush));
}
```

- [ ] **Step 4: Build**

Run: `cd functions && npm run build`
Expected: exit 0. (Node 20 has global `fetch`; if tsc complains, add `"DOM"` to `lib` in tsconfig.)

- [ ] **Step 5: Commit**

```bash
git add functions/src/io functions/test/io
git commit -m "feat(functions): add Firestore, routing provider (Google Routes) and FCM adapters"
```

---

### Task 8: Callables — pairs, spots, tokens

**Files:**
- Create: `functions/src/callables/pairs.ts`, `functions/src/callables/spots.ts`, `functions/src/callables/tokens.ts`, `functions/src/callables/auth.ts`

- [ ] **Step 1: Shared auth guard**

```ts
// functions/src/callables/auth.ts
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { pairs, getOrThrow } from '../io/firestore';
import { PairDoc } from '../types';

export function uidOf(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'sign-in required');
  return uid;
}

export async function requireActivePair(pairId: string, uid: string): Promise<PairDoc> {
  const pair = await getOrThrow(pairs().doc(pairId), 'not-paired').catch(() => { throw new HttpsError('not-found', 'not-paired'); });
  if (pair.status !== 'active' || !pair.members.includes(uid)) throw new HttpsError('permission-denied', 'not-paired');
  return pair;
}

export function otherMember(pair: PairDoc, uid: string): string {
  const other = pair.members.find((m) => m !== uid);
  if (!other) throw new HttpsError('failed-precondition', 'not-paired');
  return other;
}
```

- [ ] **Step 2: Pairs**

```ts
// functions/src/callables/pairs.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { pairs, now } from '../io/firestore';
import { uidOf } from './auth';
import { PairDoc } from '../types';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
export function randomCode(len = 6): string {
  let s = '';
  for (let i = 0; i < len; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return s;
}

export const createPair = onCall(async (req) => {
  const uid = uidOf(req);
  for (let attempt = 0; attempt < 5; attempt++) {
    const inviteCode = randomCode();
    const clash = await pairs().where('inviteCode', '==', inviteCode).where('status', '==', 'pending').limit(1).get();
    if (!clash.empty) continue;
    const doc: PairDoc = { members: [uid], status: 'pending', inviteCode, createdBy: uid, createdAt: now() };
    const ref = await pairs().add(doc);
    return { pairId: ref.id, inviteCode };
  }
  throw new HttpsError('internal', 'code-collision');
});

export const acceptPair = onCall(async (req) => {
  const uid = uidOf(req);
  const code = String(req.data?.code ?? '').toUpperCase().trim();
  if (code.length !== 6) throw new HttpsError('invalid-argument', 'bad-code');
  const q = await pairs().where('inviteCode', '==', code).where('status', '==', 'pending').limit(1).get();
  if (q.empty) throw new HttpsError('not-found', 'bad-code');
  const snap = q.docs[0];
  const pair = snap.data();
  if (pair.createdBy === uid) throw new HttpsError('failed-precondition', 'own-code');
  await snap.ref.update({ members: [pair.createdBy, uid], status: 'active' });
  return { pairId: snap.id };
});

export const revokePair = onCall(async (req) => {
  const uid = uidOf(req);
  const pairId = String(req.data?.pairId ?? '');
  const ref = pairs().doc(pairId);
  const snap = await ref.get();
  if (!snap.exists || !snap.data()!.members.includes(uid)) throw new HttpsError('permission-denied', 'not-paired');
  await ref.update({ status: 'revoked' });
  return { ok: true };
});
```

- [ ] **Step 3: Spots**

```ts
// functions/src/callables/spots.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { spots, now } from '../io/firestore';
import { uidOf, requireActivePair } from './auth';
import { SpotDoc } from '../types';

export const upsertSpot = onCall(async (req) => {
  const uid = uidOf(req);
  const d = req.data ?? {};
  const pairId = String(d.pairId ?? '');
  await requireActivePair(pairId, uid);
  const lat = Number(d.lat), lng = Number(d.lng);
  if (!Number.isFinite(lat) || !Number.isFinite(lng)) throw new HttpsError('invalid-argument', 'bad-coords');
  const name = String(d.name ?? '').trim().slice(0, 40);
  if (!name) throw new HttpsError('invalid-argument', 'bad-name');
  const leadTimeMin = Math.min(30, Math.max(1, Math.round(Number(d.leadTimeMin ?? 3))));
  const radiusM = Math.min(500, Math.max(50, Math.round(Number(d.radiusM ?? 100))));

  if (d.spotId) {
    const ref = spots().doc(String(d.spotId));
    const snap = await ref.get();
    if (!snap.exists || snap.data()!.pairId !== pairId) throw new HttpsError('not-found', 'spot-not-found');
    await ref.update({ name, lat, lng, leadTimeMin, radiusM });
    return { spotId: ref.id };
  }
  const doc: SpotDoc = { pairId, name, lat, lng, radiusM, leadTimeMin, createdBy: uid, createdAt: now() };
  const ref = await spots().add(doc);
  return { spotId: ref.id };
});

export const deleteSpot = onCall(async (req) => {
  const uid = uidOf(req);
  const ref = spots().doc(String(req.data?.spotId ?? ''));
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'spot-not-found');
  await requireActivePair(snap.data()!.pairId, uid);
  await ref.delete();
  return { ok: true };
});
```

- [ ] **Step 4: Tokens**

```ts
// functions/src/callables/tokens.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { users, now } from '../io/firestore';
import { uidOf } from './auth';

export const registerPushToken = onCall(async (req) => {
  const uid = uidOf(req);
  const token = String(req.data?.token ?? '');
  const platform = req.data?.platform === 'android' ? 'android' : 'ios';
  const displayName = String(req.data?.displayName ?? '').trim().slice(0, 30);
  if (token.length < 20) throw new HttpsError('invalid-argument', 'bad-token');
  const ref = users().doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({ phone: req.auth?.token.phone_number ?? '', displayName: displayName || 'Someone', platform, fcmTokens: [token], createdAt: now() });
  } else {
    await ref.update({ fcmTokens: FieldValue.arrayUnion(token), platform, ...(displayName ? { displayName } : {}) });
  }
  return { ok: true };
});

export const setLowBattery = onCall(async (req) => {
  const uid = uidOf(req);
  await users().doc(uid).update({ lowBattery: !!req.data?.lowBattery });
  return { ok: true };
});
```

- [ ] **Step 5: Build and commit**

Run: `cd functions && npm run build` → exit 0.

```bash
git add functions/src/callables
git commit -m "feat(functions): add pair, spot and token callables"
```

---

### Task 9: Trip callables

**Files:**
- Create: `functions/src/callables/trips.ts`

- [ ] **Step 1: Implement**

```ts
// functions/src/callables/trips.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { logger } from 'firebase-functions';
import { trips, spots, users, replies, now } from '../io/firestore';
import { directions, GOOGLE_ROUTES_KEY, ROUTING_PROVIDER } from '../io/routing';
import { sendPush } from '../io/push';
import { uidOf, requireActivePair, otherMember } from './auth';
import { bandsFor, fallbackEtaSec } from '../engine/eta';
import { haversineMeters } from '../engine/geo';
import { msg, replyText } from '../messages';
import { TripDoc, initialAlerts, ReplyKind } from '../types';

async function activeTripFor(pairId: string) {
  const q = await trips().where('pairId', '==', pairId).where('state', 'in', ['armed', 'driving']).limit(1).get();
  return q.empty ? null : q.docs[0];
}

async function nameOf(uid: string): Promise<string> {
  return (await users().doc(uid).get()).data()?.displayName ?? 'Your driver';
}

export const startTrip = onCall({ secrets: [GOOGLE_ROUTES_KEY] }, async (req) => {
  const uid = uidOf(req);
  const spotId = String(req.data?.spotId ?? '');
  const from = { lat: Number(req.data?.lat), lng: Number(req.data?.lng) };
  if (!Number.isFinite(from.lat) || !Number.isFinite(from.lng)) throw new HttpsError('invalid-argument', 'bad-coords');
  const spotSnap = await spots().doc(spotId).get();
  if (!spotSnap.exists) throw new HttpsError('not-found', 'spot-not-found');
  const spot = spotSnap.data()!;
  const pair = await requireActivePair(spot.pairId, uid);
  const receiverUid = otherMember(pair, uid);

  const existing = await activeTripFor(spot.pairId);
  if (existing && existing.data().state === 'driving') {
    return { tripId: existing.id, bands: existing.data().bands, etaSeconds: existing.data().eta?.seconds, existing: true };
  }

  const t = now();
  let etaSec: number, distanceM: number, polyline: string | undefined, approximate = false;
  try {
    // Always fetch the route at start (we need the polyline for bands), even if the client sent its own ETA.
    const r = await directions(from, spot);
    etaSec = r.etaSec; distanceM = r.distanceM; polyline = r.polyline;
    const clientEta = Number(req.data?.etaSec);
    if (Number.isFinite(clientEta) && clientEta > 0) etaSec = Math.round(clientEta); // trust on-device (MapKit) ETA when present
  } catch (e) {
    logger.error('routing failed at start', { provider: ROUTING_PROVIDER.value(), err: String(e) });
    distanceM = haversineMeters(from, spot) * 1.3;
    etaSec = fallbackEtaSec(distanceM, 10);
    approximate = true;
  }
  const bands = bandsFor(distanceM, etaSec, spot.leadTimeMin);
  const driverName = await nameOf(uid);

  const doc: TripDoc = {
    pairId: spot.pairId, driverUid: uid, receiverUid, spotId,
    spot: { lat: spot.lat, lng: spot.lng, radiusM: spot.radiusM, name: spot.name },
    leadTimeMin: spot.leadTimeMin, state: 'driving', createdAt: t, startedAt: t, startPos: from,
    eta: { seconds: etaSec, updatedAt: t, approximate }, routePolyline: polyline, routeDistanceM: Math.round(distanceM),
    bands, alerts: { ...initialAlerts(), started: true }, fuzzy: !!req.data?.fuzzy,
    lastRoutingCallAt: t, routingCalls: approximate ? 0 : 1, phaseHint: 'far',
    receiverView: { etaSeconds: etaSec, progressPct: 0, ...(req.data?.fuzzy ? {} : { lastPos: from }) },
  };

  let tripId: string;
  if (existing) { // armed → driving
    await existing.ref.set(doc, { merge: true });
    tripId = existing.id;
  } else {
    tripId = (await trips().add(doc)).id;
  }
  await sendPush(msg.started(receiverUid, driverName, etaSec, spot.name, approximate));
  return { tripId, bands, etaSeconds: etaSec, existing: false };
});

export const endTrip = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const reason = req.data?.reason === 'arrived' ? 'arrived' : 'cancelled';
  const ref = trips().doc(tripId);
  const snap = await ref.get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid && trip.receiverUid !== uid) throw new HttpsError('permission-denied', 'not-paired');
  if (!['armed', 'driving'].includes(trip.state)) return { ok: true, alreadyEnded: true };
  await ref.update({ state: reason, endedAt: now(), 'alerts.arrived': reason === 'arrived' });
  const name = await nameOf(uid);
  const other = uid === trip.driverUid ? trip.receiverUid : trip.driverUid;
  await sendPush(reason === 'arrived' ? msg.arrived(trip.receiverUid, name, trip.spot.name) : msg.cancelled(other, name));
  return { ok: true };
});

export const armTrip = onCall(async (req) => {
  const uid = uidOf(req);
  const spotId = String(req.data?.spotId ?? '');
  const spotSnap = await spots().doc(spotId).get();
  if (!spotSnap.exists) throw new HttpsError('not-found', 'spot-not-found');
  const spot = spotSnap.data()!;
  const pair = await requireActivePair(spot.pairId, uid);
  const driverUid = otherMember(pair, uid);
  const existing = await activeTripFor(spot.pairId);
  if (existing) throw new HttpsError('already-exists', 'trip-active');
  const t = now();
  const neededBy = Number.isFinite(Number(req.data?.neededBy)) ? Number(req.data.neededBy) : undefined;
  const doc: TripDoc = {
    pairId: spot.pairId, driverUid, receiverUid: uid, spotId,
    spot: { lat: spot.lat, lng: spot.lng, radiusM: spot.radiusM, name: spot.name },
    leadTimeMin: spot.leadTimeMin, state: 'armed', createdAt: t, alerts: initialAlerts(), fuzzy: false,
    routingCalls: 0, phaseHint: 'far', ...(neededBy ? { neededBy } : {}),
  };
  const ref = await trips().add(doc);
  await sendPush(msg.armed(driverUid, await nameOf(uid), spot.name));
  return { tripId: ref.id };
});

export const sendReply = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const kind = String(req.data?.kind ?? 'custom') as ReplyKind;
  const snap = await trips().doc(tripId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid && trip.receiverUid !== uid) throw new HttpsError('permission-denied', 'not-paired');
  const text = kind === 'custom' ? String(req.data?.text ?? '').trim().slice(0, 140) : (replyText[kind]?.(trip.spot.name) ?? '');
  if (!text) throw new HttpsError('invalid-argument', 'bad-reply');
  await replies(tripId).add({ fromUid: uid, kind, text, ts: now() });
  const other = uid === trip.driverUid ? trip.receiverUid : trip.driverUid;
  await sendPush(msg.reply(other, await nameOf(uid), text));
  return { ok: true };
});

export const setRunningLate = onCall(async (req) => {
  const uid = uidOf(req);
  const tripId = String(req.data?.tripId ?? '');
  const extraMin = Math.min(60, Math.max(1, Math.round(Number(req.data?.extraMin ?? 5))));
  const snap = await trips().doc(tripId).get();
  if (!snap.exists) throw new HttpsError('not-found', 'trip-not-found');
  const trip = snap.data()!;
  if (trip.driverUid !== uid) throw new HttpsError('permission-denied', 'driver-only');
  await replies(tripId).add({ fromUid: uid, kind: 'runningLate', text: `About ${extraMin} more min`, ts: now() });
  await sendPush(msg.runningLate(trip.receiverUid, await nameOf(uid), extraMin));
  return { ok: true };
});
```

- [ ] **Step 2: Build and commit**

Run: `cd functions && npm run build` → exit 0.

```bash
git add functions/src/callables/trips.ts
git commit -m "feat(functions): add trip lifecycle callables"
```

---

### Task 10: Position trigger

**Files:**
- Create: `functions/src/triggers/onPositionWrite.ts`

- [ ] **Step 1: Implement**

```ts
// functions/src/triggers/onPositionWrite.ts
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { logger } from 'firebase-functions';
import { FieldValue } from 'firebase-admin/firestore';
import { db, trips, users } from '../io/firestore';
import { directions, GOOGLE_ROUTES_KEY, ROUTING_PROVIDER } from '../io/routing';
import { sendAll } from '../io/push';
import { step, EnginePatch } from '../engine/tripEngine';
import { fallbackEtaSec } from '../engine/eta';
import { decodePolyline, polylineRemainingMeters, haversineMeters } from '../engine/geo';
import { Position, TripDoc } from '../types';

function toUpdate(p: EnginePatch, extra: Record<string, unknown> = {}): Record<string, unknown> {
  const u: Record<string, unknown> = { ...extra };
  if (p.lastPos) u.lastPos = p.lastPos;
  if (p.phaseHint) u.phaseHint = p.phaseHint;
  if (p.eta) u.eta = p.eta;
  if (p.pendingEtaSec !== undefined) u.pendingEtaSec = p.pendingEtaSec === null ? FieldValue.delete() : p.pendingEtaSec;
  if (p.alerts) u.alerts = p.alerts;
  if (p.state) u.state = p.state;
  if (p.endedAt) u.endedAt = p.endedAt;
  if (p.receiverView) u.receiverView = p.receiverView;
  return u;
}

export const onPositionWrite = onDocumentCreated(
  { document: 'trips/{tripId}/positions/{posId}', secrets: [GOOGLE_ROUTES_KEY] },
  async (event) => {
    const tripId = event.params.tripId;
    const position = event.data?.data() as Position | undefined;
    if (!position) return;
    const ref = trips().doc(tripId);
    const snap = await ref.get();
    if (!snap.exists) return;
    const trip = snap.data() as TripDoc & { pendingEtaSec?: number };
    if (trip.state !== 'driving') return;
    if (trip.lastPos && position.ts <= trip.lastPos.ts) return; // out-of-order replay

    const driver = (await users().doc(trip.driverUid).get()).data();
    const driverName = driver?.displayName ?? 'Your driver';
    const nowMs = Date.now();

    // Pass 1: no ETA → engine tells us whether to fetch one.
    let out = step({ trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec });
    let extra: Record<string, unknown> = {};

    // On-device ETA (iOS MapKit) present → use it, no routing call at all.
    const clientEta = position.etaSec;
    if (clientEta !== undefined && Number.isFinite(clientEta) && clientEta > 0) {
      out = step({ trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec, freshEtaSec: Math.round(clientEta), freshEtaApproximate: !!driver?.lowBattery });
      extra = { lastRoutingCallAt: nowMs }; // counts as a poll for throttling purposes
    } else if (out.wantsEta) {
      let freshEtaSec: number, approximate = false;
      try {
        const r = await directions(position, trip.spot);
        freshEtaSec = r.etaSec;
        extra = { lastRoutingCallAt: nowMs, routingCalls: FieldValue.increment(1) };
        // keep polyline fresh so remaining-distance fallback stays meaningful
        extra.routePolyline = r.polyline;
      } catch (e) {
        logger.warn('routing failed; using fallback', { tripId, err: String(e) });
        const remaining = trip.routePolyline
          ? polylineRemainingMeters(decodePolyline(trip.routePolyline), position)
          : haversineMeters(position, trip.spot) * 1.3;
        const avgSpeed = trip.lastPos && position.ts > trip.lastPos.ts
          ? haversineMeters(position, trip.lastPos) / ((position.ts - trip.lastPos.ts) / 1000)
          : position.speedMps;
        freshEtaSec = fallbackEtaSec(remaining, avgSpeed);
        approximate = true;
        extra = { lastRoutingCallAt: nowMs };
      }
      if (driver?.lowBattery) approximate = true;
      out = step({ trip, position, nowMs, driverName, pendingEtaSec: trip.pendingEtaSec, freshEtaSec, freshEtaApproximate: approximate });
    }

    // Idempotency: re-read alerts inside a transaction and drop pushes already sent.
    const pushes = await db.runTransaction(async (tx) => {
      const fresh = (await tx.get(ref)).data() as TripDoc;
      if (fresh.state !== 'driving') return [];
      const already = fresh.alerts;
      const keep = out.pushes.filter((p) => {
        const k = p.data.kind;
        if (k === 'tenMin') return !already.tenMin;
        if (k === 'leadTime') return !already.leadTime;
        if (k === 'arrived') return !already.arrived;
        if (k === 'didYouLeave') return !already.didYouLeave;
        if (k === 'slip') return (out.patch.alerts?.slipCount ?? 0) > already.slipCount;
        return true;
      });
      tx.update(ref, toUpdate(out.patch, extra));
      return keep;
    });

    await sendAll(pushes);
  },
);
```

- [ ] **Step 2: Build and commit**

Run: `cd functions && npm run build` → exit 0.

```bash
git add functions/src/triggers/onPositionWrite.ts
git commit -m "feat(functions): add position trigger wiring TripEngine to routing and FCM"
```

---

### Task 11: Housekeeping scheduler (lost / timeout / no-show)

**Files:**
- Create: `functions/src/triggers/housekeeping.ts`

- [ ] **Step 1: Implement**

```ts
// functions/src/triggers/housekeeping.ts
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { trips, users } from '../io/firestore';
import { sendPush } from '../io/push';
import { msg } from '../messages';

const LOST_MS = 5 * 60_000;
const TIMEOUT_MS = 3 * 60 * 60_000;
const NO_SHOW_MS = 15 * 60_000;

async function nameOf(uid: string) { return (await users().doc(uid).get()).data()?.displayName ?? 'Your driver'; }

export const housekeeping = onSchedule('every 1 minutes', async () => {
  const now = Date.now();

  const driving = await trips().where('state', '==', 'driving').get();
  for (const d of driving.docs) {
    const t = d.data();
    const started = t.startedAt ?? t.createdAt;
    if (now - started > TIMEOUT_MS) {
      await d.ref.update({ state: 'timeout', endedAt: now });
      await Promise.all([sendPush(msg.timeout(t.driverUid)), sendPush(msg.timeout(t.receiverUid))]);
      continue;
    }
    const lastTs = t.lastPos?.ts ?? started;
    if (now - lastTs > LOST_MS && !t.lostNotified) {
      await d.ref.update({ state: 'lost', lostNotified: true });
      const [dn, rn] = await Promise.all([nameOf(t.driverUid), nameOf(t.receiverUid)]);
      await Promise.all([sendPush(msg.lost(t.receiverUid, dn)), sendPush(msg.lost(t.driverUid, rn))]);
    }
  }

  // lost → driving again if positions resumed (position trigger ignores non-driving, so resume here)
  const lost = await trips().where('state', '==', 'lost').get();
  for (const d of lost.docs) {
    const t = d.data();
    const started = t.startedAt ?? t.createdAt;
    if (now - started > TIMEOUT_MS) { await d.ref.update({ state: 'timeout', endedAt: now }); continue; }
    const latest = await d.ref.collection('positions').orderBy('ts', 'desc').limit(1).get();
    const ts = latest.empty ? 0 : (latest.docs[0].data().ts as number);
    if (now - ts <= LOST_MS) await d.ref.update({ state: 'driving', lostNotified: false });
  }

  const armed = await trips().where('state', '==', 'armed').get();
  for (const d of armed.docs) {
    const t = d.data();
    if (t.noShowNotified) continue;
    const deadline = (t.neededBy ?? t.createdAt) + NO_SHOW_MS;
    if (now > deadline) {
      await d.ref.update({ noShowNotified: true });
      await sendPush(msg.noShow(t.receiverUid, await nameOf(t.driverUid)));
    }
    if (now - t.createdAt > TIMEOUT_MS) await d.ref.update({ state: 'timeout', endedAt: now });
  }
});
```

- [ ] **Step 2: Build and commit**

Run: `cd functions && npm run build` → exit 0.

```bash
git add functions/src/triggers/housekeeping.ts
git commit -m "feat(functions): add lost/timeout/no-show housekeeping scheduler"
```

---

### Task 12: Exports, security rules

**Files:**
- Modify: `functions/src/index.ts`
- Create: `firestore.rules`

- [ ] **Step 1: Export everything**

```ts
// functions/src/index.ts
export { createPair, acceptPair, revokePair } from './callables/pairs';
export { upsertSpot, deleteSpot } from './callables/spots';
export { registerPushToken, setLowBattery } from './callables/tokens';
export { startTrip, endTrip, armTrip, sendReply, setRunningLate } from './callables/trips';
export { onPositionWrite } from './triggers/onPositionWrite';
export { housekeeping } from './triggers/housekeeping';
```

- [ ] **Step 2: Security rules**

```
// firestore.rules
rules_version = '2';
service cloud.firestore {
  match /databases/{db}/documents {
    function signedIn() { return request.auth != null; }
    function uid() { return request.auth.uid; }
    function isMember(pairId) {
      return signedIn() && uid() in get(/databases/$(db)/documents/pairs/$(pairId)).data.members;
    }

    match /users/{userId} {
      allow read: if signedIn() && uid() == userId;
      allow write: if false; // via callables only
    }

    match /pairs/{pairId} {
      allow read: if signedIn() && uid() in resource.data.members;
      allow write: if false;
    }

    match /spots/{spotId} {
      allow read: if isMember(resource.data.pairId);
      allow write: if false;
    }

    match /trips/{tripId} {
      allow read: if signedIn() && (uid() == resource.data.driverUid || uid() == resource.data.receiverUid);
      allow write: if false;

      match /positions/{posId} {
        allow create: if signedIn()
          && uid() == get(/databases/$(db)/documents/trips/$(tripId)).data.driverUid
          && request.resource.data.keys().hasAll(['lat','lng','accuracyM','speedMps','ts','expireAt'])
          && request.resource.data.lat is number && request.resource.data.lng is number
          && request.resource.data.accuracyM is number && request.resource.data.speedMps is number
          && request.resource.data.ts is number && request.resource.data.expireAt is timestamp
          && (!('etaSec' in request.resource.data) || request.resource.data.etaSec is number);
        allow read: if signedIn() && (
          uid() == get(/databases/$(db)/documents/trips/$(tripId)).data.driverUid ||
          uid() == get(/databases/$(db)/documents/trips/$(tripId)).data.receiverUid);
        allow update, delete: if false;
      }

      match /replies/{replyId} {
        allow read: if signedIn() && (
          uid() == get(/databases/$(db)/documents/trips/$(tripId)).data.driverUid ||
          uid() == get(/databases/$(db)/documents/trips/$(tripId)).data.receiverUid);
        allow write: if false;
      }
    }

    match /schedules/{id} {
      allow read: if isMember(resource.data.pairId);
      allow write: if false;
    }
  }
}
```

- [ ] **Step 3: Build, run all unit tests**

Run: `cd functions && npm run build && npm test`
Expected: all suites PASS (geo 6, eta 13, messages 4, routing 2, tripEngine 16).

- [ ] **Step 4: Commit**

```bash
git add functions/src/index.ts firestore.rules
git commit -m "feat(functions): export functions and add Firestore security rules"
```

---

### Task 13: Emulator integration test for trip → position → alerts

**Files:**
- Create: `functions/test/callables/trips.emulator.test.ts`

- [ ] **Step 1: Write the emulator test (engine-through-Firestore, routing stubbed via env)**

```ts
// functions/test/callables/trips.emulator.test.ts
// Runs only under: npm run test:emu  (FIRESTORE_EMULATOR_HOST set by emulators:exec)
process.env.GCLOUD_PROJECT = 'fin-e8358';
process.env.ROUTING_STUB_ETA_SEC = '170';

import { db, trips, users, pairs, spots } from '../../src/io/firestore';
import { directions } from '../../src/io/routing';
import { step } from '../../src/engine/tripEngine';
import { initialAlerts, TripDoc } from '../../src/types';

const T0 = 1_700_000_000_000;

describe('trip flow against the Firestore emulator', () => {
  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });

  it('routing is stubbed', async () => {
    expect((await directions({ lat: 0, lng: 0 }, { lat: 1, lng: 1 })).etaSec).toBe(170);
  });

  it('creates pair, spot, trip and applies an engine patch transactionally', async () => {
    await users().doc('d').set({ phone: '+1', displayName: 'Mostafi', platform: 'ios', fcmTokens: [], createdAt: T0 });
    await users().doc('r').set({ phone: '+2', displayName: 'Sara', platform: 'android', fcmTokens: [], createdAt: T0 });
    const pair = await pairs().add({ members: ['d', 'r'], status: 'active', inviteCode: 'ABC234', createdBy: 'd', createdAt: T0 });
    const spot = await spots().add({ pairId: pair.id, name: 'Office', lat: 0, lng: 0, radiusM: 100, leadTimeMin: 3, createdBy: 'r', createdAt: T0 });

    const trip: TripDoc = {
      pairId: pair.id, driverUid: 'd', receiverUid: 'r', spotId: spot.id,
      spot: { lat: 0, lng: 0, radiusM: 100, name: 'Office' }, leadTimeMin: 3, state: 'driving',
      createdAt: T0, startedAt: T0, startPos: { lat: 0.1, lng: 0 },
      eta: { seconds: 1200, updatedAt: T0, approximate: false }, routeDistanceM: 11_000,
      bands: { far: 6600, near: 3850, lead: 2750 }, alerts: initialAlerts(), fuzzy: false,
      routingCalls: 1, lastRoutingCallAt: T0, phaseHint: 'far',
    };
    const ref = await trips().add(trip);

    const out = step({ trip, position: { lat: 0.02, lng: 0, accuracyM: 10, speedMps: 12, ts: T0 + 60_000 }, nowMs: T0 + 60_000, driverName: 'Mostafi', freshEtaSec: 170 });
    expect(out.pushes.map(p => p.data.kind)).toEqual(['tenMin', 'leadTime']);

    await db.runTransaction(async (tx) => { tx.update(ref, { alerts: out.patch.alerts, eta: out.patch.eta, phaseHint: out.patch.phaseHint ?? 'far' }); });
    const saved = (await ref.get()).data()!;
    expect(saved.alerts.leadTime).toBe(true);
    expect(saved.eta?.seconds).toBe(170);
    expect(saved.phaseHint).toBe('near');
  });
});
```

- [ ] **Step 2: Run**

Run: `cd functions && npm run build && npm run test:emu`
Expected: emulator starts, 2 tests PASS, emulator stops. (Requires `npm i -g firebase-tools` and Java for the Firestore emulator.)

- [ ] **Step 3: Commit**

```bash
git add functions/test/callables/trips.emulator.test.ts
git commit -m "test(functions): add Firestore emulator integration test"
```

---

### Task 14: Deploy checklist and real-drive checklist

**Files:**
- Create: `docs/testing/real-drive-checklist.md`, `functions/README.md`

- [ ] **Step 1: Write functions README**

```markdown
# The Sync — Cloud Functions

## One-time setup
1. `npm i -g firebase-tools && firebase login`
2. `firebase projects:create fin-e8358` (or pick an id) and put it in `.firebaserc`.
3. Enable in console: Authentication → Phone; Firestore (production mode); Cloud Messaging. Upload APNs key under Cloud Messaging → Apple app configuration (after the iOS app exists).
4. Upgrade to Blaze (required for outbound HTTP calls; free quotas still apply).
5. Google Routes API key: in Google Cloud console for project `fin-e8358` → APIs & Services → enable **Routes API** → Credentials → Create API key → restrict it to "Routes API" only. Then `firebase functions:secrets:set GOOGLE_ROUTES_KEY --project fin-e8358` and paste it. Free tier: 10,000 Compute Routes calls/month.
6. Optional: `ROUTING_PROVIDER` param (default `google`) — future providers (self-hosted Valhalla, etc.) implement `RoutingProvider` in `src/io/routing.ts`.

## Dev loop
- `npm test` — unit tests (pure engine).
- `npm run test:emu` — emulator integration test.
- `npm run serve` — local emulators with functions.
- `npm run deploy` — deploy functions + rules + indexes.

## Contract for native clients (M1)
- Sign in with phone (Firebase Auth). Call `registerPushToken({token, platform, displayName})` after login and on token refresh.
- Pair: `createPair()` → show `inviteCode`; other side `acceptPair({code})`.
- Spots: `upsertSpot({pairId, name, lat, lng, leadTimeMin, radiusM, spotId?})`, `deleteSpot({spotId})`. Listen to `spots where pairId ==`.
- Driver start: `startTrip({spotId, lat, lng, fuzzy?, etaSec?})` → `{tripId, bands, etaSeconds}`. Then write `trips/{tripId}/positions` docs `{lat,lng,accuracyM,speedMps,ts(ms),expireAt(Timestamp now+30d), etaSec?}`. **iOS: compute `etaSec` on-device with `MKDirections.calculateETA` (free, traffic-aware) and include it — the server then makes zero routing calls for that trip.** Android omits it; 200 m filter in far phase, every 5 s in near phase. Switch to near when `trips/{tripId}.phaseHint == 'near'` or straight-line distance ≤ `bands.near`.
- Stop tracking when `trips/{tripId}.state` leaves `driving`. Call `endTrip({tripId, reason:'arrived'|'cancelled'})` from the UI.
- Receiver: listen to `trips where pairId == and state in [armed,driving]`; render `receiverView`. Quick replies: `sendReply({tripId, kind, text?})`. Driver: `setRunningLate({tripId, extraMin})`.
- Push `data.kind` values: started, tenMin, leadTime (urgent channel `sync_urgent`), slip, arrived, lost, timeout, cancelled, didYouLeave, armed, noShow, runningLate, reply.
```

- [ ] **Step 2: Write real-drive checklist**

```markdown
# Real-drive checklist (run per milestone on a real pickup)

Setup: two phones, paired, spot = receiver's pickup point, leadTimeMin = 3.

- [ ] Driver taps "I'm coming" with app open → receiver gets "started" within 5 s with a sane ETA.
- [ ] Driver locks phone / switches to Google Maps → positions keep arriving (check Firestore console) every ≤ 60 s in far phase.
- [ ] `phaseHint` flips to `near` roughly 7 min out; positions every ~5 s after.
- [ ] "10 min away" arrives between 9:30 and 10:30 of actual remaining time.
- [ ] "Start walking now" arrives at 3 min ±30 s; receiver actually reaches the spot before the car.
- [ ] Simulate traffic (pull over 3 min after the 10-min alert) → "delayed, stay inside" arrives; resume → no duplicate lead alert unless ETA went above 5 min.
- [ ] Arrive and stop → "arrived" within 30 s; tracking indicator disappears on driver phone.
- [ ] Airplane mode on driver for 6 min mid-trip → both get "Connection lost"; turn off → trip resumes within 2 min.
- [ ] Tap "I'm coming" and don't move for 3 min → driver gets "Did you leave?".
- [ ] Battery used by driver phone over the trip ≤ 3 %.
- [ ] Routing calls for the trip (trips/{id}.routingCalls) ≤ 20 on Android; 0–1 on iOS with on-device ETA.
```

- [ ] **Step 3: Commit**

```bash
git add docs/testing/real-drive-checklist.md functions/README.md
git commit -m "docs: add functions README and real-drive checklist"
```

---

## Self-review against the spec

- §2 data model → Task 2 (types) incl. `phaseHint`, `receiverView`, `leadTimeMin` snapshot. `schedules` typed but not used in M1 (M3 plan).
- §3 callables: createPair/acceptPair/revokePair (T8), upsertSpot/deleteSpot (T8), startTrip/armTrip/endTrip/sendReply/setRunningLate (T9), registerPushToken (T8). `setNeededBy`, `registerLiveActivityToken`, `deleteAccount` → M2/M3/M4 plans. `onSchedule`/`onLeaveBy` → M3 plan.
- §3 TripEngine: smoothing, movement verification, tenMin/leadTime/slip/re-arm/arrived, low battery, fallback ETA, client-supplied ETA bypass → T4, T6, T10.
- §3 housekeeping: lost (5 min), timeout (3 h), armed no-show (15 min) → T11.
- §4 bands/phase handoff via `phaseHint` → T6 + README contract.
- §8 rules: clients write only `positions` → T12.
- §9 errors: typed codes `not-paired`, `trip-active`, `spot-not-found` → T8/T9; token pruning → T7; offline replay ordering → T10 (`ts` guard).
- §10 tests: engine table-driven (T6), emulator (T13), real-drive checklist (T14).

Type consistency check: `step`/`EngineInput`/`EnginePatch` names match between T6 and T10; `msg.*` signatures match between T5, T6, T9, T11; `bandsFor(distance, eta, leadTimeMin)` matches T4 and T9.
