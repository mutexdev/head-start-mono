// functions/src/io/firestore.ts
//
// The single Firestore seam. firebase-admin v14 REMOVED the namespaced API
// (`admin.firestore()` is not a function any more), so everything here — and in
// functions/scripts/*.js — uses the modular entry points only.
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
export const positions = (tripId: string) =>
  trips().doc(tripId).collection('positions') as CollectionReference<Position & { expireAt: Date }>;
export const replies = (tripId: string) =>
  trips().doc(tripId).collection('replies') as CollectionReference<ReplyDoc>;

/**
 * The emulator push sink (CLIENT_CONTRACT_ADDENDUM.md, "Emulator contract").
 * One document per would-be push; read-only for the addressed user via rules.
 * Never written in production unless PUSH_DEBUG_MIRROR=1.
 */
export const debugPushes = () => col<Record<string, unknown>>('_debugPushes');

export async function getOrThrow<T>(ref: DocumentReference<T>, code: string): Promise<T> {
  const snap = await ref.get();
  if (!snap.exists) throw new Error(code);
  return snap.data() as T;
}

export const now = () => Date.now();
