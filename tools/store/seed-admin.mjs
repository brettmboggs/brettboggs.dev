// Creates (or re-invites) the admin account and prints a one-time enrollment
// link. Run it whenever a new passkey is needed, including if a device is lost.
//
//   node tools/store/seed-admin.mjs            (production)
//   node tools/store/seed-admin.mjs --local    (local wrangler dev)
//
// This is the only way in that does not require already being in, which is why
// it lives behind terminal access to the Cloudflare account rather than behind
// anything on the public internet.

import { execFileSync } from 'node:child_process';

const EMAIL = 'brettmboggs@gmail.com';
const NAME = 'Brett Boggs';
const SITE = process.env.SITE ?? 'https://brettboggs.dev';
const local = process.argv.includes('--local');

const rand = (n = 24) =>
  Buffer.from(crypto.getRandomValues(new Uint8Array(n)))
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=+$/, '');

// npx is a shell script on Windows, so it needs shell:true to be found.
const NPX = process.platform === 'win32' ? 'npx.cmd' : 'npx';

function sql(statement) {
  // With shell:true the statement has to arrive as one quoted argument, or the
  // shell splits it on spaces and wrangler sees a dozen unknown arguments.
  const oneLine = statement.split(/\s+/).join(' ');
  const quoted = '"' + oneLine.replace(/"/g, '\\"') + '"';
  const args = ['wrangler', 'd1', 'execute', 'brettboggs-store', local ? '--local' : '--remote', '--command', quoted, '--json'];
  const out = execFileSync(NPX, args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'], shell: true });
  const start = out.indexOf('[');
  return JSON.parse(out.slice(start))[0].results ?? [];
}

const now = new Date().toISOString();
const existing = sql(`SELECT id FROM users WHERE email = '${EMAIL}'`);

let id;
if (existing.length) {
  id = existing[0].id;
  console.log(`  admin already exists: ${id}`);
} else {
  id = rand(12);
  sql(
    `INSERT INTO users (id, email, name, role, status, created_at)
     VALUES ('${id}', '${EMAIL}', '${NAME}', 'admin', 'active', '${now}')`,
  );
  console.log(`  admin created: ${id}`);
}

const token = rand(32);
const expires = new Date(Date.now() + 48 * 3600 * 1000).toISOString();
sql(
  `INSERT INTO invites (token, user_id, purpose, expires_at, created_at)
   VALUES ('${token}', '${id}', 'enroll', '${expires}', '${now}')`,
);

console.log('');
console.log('  Open this once, on the device you want to sign in from.');
console.log('  It expires in 48 hours and works a single time.');
console.log('');
console.log(`  ${SITE}/admin/enroll/?t=${token}`);
