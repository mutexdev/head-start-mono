// functions/src/callables/pairs.ts
//
// Pair lifecycle. `memberNames` (uid -> displayName) is populated from the FIRST
// write — never retrofitted — because CLIENT_CONTRACT.md line 31 /
// CLIENT_CONTRACT_ADDENDUM.md section M make it the only way either client can
// render the partner's name (rules let a user read only their own users/{uid}).
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { pairs, users, now } from '../io/firestore';
import { uidOf } from './auth';
import { PairDoc } from '../types';

const CODE_ALPHABET = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

export function randomCode(len = 6): string {
  let s = '';
  for (let i = 0; i < len; i++) s += CODE_ALPHABET[Math.floor(Math.random() * CODE_ALPHABET.length)];
  return s;
}

/** Keeps pairs/{id}.memberNames in step with a user's current displayName. */
export async function syncDisplayNameToPairs(uid: string, displayName: string): Promise<void> {
  const q = await pairs()
    .where('members', 'array-contains', uid)
    .where('status', '==', 'active')
    .get();
  await Promise.all(q.docs.map((d) => d.ref.update({ [`memberNames.${uid}`]: displayName })));
}

export async function nameOf(uid: string): Promise<string> {
  return (await users().doc(uid).get()).data()?.displayName ?? 'Someone';
}

export const createPair = onCall(async (req) => {
  const uid = uidOf(req);
  const displayName = await nameOf(uid);
  for (let attempt = 0; attempt < 5; attempt++) {
    const inviteCode = randomCode();
    const clash = await pairs()
      .where('inviteCode', '==', inviteCode)
      .where('status', '==', 'pending')
      .limit(1)
      .get();
    if (!clash.empty) continue;
    const doc: PairDoc = {
      members: [uid],
      status: 'pending',
      inviteCode,
      createdBy: uid,
      createdAt: now(),
      memberNames: { [uid]: displayName },
    };
    const ref = await pairs().add(doc);
    return { pairId: ref.id, inviteCode };
  }
  throw new HttpsError('internal', 'code-collision');
});

export const acceptPair = onCall(async (req) => {
  const uid = uidOf(req);
  const code = String(req.data?.code ?? '').toUpperCase().trim();
  if (code.length !== 6) throw new HttpsError('invalid-argument', 'bad-code');
  const q = await pairs()
    .where('inviteCode', '==', code)
    .where('status', '==', 'pending')
    .limit(1)
    .get();
  if (q.empty) throw new HttpsError('not-found', 'bad-code');
  const snap = q.docs[0];
  const pair = snap.data();
  if (pair.createdBy === uid) throw new HttpsError('failed-precondition', 'own-code');
  await snap.ref.update({
    members: [pair.createdBy, uid],
    status: 'active',
    [`memberNames.${uid}`]: await nameOf(uid),
    [`memberNames.${pair.createdBy}`]: await nameOf(pair.createdBy),
  });
  return { pairId: snap.id };
});

export const revokePair = onCall(async (req) => {
  const uid = uidOf(req);
  const pairId = String(req.data?.pairId ?? '');
  const ref = pairs().doc(pairId);
  const snap = await ref.get();
  if (!snap.exists || !snap.data()!.members.includes(uid)) {
    throw new HttpsError('permission-denied', 'not-paired');
  }
  await ref.update({ status: 'revoked' });
  return { ok: true };
});
