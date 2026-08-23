// functions/src/messages.ts
import { PushMessage } from './types';

const min = (sec: number) => Math.max(1, Math.round(sec / 60));
const approx = (a?: boolean) => (a ? ' (approx.)' : '');

function build(toUid: string, kind: string, title: string, body: string, extra: Record<string, string> = {}, urgent = false): PushMessage {
  return { toUid, title, body, data: { kind, ...extra }, urgent };
}

/**
 * Push copy. `leadTime` is the ONLY urgent kind (CLIENT_CONTRACT.md: Android
 * channel `sync_urgent` / iOS `time-sensitive`); every other kind — `arrived`
 * included — is `sync_updates` / `active`. The push layer derives the channel id
 * and interruption level purely from the `urgent` flag, so marking anything else
 * urgent silently sends both clients a channel id they do not map.
 */
export const msg = {
  started: (toUid: string, driver: string, etaSec: number, spotName: string, a?: boolean) =>
    build(toUid, 'started', `${driver} started driving`, `ETA ${min(etaSec)} min to ${spotName}${approx(a)}`),
  tenMin: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'tenMin', `${driver} is close`, `${driver} is ${min(etaSec)} min away${approx(a)}`),
  leadTime: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'leadTime', 'Start walking now', `${driver} is ${min(etaSec)} min away${approx(a)}`, {}, true),
  slip: (toUid: string, driver: string, etaSec: number, a?: boolean) =>
    build(toUid, 'slip', `${driver} is delayed`, `Traffic — now ${min(etaSec)} min, stay inside${approx(a)}`),
  arrived: (toUid: string, driver: string, spotName: string) =>
    build(toUid, 'arrived', `${driver} has arrived`, `Waiting at ${spotName}`, {}),
  lost: (toUid: string, other: string) =>
    build(toUid, 'lost', 'Connection lost', `No location from ${other} for 5 min`),
  timeout: (toUid: string) =>
    build(toUid, 'timeout', 'Trip ended', 'The trip timed out after 3 hours'),
  cancelled: (toUid: string, by: string) =>
    build(toUid, 'cancelled', 'Trip cancelled', `${by} cancelled the pickup`),
  didYouLeave: (toUid: string) =>
    build(toUid, 'didYouLeave', 'Did you leave?', 'No movement detected. Tap to confirm or cancel.'),
  armed: (toUid: string, receiver: string, spotName: string) =>
    build(toUid, 'armed', `${receiver} is waiting`, `Tap when you leave for ${spotName}`),
  noShow: (toUid: string, driver: string) =>
    build(toUid, 'noShow', 'No trip started yet', `${driver} hasn't started driving`),
  runningLate: (toUid: string, driver: string, extraMin: number) =>
    build(toUid, 'runningLate', `${driver} is running late`, `About ${extraMin} more min`),
  reply: (toUid: string, from: string, text: string) =>
    build(toUid, 'reply', from, text),
};

export const replyText: Record<string, (spotName: string) => string> = {
  fiveMore: () => '5 more minutes please',
  takeYourTime: () => 'Take your time',
  atSpot: (spot) => `I'm at ${spot}`,
};
