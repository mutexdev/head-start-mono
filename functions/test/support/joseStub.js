// functions/test/support/joseStub.js
//
// A CommonJS stand-in for the ESM-only `jose` package, used ONLY by the jest
// runners (see moduleNameMapper in jest.config.js / jest.emulator.config.js).
//
// Why this exists: any src file that imports `firebase-functions/v2/https`
// — i.e. every callable — transitively loads
//   firebase-functions/v2/https -> firebase-admin/auth -> jwks-rsa -> jose
// and jose@6 ships pure ESM (`export { ... }`). Node 22 can require() an ESM
// module, but jest's CommonJS module runtime cannot, so the suite dies with
// "SyntaxError: Unexpected token 'export'" before a single test runs.
//
// jose is only reached when firebase-admin verifies a real ID token's JWKS
// signature. Tests invoke callable handlers directly via `.run()`, so that path
// is never taken. Each shimmed export therefore throws loudly if it is ever
// actually called, rather than silently returning a wrong value.
//
// This affects tests only. The emulator and Cloud Functions runtimes load the
// real ESM jose through Node's own require(esm) support.
'use strict';

const unavailable = (name) => () => {
  throw new Error(
    `jose.${name}() is not available in the jest CommonJS runtime (test/support/joseStub.js). ` +
    'A test reached real JWT/JWKS verification; invoke callables with .run() instead.',
  );
};

module.exports = {
  importJWK: unavailable('importJWK'),
  exportSPKI: unavailable('exportSPKI'),
  decodeJwt: unavailable('decodeJwt'),
  decodeProtectedHeader: unavailable('decodeProtectedHeader'),
};
