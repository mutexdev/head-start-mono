// Regression test for a rules bug the Android end-to-end drive found and that
// every get-based rules test missed: for a LIST, Firestore synthesises `resource`
// from the query's own constraints, so a rule dereferencing a field the client did
// not filter on (driverUid) fails the entire query.
// CLIENT_CONTRACT.md: trips where pairId == <pairId> and state in ["armed","driving"].
import { initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { collection, query, where, getDocs, doc, setDoc, getDoc } from 'firebase/firestore';

let env: RulesTestEnvironment;
const DRIVER = 'uidDriver', RECV = 'uidRecv', PAIR = 'pair1';

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'fin-e8358',
    firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `pairs/${PAIR}`), {
      members: [DRIVER, RECV], status: 'active', memberNames: { [DRIVER]: 'Mostafi', [RECV]: 'Sara' },
    });
    await setDoc(doc(ctx.firestore(), 'trips/t1'), {
      pairId: PAIR, driverUid: DRIVER, receiverUid: RECV, state: 'driving',
    });
  });
});
afterAll(async () => { await env.cleanup(); });

test('GET a trip as the driver', async () => {
  const db = env.authenticatedContext(DRIVER).firestore();
  const s = await getDoc(doc(db, 'trips/t1'));
  expect(s.exists()).toBe(true);
});

test('a NON-member cannot list the pair\'s trips', async () => {
  const db = env.authenticatedContext('uidStranger').firestore();
  const q = query(collection(db, 'trips'), where('pairId', '==', PAIR), where('state', 'in', ['armed', 'driving']));
  await expect(getDocs(q)).rejects.toThrow();
});

test('an UNFILTERED trips collection read is still denied', async () => {
  const db = env.authenticatedContext(DRIVER).firestore();
  await expect(getDocs(collection(db, 'trips'))).rejects.toThrow();
});

test('LIST the active trip the way CLIENT_CONTRACT.md says clients must', async () => {
  const db = env.authenticatedContext(DRIVER).firestore();
  const q = query(collection(db, 'trips'), where('pairId', '==', PAIR), where('state', 'in', ['armed', 'driving']));
  const snap = await getDocs(q);
  expect(snap.size).toBe(1);
});
