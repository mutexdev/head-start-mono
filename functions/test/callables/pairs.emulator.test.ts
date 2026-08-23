// Runs only under: npm run test:emu
process.env.GCLOUD_PROJECT = 'fin-e8358';

import { pairs, users } from '../../src/io/firestore';
import { syncDisplayNameToPairs } from '../../src/callables/pairs';

const T0 = 1_700_000_000_000;

describe('memberNames denormalisation', () => {
  beforeAll(() => { if (!process.env.FIRESTORE_EMULATOR_HOST) throw new Error('run via npm run test:emu'); });

  it('syncDisplayNameToPairs updates every active pair the user belongs to', async () => {
    await users().doc('u1').set({ phone: '+1', displayName: 'Mostafi', platform: 'ios', fcmTokens: [], createdAt: T0 });
    const a = await pairs().add({ members: ['u1', 'u2'], status: 'active', inviteCode: 'AAA111', createdBy: 'u1', createdAt: T0, memberNames: { u1: 'Old', u2: 'Sara' } });
    const b = await pairs().add({ members: ['u3', 'u4'], status: 'active', inviteCode: 'BBB222', createdBy: 'u3', createdAt: T0, memberNames: { u3: 'X', u4: 'Y' } });

    await syncDisplayNameToPairs('u1', 'Mostafi');

    expect((await a.get()).data()!.memberNames).toEqual({ u1: 'Mostafi', u2: 'Sara' });
    expect((await b.get()).data()!.memberNames).toEqual({ u3: 'X', u4: 'Y' });
  });
});
