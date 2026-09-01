# Store

The part of brettboggs.dev that takes money. GitHub Pages is static, cannot
answer a POST, and cannot hold a secret, so this runs on Cloudflare Workers
alongside `tools/mcp`. It is the only other piece of the site not on Pages.

Nothing is for sale yet. Every product in `src/catalog.js` is `live: false`,
which means it will not price, will not appear in the catalog, and is rejected
at checkout. The store cannot sell anything until a product is turned on by
name.

## The one rule

**Fulfillment happens only in the webhook.**

The browser landing on a success page proves nothing. The customer can close
the tab before it loads, and a stranger can visit that URL directly. The only
evidence that money moved is Stripe calling this Worker with a signed event.
Everything downstream of payment hangs off `handleWebhook`, never off the
browser.

## How the pieces fit

```
browser                     this Worker                   Stripe
   |                             |                           |
   |-- POST /checkout ---------->|                           |
   |   (product ids + qty,       |-- price the cart here --->|
   |    never a price)           |   create PaymentIntent    |
   |<-- clientSecret ------------|<--------------------------|
   |                             |                           |
   |-- card details ------------------------------------->   |  (Stripe iframe,
   |                             |                           |   never touches us)
   |                             |<-- POST /webhook ---------|
   |                             |    signed, verified,      |
   |                             |    idempotent, then       |
   |                             |    fulfilled              |
```

Files:

| File | What it holds |
|---|---|
| `src/catalog.js` | The only place a price exists. Server side, always. |
| `src/stripe.js` | Stripe REST calls and webhook signature verification. |
| `src/orders.js` | Order records and the webhook idempotency claim. |
| `src/fulfill.js` | Digital downloads and the print partner. |
| `src/index.js` | Routing, checkout, webhook. |
| `schema.sql` | D1 tables. Every amount is integer cents. |

## What protects the money

Four things, all tested locally and all worth knowing by name:

1. **Prices are server side.** The browser sends ids and quantities. If it
   sends a price too, it is ignored. Quantities must already be numbers, not
   strings, because `Number('0x10')` is 16 and a cart is no place to find that
   out.
2. **Idempotency keys on every Stripe write.** The PaymentIntent is keyed on
   our own order id, so a retried checkout returns the original payment rather
   than opening a second one. This is what makes a double charge a non-event.
3. **Webhook signatures are verified.** HMAC-SHA256 over `timestamp.body` with
   the endpoint secret, compared in constant time, with a five minute replay
   window. Without this, anyone who learns the URL can send a fake "payment
   succeeded" and be shipped goods for free.
4. **Every event is claimed before work happens.** Stripe retries on any
   non-2xx and can legitimately deliver the same event twice. The claim in
   `processed_events` means three deliveries produce one fulfillment. A claim
   left stranded by a crash can be taken over after fifteen minutes, so a
   failure cannot strand an order forever.

Plus two guards that are not about attackers:

- If Stripe reports a captured amount that does not match what we priced, the
  order goes to `review` and nothing is fulfilled.
- Lines are fulfilled independently. A cart can hold a download that goes out
  instantly and a print that depends on a third party being awake, and one
  failing must not hold the other hostage. Whatever succeeded is marked `sent`,
  the order sits at `partial` with the reason on it, and a retry picks up only
  what is left.

## What things cost

Quoted from Prodigi 2026-09-01, shipped to the US. These are wholesale, what
Brett pays. Re-quote before trusting them; printers move prices.

| | print | ship 1 | ship 2 | ship 3 |
|---|---|---|---|---|
| PLAY-CARD (deck) | $10.83 | $12.12 | $13.47 | $14.82 |
| GLOBAL-FAP-16X24 | $15.00 | $12.95 | $12.95 | |

Two things that flat-rate shipping cannot express, and which is why the store
quotes it live instead:

- **Two prints ship for the same as one.** They share a tube.
- **A deck and a print cost $25.07 to ship**, because they come from two
  different labs as two parcels. Nearly the sum, not the max.

The buyer is charged exactly what the printer charges for shipping. No markup
hides there; if a product needs margin, its price should say so.

