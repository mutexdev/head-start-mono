// functions/test/messages.test.ts
import { msg } from '../src/messages';

describe('messages', () => {
  it('started includes driver and rounded minutes', () => {
    const m = msg.started('r1', 'Mostafi', 1330, 'Office');
    expect(m.toUid).toBe('r1');
    expect(m.title).toBe('Mostafi started driving');
    expect(m.body).toBe('ETA 22 min to Office');
    expect(m.data.kind).toBe('started');
  });
  it('leadTime is urgent', () => {
    const m = msg.leadTime('r1', 'Mostafi', 170);
    expect(m.urgent).toBe(true);
    expect(m.title).toBe('Start walking now');
    expect(m.body).toBe('Mostafi is 3 min away');
  });
  it('appends (approx.) when approximate', () => {
    expect(msg.tenMin('r1', 'Mostafi', 590, true).body).toBe('Mostafi is 10 min away (approx.)');
  });
  it('slip says stay inside', () => {
    expect(msg.slip('r1', 'Mostafi', 480).body).toBe('Traffic — now 8 min, stay inside');
  });
  it('leadTime is the ONLY urgent kind — arrived in particular is not', () => {
    // docs/CLIENT_CONTRACT.md: leadTime alone maps to sync_urgent / time-sensitive.
    expect(msg.arrived('r1', 'Mostafi', 'Office').urgent).toBeFalsy();
    expect(msg.leadTime('r1', 'Mostafi', 170).urgent).toBe(true);
    const built = [
      msg.started('r1', 'Mostafi', 1330, 'Office'),
      msg.tenMin('r1', 'Mostafi', 590),
      msg.leadTime('r1', 'Mostafi', 170),
      msg.slip('r1', 'Mostafi', 480),
      msg.arrived('r1', 'Mostafi', 'Office'),
      msg.lost('r1', 'Mostafi'),
      msg.timeout('r1'),
      msg.cancelled('r1', 'Mostafi'),
      msg.didYouLeave('r1'),
      msg.armed('d1', 'Sara', 'Office'),
      msg.noShow('r1', 'Mostafi'),
      msg.runningLate('r1', 'Mostafi', 10),
      msg.reply('d1', 'Sara', 'Take your time'),
    ];
    expect(built).toHaveLength(13); // every kind in the contract's data.kind list
    expect(built.filter((m) => m.urgent).map((m) => m.data.kind)).toEqual(['leadTime']);
  });
});
