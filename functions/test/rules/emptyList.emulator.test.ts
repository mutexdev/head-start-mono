// A list rule that dereferences resource.data must still behave when the query
// matches ZERO documents. Found by the iOS end-to-end drive: a brand-new pair
// with no spots yet got PERMISSION_DENIED on the contract's own spots query.
import { initializeTestEnvironment, RulesTestEnvironment } from '@firebase/rules-unit-testing';
import { readFileSync } from 'fs';
import { collection, query, where, getDocs, doc, setDoc } from 'firebase/firestore';

let env: RulesTestEnvironment;
const A = 'uidA', B = 'uidB', PAIR = 'pairEmpty';

beforeAll(async () => {
  env = await initializeTestEnvironment({
    projectId: 'fin-e8358',
    firestore: { host: '127.0.0.1', port: 8080, rules: readFileSync('../firestore.rules', 'utf8') },
  });
  await env.clearFirestore();
  await env.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), `pairs/${PAIR}`), {
      members: [A, B], status: 'active', memberNames: { [A]: 'A', [B]: 'B' },
    });
  });
});
afterAll(async () => { await env.cleanup(); });

test('spots query on a pair with NO spots yet succeeds and returns empty', async () => {
  const db = env.authenticatedContext(A).firestore();
  const snap = await getDocs(query(collection(db, 'spots'), where('pairId', '==', PAIR)));
  expect(snap.empty).toBe(true);
});

test('active-trip query with NO active trip succeeds and returns empty', async () => {
  const db = env.authenticatedContext(A).firestore();
  const snap = await getDocs(query(collection(db, 'trips'),
    where('pairId', '==', PAIR), where('state', 'in', ['armed', 'driving'])));
  expect(snap.empty).toBe(true);
});

// A stale pairId (held after an unpair, or raced during onboarding) must be
// DENIED, not handed an empty list — but it must fail as a clean rule evaluation,
// not as a "Null value error" from dereferencing a null get(). Clients treat
// PERMISSION_DENIED on this query as "no pair".
test('spots query for a pairId whose pair document does NOT exist is cleanly denied', async () => {
  const db = env.authenticatedContext(A).firestore();
  await expect(getDocs(query(collection(db, 'spots'), where('pairId', '==', 'ghostPair'))))
    .rejects.toThrow();
});

test('a non-member is denied the spots of a pair that DOES exist', async () => {
  const db = env.authenticatedContext('uidStranger').firestore();
  await expect(getDocs(query(collection(db, 'spots'), where('pairId', '==', PAIR))))
    .rejects.toThrow();
});
