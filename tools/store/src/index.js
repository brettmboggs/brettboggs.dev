// Store API for brettboggs.dev, as a Cloudflare Worker.
//
// GitHub Pages is static and cannot answer a POST or hold a secret, so the
// three things a store needs a server for live here and nowhere else:
//   GET  /catalog   what is for sale, priced by the server
//   POST /checkout  price a cart, record an order, open a PaymentIntent
//   POST /webhook   Stripe tells us what actually happened, and we fulfill
//
// The rule the whole design hangs on: FULFILLMENT HAPPENS ONLY IN THE WEBHOOK.
// The browser being redirected to a success page is not proof of anything. A
// customer can close the tab, and a stranger can visit the success URL. Stripe
// calling this Worker with a signed event is the only evidence that counts.

import { publicCatalog, priceCart, assertSellable, CartError } from './catalog.js';
import { createPaymentIntent, verifyWebhook, SignatureError, StripeError } from './stripe.js';
import {
  newId,
  createOrder,
  attachPaymentIntent,
  getOrderByPaymentIntent,
  setOrderStatus,
  claimEvent,
  completeEvent,
  recordFulfillments,
} from './orders.js';
import { fulfillOrder } from './fulfill.js';
import { quoteShipping, ShippingError } from './shipping.js';

const ALLOWED_ORIGINS = new Set(['https://brettboggs.dev', 'http://localhost:4321']);

function corsHeaders(request) {
  const origin = request.headers.get('Origin');
  return ALLOWED_ORIGINS.has(origin)
    ? {
        'Access-Control-Allow-Origin': origin,
        'Access-Control-Allow-Methods': 'GET, POST, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type',
        Vary: 'Origin',
      }
    : { Vary: 'Origin' };
}

function json(body, status, request) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders(request) },
  });
}

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(request) });
    }

    try {
      if (url.pathname === '/catalog' && request.method === 'GET') {
        return json({ products: publicCatalog() }, 200, request);
      }
      if (url.pathname === '/checkout' && request.method === 'POST') {
        return await handleCheckout(request, env);
      }
      if (url.pathname === '/webhook' && request.method === 'POST') {
        return await handleWebhook(request, env, ctx);
      }
      if (url.pathname === '/health') {
        const live = env.STRIPE_SECRET_KEY ? env.STRIPE_SECRET_KEY.startsWith('sk_live') : false;
        return json({ ok: true, mode: live ? 'live' : 'test' }, 200, request);
      }
      return json({ error: 'Not found' }, 404, request);
    } catch (err) {
      // Never leak internals to the browser. The detail goes to the log.
      console.error('unhandled', err && err.stack ? err.stack : err);
      return json({ error: 'Something went wrong.' }, 500, request);
    }
  },
};

// --- Checkout ----------------------------------------------------------------

async function handleCheckout(request, env) {
  let body;
  try {
    body = await request.json();
  } catch {
    return json({ error: 'Expected JSON.' }, 400, request);
  }

  const email = typeof body.email === 'string' ? body.email.trim().toLowerCase() : '';
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || email.length > 254) {
    return json({ error: 'A valid email address is required.' }, 400, request);
  }

  let priced;
  try {
    priced = priceCart(body.items);
    assertSellable(priced.items, env);
  } catch (err) {
    if (err instanceof CartError) return json({ error: err.message }, 400, request);
    throw err;
  }

  let shippingAddress = null;
  // Free to the buyer, always. Kept as an explicit zero rather than removed, so
  // the order record and the receipt both still show a shipping line of $0.00.
  const shippingCost = 0;
  let costShip = null;
  if (priced.requiresShipping) {
    shippingAddress = normalizeAddress(body.shipping);
    if (!shippingAddress) {
      return json(
        { error: 'This order contains a physical item, so a shipping address is required.' },
        400,
        request,
      );
    }

    // Shipping is included in every price, so the buyer is charged nothing for
    // it. We still ask the printer what it will cost us, purely to record the
    // real margin on the order.
    //
    // This must NOT block a sale. The buyer's total does not depend on the
    // answer, so a printer outage costs us a row of bookkeeping, not an order.
    try {
      costShip = await quoteShipping(env, priced.items, shippingAddress);
    } catch (err) {
      if (err instanceof ShippingError) {
        console.warn('shipping cost unknown for this order:', err.message);
      } else {
        throw err;
      }
    }
  }

  const costPrint = priced.items.reduce((sum, i) => sum + (i.cost ?? 0) * i.qty, 0);
  const total = priced.subtotal + shippingCost + priced.tax;

  const orderId = newId('ord');
  await createOrder(env.DB, {
    id: orderId,
    email,
    shippingAddress,
    items: priced.items,
    subtotal: priced.subtotal,
    shipping: shippingCost,
    tax: priced.tax,
    total,
    costPrint,
    costShip,
    requiresShipping: priced.requiresShipping,
  });

  const intentParams = {
    amount: total,
    currency: 'usd',
    receipt_email: email,
    // The order id travels with the payment, so the webhook can find its way
    // home even if our own write raced or failed.
    metadata: { order_id: orderId },
    // Cards only, deliberately.
    //
    // Stripe's automatic payment methods would also offer ACH bank debits and
    // buy-now-pay-later. Those can report 'succeeded' and then reverse days
    // later, after a deck of cards has already been printed and posted. A card
    // is authorized and captured before 'succeeded' fires, so "paid" really
    // means paid. Apple Pay and Google Pay both arrive as 'card'. Link was here
    // too and was dropped: it is not activated on the account, so it only added
    // a wallet banner nobody could use.
    //
    // This governs what can be CHARGED. It does not govern what the Payment
    // Element draws: in test mode Stripe also shows tabs for methods enabled on
    // the account, which is why bank debit and Klarna can appear with promo
    // badges. Those are turned off in the Stripe Dashboard under Settings,
    // Payment methods, not here. Confirming one would fail against this list.
    //
    // Widening this is a one-line change, but only widen it to methods that
    // cannot reverse after fulfillment, or move fulfillment behind a hold.
    payment_method_types: ['card'],
  };
  if (shippingAddress) {
    intentParams.shipping = { name: shippingAddress.name, address: shippingAddress.address };
  }

  let intent;
  try {
    // Keyed on our order id: a retry of this exact checkout can never open a
    // second PaymentIntent.
    intent = await createPaymentIntent(env, intentParams, orderId);
  } catch (err) {
    const why = err instanceof StripeError ? err.message : 'intent creation failed';
    await setOrderStatus(env.DB, orderId, 'failed', why);
    throw err;
  }

  await attachPaymentIntent(env.DB, orderId, intent.id);

  // clientSecret is safe to hand to the browser. It authorizes confirming this
  // one payment and nothing else. The secret key never leaves the Worker.
  return json(
    {
      orderId,
      clientSecret: intent.client_secret,
      amount: {
        subtotal: priced.subtotal,
        shipping: shippingCost,
        tax: priced.tax,
        total,
      },
      items: priced.items,
    },
    200,
    request,
  );
}

