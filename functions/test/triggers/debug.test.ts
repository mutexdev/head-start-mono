// functions/test/triggers/debug.test.ts
//
// The 404 guard is the only thing standing between a deployed build and a public
// "run the housekeeping sweep with an arbitrary clock" endpoint, so it gets a
// unit test of its own.
import { enabled } from '../../src/triggers/debug';

describe('debug endpoint guard', () => {
  it('is on inside the Functions emulator', () => {
    expect(enabled({ FUNCTIONS_EMULATOR: 'true' } as NodeJS.ProcessEnv)).toBe(true);
  });

  it('is on when explicitly enabled', () => {
    expect(enabled({ ENABLE_DEBUG_ENDPOINTS: '1' } as NodeJS.ProcessEnv)).toBe(true);
  });

  it('is off by default — a deployed build serves 404', () => {
    expect(enabled({} as NodeJS.ProcessEnv)).toBe(false);
    expect(enabled({ FUNCTIONS_EMULATOR: 'false', ENABLE_DEBUG_ENDPOINTS: '0' } as NodeJS.ProcessEnv)).toBe(false);
  });
});
