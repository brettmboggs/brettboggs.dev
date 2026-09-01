// Stripe, spoken directly over its REST API.
//
// No SDK on purpose. The Stripe Node library works on Workers but it is a large
// dependency for three calls, and the two things that actually keep this store
// honest (an idempotency key on every write, and a real signature check on
// every webhook) are worth seeing in full rather than trusting to a wrapper.

const API = 'https://api.stripe.com/v1';

// Stripe takes form encoding, not JSON, and expresses nesting with brackets:
//   shipping[address][line1]=100 Main St
//   metadata[order_id]=ord_abc
function formEncode(value, prefix = '', out = new URLSearchParams()) {
  if (value === null || value === undefined) return out;

  if (Array.isArray(value)) {
    value.forEach((v, i) => formEncode(v, `${prefix}[${i}]`, out));
  } else if (typeof value === 'object') {
    for (const [k, v] of Object.entries(value)) {
      formEncode(v, prefix ? `${prefix}[${k}]` : k, out);
    }
  } else {
    out.append(prefix, String(value));
  }
  return out;
}

async function call(env, method, path, body, idempotencyKey) {
  const headers = {
    Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
    'Stripe-Version': '2025-08-27.basil',
  };
  if (body) headers['Content-Type'] = 'application/x-www-form-urlencoded';

  // Every write carries an idempotency key. If the Worker retries, or the
  // network lies about a timeout, Stripe returns the ORIGINAL result instead of
  // creating a second PaymentIntent. This is the single control that makes
  // "customer got charged twice" a non-event.
  if (idempotencyKey) headers['Idempotency-Key'] = idempotencyKey;

  const res = await fetch(`${API}${path}`, {
    method,
    headers,
    body: body ? formEncode(body).toString() : undefined,
  });

  const payload = await res.json();
  if (!res.ok) {
    const err = new StripeError(payload?.error?.message || `Stripe returned ${res.status}`);
    err.status = res.status;
    err.code = payload?.error?.code;
    err.type = payload?.error?.type;
    throw err;
  }
  return payload;
}

export function createPaymentIntent(env, params, idempotencyKey) {
  return call(env, 'POST', '/payment_intents', params, idempotencyKey);
}

export function getPaymentIntent(env, id) {
  return call(env, 'GET', `/payment_intents/${id}`);
}

export class StripeError extends Error {}

// --- Webhook signature verification -----------------------------------------
//
// Without this, anyone who learns the webhook URL can POST a fake "payment
// succeeded" and be sent goods for free. It is the highest-consequence twenty
// lines in the store.
//
// Stripe-Signature looks like: t=1614556800,v1=5257a8...,v1=<older key>
// The signed payload is `${t}.${rawBody}`, HMAC-SHA256 with the endpoint's
// signing secret (whsec_...), compared in constant time.

const TOLERANCE_SECONDS = 300;

export async function verifyWebhook(rawBody, signatureHeader, secret, nowSeconds = Math.floor(Date.now() / 1000)) {
  if (!signatureHeader) throw new SignatureError('Missing Stripe-Signature header.');
  if (!secret) throw new SignatureError('Webhook signing secret is not configured.');

  let timestamp = null;
  const candidates = [];
  for (const part of signatureHeader.split(',')) {
    const idx = part.indexOf('=');
    if (idx === -1) continue;
    const key = part.slice(0, idx).trim();
    const val = part.slice(idx + 1).trim();
    if (key === 't') timestamp = val;
    else if (key === 'v1') candidates.push(val);
  }

  if (!timestamp || candidates.length === 0) throw new SignatureError('Malformed Stripe-Signature header.');

  // Replay window. A signature stays valid forever without this, so a captured
  // request could be replayed at any point in the future.
  const age = Math.abs(nowSeconds - Number(timestamp));
  if (!Number.isFinite(age) || age > TOLERANCE_SECONDS) {
    throw new SignatureError('Signature timestamp is outside the tolerance window.');
  }

  const key = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(secret),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  );
  const mac = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(`${timestamp}.${rawBody}`));
  const expected = [...new Uint8Array(mac)].map((b) => b.toString(16).padStart(2, '0')).join('');

  if (!candidates.some((c) => timingSafeEqual(c, expected))) {
    throw new SignatureError('Signature does not match.');
  }

  return JSON.parse(rawBody);
}

function timingSafeEqual(a, b) {
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

export class SignatureError extends Error {}
