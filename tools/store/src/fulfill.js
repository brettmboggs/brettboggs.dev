// Fulfillment. Called only from the webhook, only after Stripe confirms the
// money landed and the captured amount matched what we priced.
//
// Two kinds, because Brett holds no stock and ships nothing himself:
//
//   digital  a signed, expiring link to the print-resolution file in R2
//   pod      an order handed to the print partner, who prints and ships
//
// Every adapter must be safe to call twice. The webhook layer already claims
// each event before doing work, but a partner API can time out after it has
// actually accepted the order, so each adapter carries our order id as its own
// idempotency reference and checks before creating anything.

import { newId } from './orders.js';

// Each line is fulfilled independently. An order can mix a download that can be
// delivered this second with a print that depends on a third party being awake,
// and one of those failing must not hold the other hostage: the buyer paid for
// both. Anything that succeeded is marked 'sent', and because every adapter only
// touches rows that are not already 'sent', a later retry picks up exactly what
// is left and never re-delivers what already went out.
//
// Throws if anything failed, so the webhook returns non-2xx and Stripe retries.
export async function fulfillOrder(env, order, items) {
  const shipping = order.shipping_json ? JSON.parse(order.shipping_json) : null;
  const failed = [];

  for (const item of items) {
    try {
      switch (item.kind) {
        case 'digital':
          await fulfillDigital(env, order, item);
          break;
        case 'pod':
          await fulfillPod(env, order, item, shipping);
          break;
        default:
          throw new Error(`No fulfillment adapter for kind "${item.kind}"`);
      }
    } catch (err) {
      const reason = err && err.message ? err.message : String(err);
      failed.push({ id: item.id, reason });
      await env.DB.prepare(
        `UPDATE fulfillments
            SET status = 'failed', detail_json = ?, updated_at = ?
          WHERE order_id = ? AND product_id = ? AND status <> 'sent'`,
      )
        .bind(JSON.stringify({ error: reason }), new Date().toISOString(), order.id, item.id)
        .run();
    }
  }

  if (failed.length) {
    const err = new Error(
      `${failed.length} of ${items.length} lines failed: ` +
        failed.map((f) => `${f.id} (${f.reason})`).join('; '),
    );
    err.partial = failed.length < items.length;
    throw err;
  }
}

// --- Digital -----------------------------------------------------------------

const DOWNLOAD_TTL_HOURS = 72;
const DOWNLOAD_MAX_USES = 5;

async function fulfillDigital(env, order, item) {
  // A random token, not a signed URL to R2 directly. The token is ours, so we
  // can expire it, cap its uses, and revoke it on a refund or a chargeback.
  // A raw R2 presigned URL can do none of those things once it is issued.
  const token = newId('dl');
  const expiresAt = new Date(Date.now() + DOWNLOAD_TTL_HOURS * 3600 * 1000).toISOString();

  await env.DB.prepare(
    `UPDATE fulfillments
        SET status = 'sent', detail_json = ?, updated_at = ?
      WHERE order_id = ? AND product_id = ? AND status <> 'sent'`,
  )
    .bind(
      JSON.stringify({ token, expiresAt, maxUses: DOWNLOAD_MAX_USES, uses: 0 }),
      new Date().toISOString(),
      order.id,
      item.id,
    )
    .run();

  // TODO(delivery): email the link. Until an email sender is wired up, the
  // token is recorded and retrievable, and Stripe has already sent the buyer a
  // receipt. Deliberately not silently dropped: an order stays visible as
  // 'sent' with a token nobody has been given, which is a state Brett can see.
}

// --- Print on demand ---------------------------------------------------------

async function fulfillPod(env, order, item, shipping) {
  if (!shipping) throw new Error(`Physical item ${item.id} on order ${order.id} has no shipping address`);
  if (!env.POD_API_KEY) throw new Error('POD_API_KEY is not configured');

  // Test money must never buy a real parcel.
  //
  // The print partner's sandbox and production keys look identical, and the
  // only thing separating a rehearsal from a printed deck landing on someone's
  // doormat is which one is loaded. If Stripe is in test mode, refuse to talk
  // to a production printer at all, no matter how the config is set.
  const stripeIsTest = !env.STRIPE_SECRET_KEY?.startsWith('sk_live');
  const podIsProduction = env.POD_SANDBOX !== 'true';
  if (stripeIsTest && podIsProduction) {
    throw new Error(
      'Refusing to place a real print order from a Stripe test payment. ' +
        'Either use a sandbox print key with POD_SANDBOX=true, or go live on both.',
    );
  }

  const provider = getPodProvider(env);
  const reference = `${order.id}:${item.id}`;

  // Ask before creating. If a previous attempt succeeded and then the Worker
  // died before writing the result, this finds it instead of printing twice.
  const existing = await provider.findOrder(env, reference);
  const remote = existing || (await provider.createOrder(env, { reference, item, shipping, email: order.email }));

  await env.DB.prepare(
    `UPDATE fulfillments
        SET status = 'sent', detail_json = ?, updated_at = ?
      WHERE order_id = ? AND product_id = ? AND status <> 'sent'`,
  )
    .bind(
      JSON.stringify({ provider: provider.name, remoteId: remote.id, reference, reused: Boolean(existing) }),
      new Date().toISOString(),
      order.id,
      item.id,
    )
    .run();
}

