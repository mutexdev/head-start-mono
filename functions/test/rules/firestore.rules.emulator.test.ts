// functions/test/rules/firestore.rules.emulator.test.ts
//
// The rules are the enforcement point for the ONE thing clients may write
// (CLIENT_CONTRACT.md: `trips/{tripId}/positions/{autoId}`, driver only, exact
// field set) and for the emulator push sink both client apps subscribe to. The
// plan doc has no equivalent suite; this is it.
//
// Runs only under: npm run test:emu  (jest.emulator.config.js, maxWorkers 1).
import { readFileSync } from 'fs';
import * as path from 'path';
import {
  initializeTestEnvironment,
  RulesTestEnvironment,
  assertFails,
  assertSucceeds,
} from '@firebase/rules-unit-testing';
import {
  doc, setDoc, getDoc, addDoc, deleteDoc, updateDoc,
  collection, getDocs, query, where, orderBy, Timestamp,
} from 'firebase/firestore';

const PROJECT_ID = 'fin-e8358';
const DRIVER = 'driverUid1';
const RECEIVER = 'receiverUid1';
const STRANGER = 'strangerUid1';
const T0 = 1_700_000_000_000;

let env: RulesTestEnvironment;

/** A well-formed position document: exactly the contract's seven keys. */
const goodPosition = () => ({
  lat: 37.4,
  lng: -122.1,
  accuracyM: 8,
  speedMps: 12.5,
  ts: T0,
  expireAt: Timestamp.fromMillis(T0 + 30 * 24 * 3600 * 1000),
  etaSec: 420,
});

beforeAll(async () => {
  const rules = readFileSync(path.resolve(__dirname, '../../../firestore.rules'), 'utf8');
  env = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: { host: '127.0.0.1', port: 8080, rules },
  });
});

afterAll(async () => { if (env) await env.cleanup(); });

beforeEach(async () => {
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'pairs/p1'), {
      members: [DRIVER, RECEIVER], status: 'active', inviteCode: 'AAA111',
      createdBy: DRIVER, createdAt: T0, memberNames: { [DRIVER]: 'Mostafi', [RECEIVER]: 'Sara' },
    });
    await setDoc(doc(db, 'pairs/p2'), {
      members: [STRANGER, 'someoneElse'], status: 'active', inviteCode: 'BBB222',
      createdBy: STRANGER, createdAt: T0, memberNames: { [STRANGER]: 'Stranger', someoneElse: 'Nobody' },
    });
    await setDoc(doc(db, 'users/' + DRIVER), {
      phone: '+15550001111', displayName: 'Mostafi', platform: 'ios', fcmTokens: [], createdAt: T0,
    });
    await setDoc(doc(db, 'spots/s1'), {
      pairId: 'p1', name: 'School gate', lat: 37.42, lng: -122.08,
      radiusM: 100, leadTimeMin: 3, createdBy: RECEIVER, createdAt: T0,
    });
    await setDoc(doc(db, 'trips/t1'), {
      pairId: 'p1', driverUid: DRIVER, receiverUid: RECEIVER, spotId: 's1',
      spot: { lat: 37.42, lng: -122.08, radiusM: 100, name: 'School gate' },
      leadTimeMin: 3, state: 'driving', createdAt: T0, startedAt: T0,
      alerts: { started: true, tenMin: false, leadTime: false, arrived: false, didYouLeave: false, slipCount: 0 },
      fuzzy: false, routingCalls: 1, phaseHint: 'far',
    });
    await setDoc(doc(db, 'trips/t1/replies/r1'), { fromUid: RECEIVER, kind: 'atSpot', text: "I'm at School gate", ts: T0 });
    await setDoc(doc(db, '_debugPushes/dp1'), {
      toUid: DRIVER, kind: 'reply', title: 'Sara', body: "I'm at School gate", urgent: false,
      data: { kind: 'reply', tripId: 't1' }, androidChannelId: 'sync_updates',
      apnsInterruptionLevel: 'active', tokens: [], sentAt: T0, delivered: false,
    });
    await setDoc(doc(db, '_debugPushes/dp2'), {
      toUid: RECEIVER, kind: 'leadTime', title: 'Start walking now', body: 'Mostafi is 3 min away', urgent: true,
      data: { kind: 'leadTime', tripId: 't1' }, androidChannelId: 'sync_urgent',
      apnsInterruptionLevel: 'time-sensitive', tokens: [], sentAt: T0 + 1, delivered: false,
    });
  });
});

const asDriver = () => env.authenticatedContext(DRIVER).firestore();
const asReceiver = () => env.authenticatedContext(RECEIVER).firestore();
const asStranger = () => env.authenticatedContext(STRANGER).firestore();
const asAnon = () => env.unauthenticatedContext().firestore();

