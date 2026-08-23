// functions/src/callables/auth.ts
//
// Shared guards for every callable. Error *messages* are the contract's error
// codes (CLIENT_CONTRACT.md): clients switch on the message, not the gRPC code.
import { HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { pairs, getOrThrow } from '../io/firestore';
import { PairDoc } from '../types';

export function uidOf(req: CallableRequest): string {
  const uid = req.auth?.uid;
  if (!uid) throw new HttpsError('unauthenticated', 'sign-in required');
  return uid;
}

export async function requireActivePair(pairId: string, uid: string): Promise<PairDoc> {
  const pair = await getOrThrow(pairs().doc(pairId), 'not-paired').catch(() => {
    throw new HttpsError('not-found', 'not-paired');
  });
  if (pair.status !== 'active' || !pair.members.includes(uid)) {
    throw new HttpsError('permission-denied', 'not-paired');
  }
  return pair;
}

export function otherMember(pair: PairDoc, uid: string): string {
  const other = pair.members.find((m) => m !== uid);
  if (!other) throw new HttpsError('failed-precondition', 'not-paired');
  return other;
}
