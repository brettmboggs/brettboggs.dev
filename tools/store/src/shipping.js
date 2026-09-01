// Shipping, quoted live from the printer.
//
// A flat per-item figure cannot describe what actually happens. Measured against
// Prodigi on 2026-09-01, shipping to the US:
//
//   1 deck                12.12      2 decks   13.47      3 decks   14.82
//   1 print               12.95      2 prints  12.95   (they share one tube)
//   1 deck + 1 print      25.07             (two labs, two parcels)
//
// So it is neither per item nor per order. The only correct answer is to ask,
// which is cheap because the address is already collected before checkout runs.
//
// The buyer is charged exactly what the printer charges. No markup hidden in
// shipping: if a product needs more margin, its price should say so.

const TIMEOUT_MS = 8000;

export async function quoteShipping(env, items, shippingAddress) {
  const physical = items.filter((i) => i.kind === 'pod');
  if (physical.length === 0) return 0;

  const missing = physical.find((i) => !i.sku);
  if (missing) throw new ShippingError(`No printer SKU for ${missing.id}`);

  const base = env.POD_SANDBOX === 'true' ? 'https://api.sandbox.prodigi.com' : 'https://api.prodigi.com';

  // Do not let a slow printer hang a checkout indefinitely.
  const abort = new AbortController();
  const timer = setTimeout(() => abort.abort(), TIMEOUT_MS);

  let body;
  try {
    const res = await fetch(`${base}/v4.0/quotes`, {
      method: 'POST',
      headers: { 'X-API-Key': env.POD_API_KEY, 'Content-Type': 'application/json' },
      signal: abort.signal,
      body: JSON.stringify({
        shippingMethod: 'Standard',
        destinationCountryCode: shippingAddress.address.country,
        currencyCode: 'usd',
        items: physical.map((i) => ({
          sku: i.sku,
          copies: i.qty,
          attributes: {},
          assets: [{ printArea: 'default' }],
        })),
      }),
    });
    if (!res.ok) throw new ShippingError(`Printer quote failed: ${res.status}`);
    body = await res.json();
  } catch (err) {
    if (err instanceof ShippingError) throw err;
    throw new ShippingError(
      err?.name === 'AbortError' ? 'Printer did not answer in time' : `Printer unreachable: ${err?.message}`,
    );
  } finally {
    clearTimeout(timer);
  }

  const quote = body?.quotes?.[0];
  const amount = quote?.costSummary?.shipping?.amount;
  if (amount === undefined) throw new ShippingError('Printer returned no shipping cost');

  // Quotes come back as decimal strings. Round up to the cent so rounding can
  // never quietly land in the buyer's favour and out of Brett's pocket.
  const cents = Math.ceil(Number(amount) * 100);
  if (!Number.isFinite(cents) || cents < 0) throw new ShippingError('Printer returned an unusable shipping cost');

  return cents;
}

export class ShippingError extends Error {}
