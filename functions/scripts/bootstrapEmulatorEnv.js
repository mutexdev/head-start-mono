#!/usr/bin/env node
/**
 * Idempotently creates functions/.secret.local so the Functions emulator can
 * satisfy defineSecret('GOOGLE_ROUTES_KEY') without a real key.
 *
 * firebase-tools reads LOCAL_SECRETS_FILE = '.secret.local' from the functions
 * source dir and injects its KEY=VALUE pairs into the emulated function's
 * process.env. Without it, secret-bound functions warn or fail at load time.
 *
 * The file is gitignored (functions/.gitignore) so no real key can ever be
 * committed by accident — it is generated, never checked in.
 *
 * Plain CommonJS, zero dependencies. Run by every emu:* npm script.
 */
'use strict';

const fs = require('fs');
const path = require('path');

const FUNCTIONS_DIR = path.resolve(__dirname, '..');
const SECRETS_FILE = path.join(FUNCTIONS_DIR, '.secret.local');
const PLACEHOLDER = 'GOOGLE_ROUTES_KEY=emulator-unused\n';

function main() {
  if (fs.existsSync(SECRETS_FILE)) {
    const body = fs.readFileSync(SECRETS_FILE, 'utf8');
    if (/^\s*GOOGLE_ROUTES_KEY\s*=/m.test(body)) {
      console.log(`[bootstrapEmulatorEnv] kept existing ${SECRETS_FILE} (GOOGLE_ROUTES_KEY already set)`);
      return;
    }
    const sep = body.length === 0 || body.endsWith('\n') ? '' : '\n';
    fs.appendFileSync(SECRETS_FILE, sep + PLACEHOLDER);
    console.log(`[bootstrapEmulatorEnv] appended GOOGLE_ROUTES_KEY placeholder to ${SECRETS_FILE}`);
    return;
  }

  fs.writeFileSync(SECRETS_FILE, PLACEHOLDER, { mode: 0o600 });
  console.log(`[bootstrapEmulatorEnv] created ${SECRETS_FILE} with GOOGLE_ROUTES_KEY placeholder`);
}

main();
