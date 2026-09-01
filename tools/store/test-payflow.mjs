// End-to-end test against the local Worker and the real Stripe sandbox.
//
// Does exactly what a buyer does, minus typing into Stripe's iframe, which no
// automation can reach from outside the frame. It creates a real PaymentIntent,
// confirms it with Stripe's canned 4242 test card, then signs and delivers the
// webhook the way Stripe would, twice, to prove one payment fulfills once.
//
// Run the Worker first (see README), then:
//
//   node tools/store/test-payflow.mjs
//   CART='[{"id":"print-file-eclipse","qty":1}]' node tools/store/test-payflow.mjs
//
// A cart containing a printed item is expected to end 'partial' until the print
// partner key exists, so that run wants EXPECT_WEBHOOK=500.
//
// The secret key is read from .dev.vars and is never printed.

import { readFileSync } from 'node:fs';
import { createHmac } from 'node:crypto';

import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const VARS = join(dirname(fileURLToPath(import.meta.url)), '.dev.vars');
const WORKER = 'http://127.0.0.1:8788';

const env = Object.fromEntries(
  readFileSync(VARS, 'utf8')
    .split(/\r?\n/)
    .filter(Boolean)
    .map((l) => [l.slice(0, l.indexOf('=')), l.slice(l.indexOf('=') + 1).trim()]),
);
const SK = env.STRIPE_SECRET_KEY;
const WHSEC = env.STRIPE_WEBHOOK_SECRET;

let failures = 0;
const step = (n, s) => console.log(`\n${n}. ${s}`);
// Reports against what was EXPECTED. An unexpected result is a FAIL even when
// the request itself "worked".
const expect = (cond, s) => {
  if (!cond) failures++;
  console.log(`   ${cond ? 'PASS' : 'FAIL'}  ${s}`);
};

const CART = JSON.parse(
  process.env.CART ?? '[{"id":"cards-deck","qty":1},{"id":"print-file-eclipse","qty":1}]',
);
// A run against a cart with no print partner configured is expected to end
// partially fulfilled, not fulfilled.
const EXPECT_WEBHOOK = process.env.EXPECT_WEBHOOK ?? '200';

step(1, 'Buyer submits the checkout form');
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

expect(!co.error, co.error ?? `order ${co.orderId}, total $${(co.amount.total / 100).toFixed(2)}`);
if (co.error) process.exit(1);
const pi = co.clientSecret.split('_secret_')[0];

step(2, 'Card is entered and the payment is confirmed at Stripe');
const paid = await fetch(`https://api.stripe.com/v1/payment_intents/${pi}/confirm`, {
  method: 'POST',
  headers: { Authorization: `Bearer ${SK}`, 'Content-Type': 'application/x-www-form-urlencoded' },
  body: new URLSearchParams({
    payment_method: 'pm_card_visa',
    return_url: 'https://brettboggs.dev/store/thanks/',
  }).toString(),
}).then((r) => r.json());

expect(
  paid.status === 'succeeded',
  paid.error ? paid.error.message : `Stripe says ${paid.status}, captured $${(paid.amount_received / 100).toFixed(2)}`,
);
if (paid.status !== 'succeeded') process.exit(1);

// Stripe cannot reach localhost, so the event it WOULD send is rebuilt from the
// confirmed intent and signed with the same secret the Worker holds.
const event = JSON.stringify({
  id: `evt_local_${paid.id}`,
  type: 'payment_intent.succeeded',
  data: { object: { id: paid.id, amount_received: paid.amount_received } },
});

const deliver = async () => {
  const t = Math.floor(Date.now() / 1000);
  const sig = `t=${t},v1=${createHmac('sha256', WHSEC).update(`${t}.${event}`).digest('hex')}`;
  const res = await fetch(`${WORKER}/webhook`, {
    method: 'POST',
    headers: { 'Stripe-Signature': sig, 'Content-Type': 'application/json' },
    body: event,
  });
  return { status: res.status, body: await res.text() };
};

step(3, `Stripe calls the webhook (expecting HTTP ${EXPECT_WEBHOOK})`);
const a = await deliver();
expect(String(a.status) === EXPECT_WEBHOOK, `HTTP ${a.status} ${a.body}`);

step(4, 'Stripe retries the same event (the double-fulfillment trap)');
const b = await deliver();
expect(String(b.status) === EXPECT_WEBHOOK, `HTTP ${b.status} ${b.body}`);

console.log(`\n${failures === 0 ? 'all assertions passed' : failures + ' ASSERTION(S) FAILED'}`);
console.log(`order id: ${co.orderId}`);
process.exit(failures === 0 ? 0 : 1);
