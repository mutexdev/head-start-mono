// functions/src/callables/tokens.ts
import { onCall, HttpsError } from 'firebase-functions/v2/https';
import { FieldValue } from 'firebase-admin/firestore';
import { users, now } from '../io/firestore';
import { uidOf } from './auth';
import { syncDisplayNameToPairs } from './pairs';

export const registerPushToken = onCall(async (req) => {
  const uid = uidOf(req);
  const token = String(req.data?.token ?? '');
  const platform = req.data?.platform === 'android' ? 'android' : 'ios';
  const displayName = String(req.data?.displayName ?? '').trim().slice(0, 30);
  if (token.length < 20) throw new HttpsError('invalid-argument', 'bad-token');
  const ref = users().doc(uid);
  const snap = await ref.get();
  if (!snap.exists) {
    await ref.set({
      phone: req.auth?.token.phone_number ?? '',
      displayName: displayName || 'Someone',
      platform,
      fcmTokens: [token],
      createdAt: now(),
    });
    // A brand new user document cannot belong to a pair yet, so nothing to sync.
  } else {
    await ref.update({ fcmTokens: FieldValue.arrayUnion(token), platform, ...(displayName ? { displayName } : {}) });
    // Propagate a renamed user into every active pair's denormalised memberNames.
    if (displayName) await syncDisplayNameToPairs(uid, displayName);
  }
  return { ok: true };
});

export const setLowBattery = onCall(async (req) => {
  const uid = uidOf(req);
  await users().doc(uid).update({ lowBattery: !!req.data?.lowBattery });
  return { ok: true };
});
