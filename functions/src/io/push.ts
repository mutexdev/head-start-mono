// functions/src/io/push.ts
//
// The push seam. FCM cannot deliver from the Firebase emulator and there is no
// APNs key or paid Apple team here, so the alert ladder would be completely
// unobservable end to end with a single hard-wired FCM sender. Instead the
// sender is an interface with two implementations:
//
//   FcmPushSender        production — real multicast + dead-token pruning
//   FirestorePushSender  emulator   — writes the payload FCM WOULD have carried
//                                     to `_debugPushes/{autoId}`
//
// Both clients ship a debug-only listener on `_debugPushes where toUid == me`
// that feeds rows into the same rendering path a real APNs/FCM message takes,
// which is what makes the server's decisions assertable on a Simulator/AVD.
// See CLIENT_CONTRACT_ADDENDUM.md, "Emulator contract".
import { getMessaging } from 'firebase-admin/messaging';
import { FieldValue } from 'firebase-admin/firestore';
// `firebase-functions/logger` and not the package root on purpose: the root
// index pulls in v2/https -> firebase-admin/auth -> jwks-rsa -> jose, which is
// ESM-only and cannot be loaded by the CJS jest/ts-jest unit runner.
import * as logger from 'firebase-functions/logger';
import { PushMessage, PushSink } from '../types';
import { users, debugPushes } from './firestore';

// ---------------------------------------------------------------------------
// Pure mapping helpers (no Firestore, no FCM — unit-tested without an emulator)
// ---------------------------------------------------------------------------

export type AndroidChannelId = 'sync_urgent' | 'sync_updates';
export type ApnsInterruptionLevel = 'time-sensitive' | 'active';

/** Extra context the message builders do not know about. */
export interface PushContext { tripId?: string }

/**
 * The exact `_debugPushes/{autoId}` document shape. THIS IS A CONTRACT with the
 * iOS and Android debug push bridges — do not add, rename or reorder-away fields.
 */
export interface DebugPushDoc {
  toUid: string;
  kind: string;
  title: string;
  body: string;
  urgent: boolean;
  data: Record<string, string>;
  androidChannelId: AndroidChannelId;
  apnsInterruptionLevel: ApnsInterruptionLevel;
  tokens: string[];
  sentAt: number;
  delivered: false;
}

/** CLIENT_CONTRACT.md lines 53-56: `leadTime` is the only urgent kind. */
export const channelIdFor = (urgent?: boolean): AndroidChannelId =>
  (urgent ? 'sync_urgent' : 'sync_updates');

/** CLIENT_CONTRACT.md lines 53-56 (iOS half of the same mapping). */
export const interruptionLevelFor = (urgent?: boolean): ApnsInterruptionLevel =>
  (urgent ? 'time-sensitive' : 'active');

/**
 * The wire `data` payload: whatever the builder set, plus `data.tripId` for every
 * trip-scoped push (addendum section D). Values stay strings — FCM rejects
 * anything else.
 */
export function payloadData(m: PushMessage, ctx?: PushContext): Record<string, string> {
  return ctx?.tripId ? { ...m.data, tripId: ctx.tripId } : { ...m.data };
}

export function debugPushDoc(m: PushMessage, tokens: string[], ctx?: PushContext): DebugPushDoc {
  const data = payloadData(m, ctx);
  return {
    toUid: m.toUid,
    kind: data.kind,
    title: m.title,
    body: m.body,
    urgent: m.urgent === true,
    data,
    androidChannelId: channelIdFor(m.urgent),
    apnsInterruptionLevel: interruptionLevelFor(m.urgent),
    tokens,
    sentAt: Date.now(),
    delivered: false,
  };
}

// ---------------------------------------------------------------------------
// Senders
// ---------------------------------------------------------------------------

export interface PushSender {
  send(m: PushMessage, ctx?: PushContext): Promise<void>;
}

async function tokensFor(uid: string): Promise<string[]> {
  const snap = await users().doc(uid).get();
  return snap.data()?.fcmTokens ?? [];
}

/** Production sender: real FCM multicast, prunes tokens FCM reports as dead. */
export class FcmPushSender implements PushSender {
  async send(m: PushMessage, ctx?: PushContext): Promise<void> {
    const tokens = await tokensFor(m.toUid);
    if (tokens.length === 0) { logger.warn('no tokens', { uid: m.toUid, kind: m.data.kind }); return; }

    const res = await getMessaging().sendEachForMulticast({
      tokens,
      notification: { title: m.title, body: m.body },
      data: payloadData(m, ctx),
      android: {
        priority: 'high',
        notification: { channelId: channelIdFor(m.urgent), sound: m.urgent ? 'urgent' : 'default' },
      },
      apns: {
        headers: { 'apns-priority': '10', ...(m.urgent ? { 'apns-push-type': 'alert' } : {}) },
        payload: { aps: { sound: m.urgent ? 'urgent.caf' : 'default', 'interruption-level': interruptionLevelFor(m.urgent) } },
      },
    });

    const dead = res.responses
      .map((r, i) => (!r.success && r.error?.code === 'messaging/registration-token-not-registered' ? tokens[i] : null))
      .filter((t): t is string => t !== null);
    if (dead.length) await users().doc(m.toUid).update({ fcmTokens: FieldValue.arrayRemove(...dead) });
  }
}

/** Emulator sender: records exactly what WOULD have been sent. Never delivers. */
export class FirestorePushSender implements PushSender {
  async send(m: PushMessage, ctx?: PushContext): Promise<void> {
    const tokens = await tokensFor(m.toUid).catch(() => [] as string[]);
    // cast: the collection is typed Record<string, unknown> (firestore.ts must not
    // import this module — it would be a cycle). The shape is enforced by debugPushDoc.
    await debugPushes().add(debugPushDoc(m, tokens, ctx) as unknown as Record<string, unknown>);
  }
}

/** PUSH_DEBUG_MIRROR=1: really send AND record. Recording failures never break delivery. */
export class MirroringPushSender implements PushSender {
  constructor(private readonly primary: PushSender, private readonly mirror: PushSender) {}
  async send(m: PushMessage, ctx?: PushContext): Promise<void> {
    await this.primary.send(m, ctx);
    try {
      await this.mirror.send(m, ctx);
    } catch (e) {
      logger.warn('push mirror failed', { uid: m.toUid, kind: m.data.kind, err: String(e) });
    }
  }
}

/** Which sink this process delivers to. Pure — exported so it can be unit-tested. */
export function sinkFor(env: NodeJS.ProcessEnv = process.env): PushSink {
  return env.PUSH_SINK === 'firestore' || env.FUNCTIONS_EMULATOR === 'true' ? 'firestore' : 'fcm';
}

export function pushSender(): PushSender {
  if (sinkFor() === 'firestore') return new FirestorePushSender();
  const fcm = new FcmPushSender();
  return process.env.PUSH_DEBUG_MIRROR === '1'
    ? new MirroringPushSender(fcm, new FirestorePushSender())
    : fcm;
}

export async function sendPush(m: PushMessage, ctx?: PushContext): Promise<void> {
  return pushSender().send(m, ctx);
}

/**
 * Sequential on purpose: `_debugPushes.sentAt` ordering is what the driver script
 * asserts the alert ladder against, and Promise.all would race it.
 */
export async function sendAll(msgs: PushMessage[], ctx?: PushContext): Promise<void> {
  for (const m of msgs) await sendPush(m, ctx);
}
