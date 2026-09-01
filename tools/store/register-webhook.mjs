// Registers this store's webhook endpoint with Stripe and prints the signing
// secret on stdout so it can be piped straight into `wrangler secret put`.
//
//   node register-webhook.mjs | npx wrangler secret put STRIPE_WEBHOOK_SECRET
//
// Everything human-readable goes to stderr; stdout carries the secret and
// nothing else. If anything goes wrong the process exits non-zero WITHOUT
// writing to stdout, so a failure can never upload an empty secret.

import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const vars = join(dirname(fileURLToPath(import.meta.url)), '.dev.vars');
const env = Object.fromEntries(
  readFileSync(vars, 'utf8')
    .split(/\r?\n/)
    .filter((l) => l && !l.startsWith('#'))
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]),
);

const SK = env.STRIPE_SECRET_KEY;
const ENDPOINT = process.env.WEBHOOK_URL ?? 'https://brettboggs-store.brettmboggs.workers.dev/webhook';
const EVENTS = [
  'payment_intent.succeeded',
  'payment_intent.payment_failed',
  'charge.refunded',
  'charge.dispute.created',
];

const die = (msg) => {
  console.error(`  ERROR: ${msg}`);
  process.exit(1);
};

if (!SK) die('no STRIPE_SECRET_KEY in .dev.vars');

async function api(path, method = 'GET', body) {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${SK}`,
      ...(body ? { 'Content-Type': 'application/x-www-form-urlencoded' } : {}),
    },
    body,
  });
  const json = await res.json();
  if (json.error) die(json.error.message);
  return json;
}

const list = await api('/webhook_endpoints?limit=100');
const existing = (list.data ?? []).find((w) => w.url === ENDPOINT);

if (existing) {
  // Stripe reveals a signing secret only when the endpoint is created, so an
  // existing endpoint has to be replaced to learn its secret again.
  console.error(`  replacing existing endpoint ${existing.id}`);
  await api(`/webhook_endpoints/${existing.id}`, 'DELETE');
}

const params = new URLSearchParams();
params.set('url', ENDPOINT);
params.set('description', 'brettboggs.dev store');
EVENTS.forEach((ev, i) => params.set(`enabled_events[${i}]`, ev));

const made = await api('/webhook_endpoints', 'POST', params.toString());
if (!made.secret) die('Stripe returned no signing secret');

console.error(`  created ${made.id}`);
console.error(`  url     ${made.url}`);
console.error(`  events  ${made.enabled_events.join(', ')}`);
console.error(`  secret  ${made.secret.length} chars, writing to stdout`);

process.stdout.write(made.secret);