describe('positions — the one client-writable path', () => {
  it('(a) the trip driver CAN create a well-formed positions document', async () => {
    await assertSucceeds(addDoc(collection(asDriver(), 'trips/t1/positions'), goodPosition()));
  });

  it('(a2) etaSec is optional — six keys is also well formed', async () => {
    const { etaSec, ...noEta } = goodPosition();
    void etaSec;
    await assertSucceeds(addDoc(collection(asDriver(), 'trips/t1/positions'), noEta));
  });

  it('(b) the receiver CANNOT create a positions document', async () => {
    await assertFails(addDoc(collection(asReceiver(), 'trips/t1/positions'), goodPosition()));
  });

  it('(b2) a stranger and an anonymous caller CANNOT create a positions document', async () => {
    await assertFails(addDoc(collection(asStranger(), 'trips/t1/positions'), goodPosition()));
    await assertFails(addDoc(collection(asAnon(), 'trips/t1/positions'), goodPosition()));
  });

  it('(c) a positions document missing expireAt is rejected', async () => {
    const { expireAt, ...noTtl } = goodPosition();
    void expireAt;
    await assertFails(addDoc(collection(asDriver(), 'trips/t1/positions'), noTtl));
  });

  it('(c2) expireAt must be a timestamp, not a number', async () => {
    await assertFails(addDoc(collection(asDriver(), 'trips/t1/positions'), {
      ...goodPosition(), expireAt: T0 + 1000,
    }));
  });

  it('(d) a positions document with an extra unknown field is rejected', async () => {
    await assertFails(addDoc(collection(asDriver(), 'trips/t1/positions'), {
      ...goodPosition(), battery: 42,
    }));
  });

  it('(d2) positions are append-only — no update, no delete', async () => {
    let id = '';
    await env.withSecurityRulesDisabled(async (ctx) => {
      const ref = await addDoc(collection(ctx.firestore(), 'trips/t1/positions'), goodPosition());
      id = ref.id;
    });
    await assertFails(updateDoc(doc(asDriver(), `trips/t1/positions/${id}`), { lat: 0 }));
    await assertFails(deleteDoc(doc(asDriver(), `trips/t1/positions/${id}`)));
  });

  it('both members CAN read positions; a stranger cannot', async () => {
    await assertSucceeds(getDocs(collection(asDriver(), 'trips/t1/positions')));
    await assertSucceeds(getDocs(collection(asReceiver(), 'trips/t1/positions')));
    await assertFails(getDocs(collection(asStranger(), 'trips/t1/positions')));
  });
});

describe('(e) every other collection is server-write-only', () => {
  it('a signed-in member cannot write trips, spots, pairs or users', async () => {
    const db = asDriver();
    await assertFails(setDoc(doc(db, 'trips/t1'), { state: 'arrived' }, { merge: true }));
    await assertFails(updateDoc(doc(db, 'trips/t1'), { state: 'arrived' }));
    await assertFails(deleteDoc(doc(db, 'trips/t1')));
    await assertFails(addDoc(collection(db, 'trips'), { pairId: 'p1' }));
    await assertFails(setDoc(doc(db, 'spots/s1'), { name: 'hacked' }, { merge: true }));
    await assertFails(addDoc(collection(db, 'spots'), { pairId: 'p1', name: 'x' }));
    await assertFails(setDoc(doc(db, 'pairs/p1'), { status: 'revoked' }, { merge: true }));
    await assertFails(setDoc(doc(db, 'users/' + DRIVER), { displayName: 'hacked' }, { merge: true }));
    await assertFails(addDoc(collection(db, 'trips/t1/replies'), { fromUid: DRIVER, kind: 'custom', text: 'x', ts: T0 }));
    await assertFails(addDoc(collection(db, 'schedules'), { pairId: 'p1' }));
  });

  it('members can still read their own trip, spot, replies and user document', async () => {
    await assertSucceeds(getDoc(doc(asDriver(), 'trips/t1')));
    await assertSucceeds(getDoc(doc(asReceiver(), 'trips/t1')));
    await assertFails(getDoc(doc(asStranger(), 'trips/t1')));
    await assertSucceeds(getDoc(doc(asDriver(), 'spots/s1')));
    await assertSucceeds(getDocs(collection(asReceiver(), 'trips/t1/replies')));
    await assertSucceeds(getDoc(doc(asDriver(), 'users/' + DRIVER)));
    await assertFails(getDoc(doc(asReceiver(), 'users/' + DRIVER)));
  });
});

describe('(f) pair discovery', () => {
  it('a member CAN read their pair; a non-member cannot', async () => {
    await assertSucceeds(getDoc(doc(asDriver(), 'pairs/p1')));
    await assertSucceeds(getDoc(doc(asReceiver(), 'pairs/p1')));
    await assertFails(getDoc(doc(asStranger(), 'pairs/p1')));
  });

  it('the contract query — members array-contains uid, status == active — SUCCEEDS', async () => {
    const db = asDriver();
    const snap = await assertSucceeds(getDocs(query(
      collection(db, 'pairs'),
      where('members', 'array-contains', DRIVER),
      where('status', '==', 'active'),
    )));
    expect(snap.docs.map((d) => d.id)).toEqual(['p1']);
    expect(snap.docs[0].data().memberNames[RECEIVER]).toBe('Sara');
  });

  it('an unfiltered read of the whole pairs collection FAILS', async () => {
    await assertFails(getDocs(collection(asDriver(), 'pairs')));
  });
});

describe('(g) _debugPushes — the emulator push sink', () => {
  it('a user can read rows addressed to them', async () => {
    await assertSucceeds(getDoc(doc(asDriver(), '_debugPushes/dp1')));
    const snap = await assertSucceeds(getDocs(query(
      collection(asReceiver(), '_debugPushes'),
      where('toUid', '==', RECEIVER),
      orderBy('sentAt'),
    )));
    expect(snap.docs.map((d) => d.data().kind)).toEqual(['leadTime']);
  });

  it('a user cannot read rows addressed to someone else', async () => {
    await assertFails(getDoc(doc(asDriver(), '_debugPushes/dp2')));
    await assertFails(getDocs(collection(asDriver(), '_debugPushes')));
    await assertFails(getDocs(query(
      collection(asDriver(), '_debugPushes'),
      where('toUid', '==', RECEIVER),
    )));
  });

  it('nobody can write the sink', async () => {
    await assertFails(setDoc(doc(asDriver(), '_debugPushes/dp1'), { toUid: DRIVER, delivered: true }, { merge: true }));
    await assertFails(addDoc(collection(asDriver(), '_debugPushes'), { toUid: DRIVER, kind: 'leadTime' }));
    await assertFails(deleteDoc(doc(asDriver(), '_debugPushes/dp1')));
  });
});
