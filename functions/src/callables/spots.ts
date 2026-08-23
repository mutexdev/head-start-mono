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
  // CLIENT_CONTRACT_ADDENDUM.md section K: clients clamp too, so a user never sees a raw error.
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
