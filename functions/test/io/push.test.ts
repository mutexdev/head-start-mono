import {
  channelIdFor,
  interruptionLevelFor,
  payloadData,
  debugPushDoc,
  sinkFor,
  pushSender,
  FcmPushSender,
  FirestorePushSender,
  MirroringPushSender,
} from '../../src/io/push';
import { msg } from '../../src/messages';
import { PushMessage } from '../../src/types';

const lead: PushMessage = msg.leadTime('rx', 'Sam', 180);
const arrived: PushMessage = msg.arrived('rx', 'Sam', 'Gate B');

describe('urgency mapping (CLIENT_CONTRACT.md lines 53-56)', () => {
  it('urgent -> sync_urgent / time-sensitive', () => {
    expect(channelIdFor(true)).toBe('sync_urgent');
    expect(interruptionLevelFor(true)).toBe('time-sensitive');
  });
  it('non-urgent (and undefined) -> sync_updates / active', () => {
    expect(channelIdFor(false)).toBe('sync_updates');
    expect(channelIdFor(undefined)).toBe('sync_updates');
    expect(interruptionLevelFor(false)).toBe('active');
    expect(interruptionLevelFor(undefined)).toBe('active');
  });
  it('leadTime is urgent and arrived is not', () => {
    expect(channelIdFor(lead.urgent)).toBe('sync_urgent');
    expect(channelIdFor(arrived.urgent)).toBe('sync_updates');
    expect(interruptionLevelFor(arrived.urgent)).toBe('active');
  });
});

describe('payloadData', () => {
  it('injects data.tripId when ctx carries one', () => {
    expect(payloadData(lead, { tripId: 't1' })).toEqual({ kind: 'leadTime', tripId: 't1' });
  });
  it('omits tripId for non-trip pushes', () => {
    expect(payloadData(lead)).toEqual({ kind: 'leadTime' });
    expect(payloadData(lead, {})).toEqual({ kind: 'leadTime' });
  });
  it('does not mutate the message builder output', () => {
    payloadData(lead, { tripId: 't1' });
    expect(lead.data).toEqual({ kind: 'leadTime' });
  });
});

describe('debugPushDoc — the _debugPushes contract with both clients', () => {
  it('has exactly the eleven contract keys', () => {
    const d = debugPushDoc(lead, ['tok1'], { tripId: 't1' });
    expect(Object.keys(d).sort()).toEqual([
      'androidChannelId', 'apnsInterruptionLevel', 'body', 'data', 'delivered',
      'kind', 'sentAt', 'title', 'tokens', 'toUid', 'urgent',
    ].sort());
  });

  it('mirrors an urgent push exactly', () => {
    const before = Date.now();
    const d = debugPushDoc(lead, ['tok1', 'tok2'], { tripId: 't1' });
    expect(d.toUid).toBe('rx');
    expect(d.kind).toBe('leadTime');
    expect(d.kind).toBe(d.data.kind);
    expect(d.title).toBe(lead.title);
    expect(d.body).toBe(lead.body);
    expect(d.urgent).toBe(true);
    expect(d.data).toEqual({ kind: 'leadTime', tripId: 't1' });
    expect(d.androidChannelId).toBe('sync_urgent');
    expect(d.apnsInterruptionLevel).toBe('time-sensitive');
    expect(d.tokens).toEqual(['tok1', 'tok2']);
    expect(d.delivered).toBe(false);
    expect(d.sentAt).toBeGreaterThanOrEqual(before);
    expect(d.sentAt).toBeLessThanOrEqual(Date.now());
  });

  it('mirrors a non-urgent push, and tolerates zero tokens', () => {
    const d = debugPushDoc(arrived, [], { tripId: 't1' });
    expect(d.urgent).toBe(false);
    expect(d.androidChannelId).toBe('sync_updates');
    expect(d.apnsInterruptionLevel).toBe('active');
    expect(d.tokens).toEqual([]);
    expect(d.data).toEqual({ kind: 'arrived', tripId: 't1' });
  });

  it('omits tripId entirely for a non-trip push', () => {
    const d = debugPushDoc(arrived, []);
    expect(d.data).toEqual({ kind: 'arrived' });
    expect('tripId' in d.data).toBe(false);
  });
});

describe('sink selection', () => {
  it('is firestore under the emulator or an explicit PUSH_SINK', () => {
    expect(sinkFor({ FUNCTIONS_EMULATOR: 'true' } as NodeJS.ProcessEnv)).toBe('firestore');
    expect(sinkFor({ PUSH_SINK: 'firestore' } as NodeJS.ProcessEnv)).toBe('firestore');
  });
  it('is fcm otherwise', () => {
    expect(sinkFor({} as NodeJS.ProcessEnv)).toBe('fcm');
    expect(sinkFor({ FUNCTIONS_EMULATOR: 'false', PUSH_SINK: 'fcm' } as NodeJS.ProcessEnv)).toBe('fcm');
  });

  describe('pushSender()', () => {
    const saved = { ...process.env };
    beforeEach(() => {
      delete process.env.FUNCTIONS_EMULATOR;
      delete process.env.PUSH_SINK;
      delete process.env.PUSH_DEBUG_MIRROR;
    });
    afterAll(() => { process.env = { ...saved }; });

    it('returns FirestorePushSender when FUNCTIONS_EMULATOR=true', () => {
      process.env.FUNCTIONS_EMULATOR = 'true';
      expect(pushSender()).toBeInstanceOf(FirestorePushSender);
    });
    it('returns FirestorePushSender when PUSH_SINK=firestore', () => {
      process.env.PUSH_SINK = 'firestore';
      expect(pushSender()).toBeInstanceOf(FirestorePushSender);
    });
    it('returns FcmPushSender in production', () => {
      expect(pushSender()).toBeInstanceOf(FcmPushSender);
    });
    it('wraps FCM in the mirror when PUSH_DEBUG_MIRROR=1', () => {
      process.env.PUSH_DEBUG_MIRROR = '1';
      expect(pushSender()).toBeInstanceOf(MirroringPushSender);
    });
  });
});