Margin at the placeholder prices, after Stripe takes 2.9% + 30c:

| order | buyer pays | Brett pays | net |
|---|---|---|---|
| 1 deck at $22 | $34.12 | $22.95 | about $9.88 |
| 1 print at $120 | $132.95 | $27.95 | about $101.14 |

## Testing it against the real Stripe sandbox

`test-payflow.mjs` runs the whole thing: creates a real PaymentIntent, confirms
it with Stripe's canned 4242 card, then signs and delivers the webhook twice to
prove one payment fulfills exactly once.

```
node tools/store/test-payflow.mjs
```

A digital-only cart should end `fulfilled`:

```
CART='[{"id":"print-file-eclipse","qty":1}]' node tools/store/test-payflow.mjs
```

Anything printed will end `partial` until `POD_API_KEY` exists, which is
correct, not broken. That run wants `EXPECT_WEBHOOK=500`.

Products must be `live: true` in `src/catalog.js` for any of this to price.

## Running it locally

No Cloudflare account needed for this part. `--local` runs the whole thing,
D1 included, on your machine.

```
cd tools/store
npx wrangler d1 execute brettboggs-store --local --file=schema.sql
npx wrangler dev --local --port 8788
```

`wrangler` is Cloudflare's CLI and `npx` runs it without installing anything
globally.

Local secrets go in `tools/store/.dev.vars`, which is gitignored. It currently
holds a placeholder, so checkout will get as far as Stripe and then fail with
"Invalid API Key", which is the correct behaviour. To take it further, put your
own sandbox secret key in yourself:

```
STRIPE_SECRET_KEY=sk_test_...your sandbox secret...
STRIPE_WEBHOOK_SECRET=whsec_localtestsecret
```

The site needs the matching publishable key in `.env` at the repo root
(`PUBLIC_STRIPE_PK`). Publishable keys are meant to be in the browser bundle.
Secret keys are not, and none of them belong in a committed file.

## Going live, in order

Each step is safe to stop after.

**1. Stripe account.** Sign up at stripe.com and stop there. Do not activate
the account or enter bank details yet. Test mode works immediately and gives
you keys that move no real money. Everything below can be built and broken
repeatedly in test mode.

**2. Cloudflare account.** Free, no card, at dash.cloudflare.com/sign-up. This
is the same account `tools/mcp` has been waiting on.

**3. Create the database and paste its id into `wrangler.toml`:**

```
npx wrangler d1 create brettboggs-store
```

**4. Load the schema into the real database** (same command as local, without
`--local`).

**5. Put the secrets in.** These go into Cloudflare, never into a file:

```
npx wrangler secret put STRIPE_SECRET_KEY
npx wrangler secret put STRIPE_WEBHOOK_SECRET
```

**6. Deploy**, then register the webhook URL in the Stripe dashboard pointing
at `https://brettboggs-store.<subdomain>.workers.dev/webhook`, subscribing to
`payment_intent.succeeded`, `payment_intent.payment_failed`, `charge.refunded`
and `charge.dispute.created`. Stripe shows you the signing secret once, and
that is what step 5 wanted.

**7. Rehearse with the Stripe CLI** before a real card ever appears. It
forwards live test events to your laptop and can fire fake ones on demand,
including failures and disputes.

## Still open

- **The print partner.** `src/fulfill.js` is written against Prodigi as a
  placeholder. The SKUs in `PROD_SKUS` are invented and must be replaced with
  real ones, and every `assetUrl` must point at a signed print file, before
  anything is turned on.
- **Delivery email.** Digital orders record a download token but nothing sends
  it yet. Stripe emails the receipt, so the buyer is not left silent, but the
  link needs a sender.
- **Sales tax.** Currently a hard zero, kept as its own line rather than folded
  into the total so it stays visible. Physical goods shipped into Missouri and
  elsewhere raise a registration question that is a real decision, not a code
  change. Stripe Tax can do the calculation for 0.5% per transaction once that
  decision is made.
- **Print-resolution files must leave `public/`.** The store is pointless while
  the masters are downloadable from the site. See the separate image pass.
