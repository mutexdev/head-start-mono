// functions/src/index.ts
import { setGlobalOptions } from 'firebase-functions/v2';

// Region is pinned so callable URLs are deterministic in the emulator:
//   http://127.0.0.1:5001/fin-e8358/us-central1/<name>
// Both client platforms hard-code that base URL.
//
// This MUST run before any onCall/onRequest is constructed — the options are
// captured at definition time. `export ... from` compiles to a require() that
// TypeScript emits at this statement's position, i.e. AFTER the call above;
// verified by inspecting lib/index.js.
setGlobalOptions({ region: 'us-central1', maxInstances: 10 });

// The twelve M1 callables (CLIENT_CONTRACT_ADDENDUM.md section A).
export { createPair, acceptPair, revokePair } from './callables/pairs';
export { upsertSpot, deleteSpot } from './callables/spots';
export { registerPushToken, setLowBattery } from './callables/tokens';
export { startTrip, endTrip, armTrip, sendReply, setRunningLate } from './callables/trips';

// Triggers. `housekeeping` is deliberately NOT emulated (firebase-tools maps
// onSchedule to a Pub/Sub topic and logs "function ignored because the pubsub
// emulator does not exist or is not running" — that line is EXPECTED locally);
// debugRunHousekeeping runs the same body with an injectable clock and 404s
// outside the emulator.
export { onPositionWrite } from './triggers/onPositionWrite';
export { housekeeping } from './triggers/housekeeping';
export { debugRunHousekeeping, debugPing } from './triggers/debug';