// Provider is behind an interface on purpose. Prodigi, Printful, Gelato and the
// card printers all differ, and the choice should not be able to leak into the
// webhook or the order code. Swapping providers means writing one of these.
function getPodProvider(env) {
  switch (env.POD_PROVIDER) {
    case 'prodigi':
      return PRODIGI;
    default:
      throw new Error(`Unknown POD_PROVIDER "${env.POD_PROVIDER}"`);
  }
}

// Prodigi: global print and ship, no minimums, a real REST API, and a sandbox
// that is a genuinely separate account from production. The SKUs below are real
// and confirmed against that sandbox catalogue.
const PRODIGI = {
  name: 'prodigi',

  // Prodigi ACCEPTS ?merchantReference= and then ignores it: the response is
  // the same list of recent orders whatever you pass, including for a reference
  // that cannot exist. Trusting it meant taking orders[0] and concluding the
  // order was already placed, which would mark a paid order as sent while the
  // printer had never heard of it.
  //
  // So the filtering happens here, on our side, over a page of recent orders.
  // We only ever look immediately before creating, so a genuine duplicate is
  // always recent. If it is somehow older than this window we create a second
  // order, which is a bad day, but a far better one than never printing at all.
  async findOrder(env, reference) {
    const res = await fetch(`${prodigiBase(env)}/v4.0/Orders?top=100`, {
      headers: { 'X-API-Key': env.POD_API_KEY },
    });
    if (!res.ok) throw new Error(`Prodigi lookup failed: ${res.status}`);
    const body = await res.json();
    const found = (body.orders ?? []).find((o) => o.merchantReference === reference);
    return found ? { id: found.id } : null;
  },

  async createOrder(env, { reference, item, shipping, email }) {
    const sku = PROD_SKUS[item.id] ?? printSkuFor(item);
    if (!sku) throw new Error(`No print SKU mapped for product ${item.id}`);
    if (!sku.assetUrl) {
      throw new Error(`No print file for ${item.id}. The image needs a hosted, signed file before it can be printed.`);
    }

    const res = await fetch(`${prodigiBase(env)}/v4.0/Orders`, {
      method: 'POST',
      headers: { 'X-API-Key': env.POD_API_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        merchantReference: reference,
        shippingMethod: 'Standard',
        recipient: {
          name: shipping.name,
          email,
          address: {
            line1: shipping.address.line1,
            line2: shipping.address.line2,
            postalOrZipCode: shipping.address.postal_code,
            townOrCity: shipping.address.city,
            stateOrCounty: shipping.address.state,
            countryCode: shipping.address.country,
          },
        },
        items: [
          {
            sku: sku.sku,
            copies: item.qty,
            sizing: sku.sizing,
            // The print file is fetched by the printer from a URL we sign. It
            // is never in public/ and never reachable without the signature.
            assets: [{ printArea: 'default', url: sku.assetUrl }],
          },
        ],
      }),
    });

    if (!res.ok) throw new Error(`Prodigi create failed: ${res.status} ${await res.text()}`);
    const body = await res.json();
    return { id: body.order.id };
  },
};

const prodigiBase = (env) =>
  env.POD_SANDBOX === 'true' ? 'https://api.sandbox.prodigi.com' : 'https://api.prodigi.com';

// Product id -> printer SKU. These SKUs are REAL, confirmed against Prodigi's
// sandbox catalogue. The assetUrl values are not: each must point at a signed
// print-resolution file in R2 before anything can be turned on.
//
// PLAY-CARD is "Personalised Playing Cards 6x9cm / 3x4"" and exposes exactly
// ONE print area. Prodigi puts your single image on the back of every card and
// prints its own standard faces. A deck with custom faces cannot be made here.
//
// Prodigi has no 13x19. GLOBAL-FAP-16X24 is 40x60cm / 16x24in on Enhanced Matte
// Art 200gsm; GLOBAL-FAP-A2 is 42x59.4cm. The catalog still calls this product
// "13 x 19", so either the name or the SKU has to change before it sells.
// Products needing a hand-written SKU. Empty: prints carry their own SKU and
// print file, both set from the admin panel.
const PROD_SKUS = {};

// Prints carry their SKU on the line item, so they need no hand-written entry.
// What they still lack is a hosted print file per image, which is the next
// piece of work. Returning a null assetUrl makes that failure loud and specific
// rather than a confusing rejection from the printer.
function printSkuFor(item) {
  return item.sku ? { sku: item.sku, sizing: 'fillPrintArea', assetUrl: null } : null;
}
