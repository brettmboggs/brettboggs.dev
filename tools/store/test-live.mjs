// End-to-end test against the DEPLOYED Worker, with no help from us.
//
// Unlike test-payflow.mjs, this does NOT hand-deliver the webhook. It pays,
// then waits for Stripe to call the deployed Worker by itself, which is the
// only way to prove the deployed webhook path actually works.
//
//   node tools/store/test-live.mjs
//   CART='[{"id":"cards-deck","qty":1}]' node tools/store/test-live.mjs

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
const WORKER = process.env.WORKER ?? 'https://brettboggs-store.brettmboggs.workers.dev';
const CART = JSON.parse(process.env.CART ?? '[{"id":"print-file-eclipse","qty":1}]');

const say = (s) => console.log(s);

say(`worker: ${WORKER}`);
say(`cart:   ${CART.map((c) => `${c.id} x${c.qty}`).join(', ')}`);

say('\n1. checkout');
const co = await fetch(`${WORKER}/checkout`, {
  method: 'POST',
  headers: { 'Content-Type': 'application/json', Origin: 'https://brettboggs.dev' },
  body: JSON.stringify({
    email: 'buyer@example.com',
    items: CART,
    shipping: {
      name: 'Test Buyer',
      line1: '100 Market St',
      city: 'St Louis',
      state: 'MO',
      postal_code: '63101',
      country: 'US',
    },
  }),
}).then((r) => r.json());

if (co.error) {
  say(`   FAIL  ${co.error}`);
  process.exit(1);
}
say(`   order ${co.orderId}, total $${(co.amount.total / 100).toFixed(2)}`);

say('\n2. pay');
const pi = co.clientSecret.split('_secret_')[0];
const paid = await fetch(`https://api.stripe.com/v1/payment_intents/${pi}/confirm`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${SK}`, 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    payment_method: 'pm_card_visa',
    return_url: 'https://brettboggs.dev/store/thanks/',
  }).toString(),
}).then((r) => r.json());

if (paid.status !== 'succeeded') {
  say(`   FAIL  ${paid.error ? paid.error.message : paid.status}`);
  process.exit(1);
}
say(`   ${paid.status}, captured $${(paid.amount_received / 100).toFixed(2)}`);

say('\n3. waiting for Stripe to call the webhook by itself');
say(`   order id: ${co.orderId}`);
say('   check with:');
say(
  `   npx wrangler d1 execute brettboggs-store --remote --command "SELECT status,note FROM orders WHERE id='${co.orderId}';"`,
);
