module.exports = {
  preset: 'ts-jest',
  testEnvironment: 'node',
  // jose@6 is pure ESM and jest's CJS runtime cannot require() it. Reached via
  // firebase-functions/v2/https -> firebase-admin/auth -> jwks-rsa -> jose.
  // See test/support/joseStub.js.
  moduleNameMapper: { '^jose$': '<rootDir>/test/support/joseStub.js' },

  roots: ['<rootDir>/test'],
  testMatch: ['**/*.emulator.test.ts'],
  testTimeout: 30000,
  maxWorkers: 1,
};