function normalizeAddress(raw) {
  if (!raw || typeof raw !== 'object') return null;
  const str = (v, max) => (typeof v === 'string' && v.trim() ? v.trim().slice(0, max) : null);

  const name = str(raw.name, 100);
  const line1 = str(raw.line1, 200);
  const city = str(raw.city, 100);
  const state = str(raw.state, 50);
  const postal = str(raw.postal_code, 20);
  const countryRaw = str(raw.country, 2);
  const country = countryRaw ? countryRaw.toUpperCase() : 'US';

  if (!name || !line1 || !city || !state || !postal) return null;
  return {
    name,
    address: { line1, line2: str(raw.line2, 200), city, state, postal_code: postal, country },
  };
}

// --- Webhook -----------------------------------------------------------------

async function handleWebhook(request, env, ctx) {
  // Must be the raw bytes. Parsing and re-serializing changes the text and the
  // signature will not match.
  const raw = await request.text();

  let event;
  try {
    event = await verifyWebhook(raw, request.headers.get('Stripe-Signature'), env.STRIPE_WEBHOOK_SECRET);
  } catch (err) {
    if (err instanceof SignatureError) {
      console.warn('rejected webhook:', err.message);
      return new Response('Invalid signature', { status: 400 });
    }
    throw err;
  }

  const claim = await claimEvent(env.DB, event.id, event.type);
  if (!claim.claimed) {
    // Duplicate of finished work: acknowledge so Stripe stops retrying.
    if (claim.reason === 'duplicate') return new Response('Already handled', { status: 200 });
    // Still in flight elsewhere: ask Stripe to come back later.
    return new Response('In flight, retry', { status: 409 });
  }

  try {
    const orderId = await applyEvent(event, env, ctx);
    await completeEvent(env.DB, event.id, orderId);
    return new Response('ok', { status: 200 });
  } catch (err) {
    console.error('webhook handling failed', event.id, err && err.stack ? err.stack : err);
    await completeEvent(env.DB, event.id, null, 'failed');
    // 500 so Stripe retries. The stale-claim takeover in claimEvent means a
    // retry can pick this up again rather than being locked out.
    return new Response('Handler failed', { status: 500 });
  }
}

async function applyEvent(event, env, ctx) {
  const object = event.data.object;

  switch (event.type) {
    case 'payment_intent.succeeded': {
      const order = await getOrderByPaymentIntent(env.DB, object.id);
      if (!order) throw new Error(`No order for ${object.id}`);
      if (order.status === 'fulfilled') return order.id;

      // Defensive: the amount Stripe captured must equal the amount we priced.
      // A mismatch means something is wrong upstream, so the order is held for
      // review rather than fulfilled.
      if (object.amount_received !== order.amount_total) {
        await setOrderStatus(
          env.DB,
          order.id,
          'review',
          `Captured ${object.amount_received} but priced ${order.amount_total}`,
        );
        return order.id;
      }

      await setOrderStatus(env.DB, order.id, 'paid');
      const items = JSON.parse(order.items_json);
      await recordFulfillments(env.DB, order.id, items);

      try {
        await fulfillOrder(env, order, items);
      } catch (err) {
        // Some or all lines did not go out. Whatever DID go out is already
        // recorded as sent. Leave the order visibly short of 'fulfilled' with
        // the reason on it, and rethrow so Stripe retries the rest.
        await setOrderStatus(env.DB, order.id, err.partial ? 'partial' : 'paid', err.message);
        throw err;
      }

      await setOrderStatus(env.DB, order.id, 'fulfilled');
      return order.id;
    }

    case 'payment_intent.payment_failed': {
      const order = await getOrderByPaymentIntent(env.DB, object.id);
      if (order) {
        const why = object.last_payment_error ? object.last_payment_error.message : null;
        await setOrderStatus(env.DB, order.id, 'failed', why);
      }
      return order ? order.id : null;
    }

    case 'charge.refunded':
    case 'charge.dispute.created': {
      const order = await getOrderByPaymentIntent(env.DB, object.payment_intent);
      if (order) {
        const next = event.type === 'charge.refunded' ? 'refunded' : 'review';
        await setOrderStatus(env.DB, order.id, next, event.type);
      }
      return order ? order.id : null;
    }

    default:
      // Unrecognised events are acknowledged, not errors. Stripe sends plenty
      // we did not subscribe to, and retrying those forever helps nobody.
      return null;
  }
}
