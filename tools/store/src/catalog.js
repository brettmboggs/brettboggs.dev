// The catalog, read from the database.
//
// This used to be a hand-edited object, which meant every new photograph was a
// code change, a build and a deploy, with Brett waiting on someone else to do
// it. Pictures, prices, descriptions and what is published now live in D1 and
// are edited from /admin on the site.
//
// What stays in code is pricing POLICY rather than pricing: the size ladder,
// what each size costs to print, and the tier multipliers. Those are decisions
// about the shape of the business, they change rarely, and getting one wrong
// silently is expensive. A per-image override lives in the database for when a
// particular picture should not follow the ladder.

// --- Sizes -------------------------------------------------------------------
//
// SHIPPING IS INCLUDED IN EVERY PRICE. The buyer is told shipping is free and it
// genuinely is. `cost` is what Prodigi charges to print and `ship` to deliver in
// the US, both quoted 2026-09-01, and `base` already covers both.
//
// US only for now: Prodigi prints regionally and most countries are cheaper,
// but Canada is an outlier that would swallow a print's margin under a blanket
// free shipping promise.
//
// `base` is deliberately NOT cost-plus. An 8x10 costs $9.00 to print and a
// 24x36 costs $22.00, so cost-plus would price a wall-sized piece at barely
// more than a small one, which is not how anyone buys a photograph.
export const SIZES = {
  '8x10': { sku: 'GLOBAL-FAP-8X10', dims: { w: 8, h: 10, units: 'in' }, aspect: '4:5', base: 6000, cost: 900, ship: 1185 },
  '12x18': { sku: 'GLOBAL-FAP-12X18', dims: { w: 12, h: 18, units: 'in' }, aspect: '2:3', base: 9000, cost: 1400, ship: 1295 },
  '16x24': { sku: 'GLOBAL-FAP-16X24', dims: { w: 16, h: 24, units: 'in' }, aspect: '2:3', base: 13500, cost: 1500, ship: 1295 },
  '20x30': { sku: 'GLOBAL-FAP-20X30', dims: { w: 20, h: 30, units: 'in' }, aspect: '2:3', base: 19000, cost: 2000, ship: 1400 },
  '24x36': { sku: 'GLOBAL-FAP-24X36', dims: { w: 24, h: 36, units: 'in' }, aspect: '2:3', base: 26000, cost: 2200, ship: 1590 },
};

export const PAPER = 'Enhanced Matte Art paper, 200gsm';

// A tier is a claim about the picture, not the object. Same paper, same printer,
// same cost, so the only honest reasons to charge more are demand or genuine
// scarcity. `limit` is a hard cap, enforced against orders rather than merely
// advertised, because an edition that is not counted is a lie.
export const TIERS = {
  standard: { label: 'Open edition', multiplier: 1 },
  premium: { label: 'Open edition', multiplier: 1.35 },
  limited: { label: 'Limited edition of 25', multiplier: 2.1, limit: 25 },
};

export const KINDS_REQUIRING_SHIPPING = new Set(['pod']);

/** Rounded to the nearest $5 so a tier multiplier never produces $162.37. */
const round5 = (cents) => Math.round(cents / 500) * 500;

/** Which sizes suit a picture of this shape. A 6:1 panorama gets none of them. */
export function sizesForAspect(aspect) {
  return Object.entries(SIZES)
    .filter(([, s]) => s.aspect === aspect)
    .map(([id]) => id);
}

export function priceFor(sizeId, tierName, overrides = {}) {
  if (overrides[sizeId] != null) return overrides[sizeId];
  const size = SIZES[sizeId];
  const tier = TIERS[tierName] ?? TIERS.standard;
  return round5(size.base * tier.multiplier);
}

// --- Reading the catalog -----------------------------------------------------

/**
 * Expands live images into products, one per size, plus any live goods.
 * `all` includes drafts, which only the admin panel asks for.
 */
export async function loadProducts(db, { all = false } = {}) {
  const where = all ? '' : `WHERE status = 'live'`;

  const [images, prices, goods] = await Promise.all([
    db.prepare(`SELECT * FROM images ${where} ORDER BY sort_order, created_at`).all(),
    db.prepare(`SELECT * FROM image_prices`).all(),
    db.prepare(`SELECT * FROM goods ${where} ORDER BY sort_order, created_at`).all(),
  ]);

  const overridesByImage = {};
  for (const row of prices.results ?? []) {
    (overridesByImage[row.image_id] ??= {})[row.size_id] = row.price;
  }

  const products = {};

  for (const img of images.results ?? []) {
    const tier = TIERS[img.tier] ?? TIERS.standard;
    const sizes = safeParse(img.sizes_json) ?? sizesForAspect(img.aspect);

    for (const sizeId of sizes) {
      const size = SIZES[sizeId];
      if (!size) continue;

      products[`${img.id}-${sizeId}`] = {
        live: img.status === 'live',
        name: `${img.title}, ${size.dims.w} x ${size.dims.h}`,
        kind: 'pod',
        price: priceFor(sizeId, img.tier, overridesByImage[img.id] ?? {}),
        cost: size.cost,
        sku: size.sku,
        dims: size.dims,
        material: `${PAPER}, ${size.dims.w} x ${size.dims.h} in`,
        blurb: img.blurb ?? '',
        imageId: img.id,
        imageTitle: img.title,
        sizeId,
        printKey: img.print_key,
        tier: img.tier,
        tierLabel: tier.label,
        editionLimit: tier.limit ?? null,
      };
    }
  }

  for (const g of goods.results ?? []) {
    products[g.id] = {
      live: g.status === 'live',
      name: g.name,
      kind: g.kind,
      price: g.price,
      cost: g.cost ?? 0,
      sku: g.sku,
      dims: null,
      material: g.material,
      blurb: g.blurb ?? '',
      imageId: null,
      imageTitle: null,
      sizeId: null,
      printKey: g.asset_key,
      tierLabel: null,
      editionLimit: null,
    };
  }

  return products;
}

export async function publicCatalog(db) {
  const products = await loadProducts(db);
  return Object.entries(products)
    .filter(([, p]) => p.live)
    .map(([id, p]) => ({
      id,
      name: p.name,
      kind: p.kind,
      price: p.price,
      blurb: p.blurb,
      // Sent so the store can draw the thing at true scale. A buyer who cannot
      // picture 16 by 24 inches is being asked to guess.
      dims: p.dims,
      material: p.material,
      tierLabel: p.tierLabel,
      editionLimit: p.editionLimit,
      imageId: p.imageId,
      imageTitle: p.imageTitle,
      sizeId: p.sizeId,
    }));
}

// Turns an untrusted [{id, qty}] cart into a priced, frozen set of line items.
// Throws on anything it does not recognise rather than guessing.
export async function priceCart(db, cart) {
  if (!Array.isArray(cart) || cart.length === 0) throw new CartError('Cart is empty.');
  if (cart.length > 20) throw new CartError('Too many line items.');

  const products = await loadProducts(db);
  const items = [];
  let subtotal = 0;
  let requiresShipping = false;

  for (const raw of cart) {
    const product = products[raw?.id];
    if (!product || !product.live) {
      throw new CartError(`Unknown or unavailable item: ${String(raw?.id).slice(0, 40)}`);
    }

    // Strict: the quantity must already BE a number. No coercion, because
    // Number('0x10') is 16 and a cart is not the place to discover that.
    const qty = raw?.qty;
    if (typeof qty !== 'number' || !Number.isInteger(qty) || qty < 1 || qty > 10) {
      throw new CartError(`Quantity for ${raw.id} must be a whole number from 1 to 10.`);
    }

    const lineTotal = product.price * qty;
    subtotal += lineTotal;
    if (KINDS_REQUIRING_SHIPPING.has(product.kind)) requiresShipping = true;

    items.push({
      id: raw.id,
      name: product.name,
      kind: product.kind,
      sku: product.sku ?? null,
      printKey: product.printKey ?? null,
      // Carried onto the frozen line so an order records what it cost us on the
      // day it was placed, not what the catalog says months later.
      cost: product.cost ?? 0,
      imageId: product.imageId ?? null,
      editionLimit: product.editionLimit ?? null,
      unitPrice: product.price,
      qty,
      lineTotal,
    });
  }

  // Shipping depends on the whole cart in ways no per-item figure can express:
  // two prints share one tube, but a print and a deck ship as two parcels from
  // two labs. It is quoted live and added by the caller.
  //
  // Tax is a hard zero by Brett's decision: reflected in prices, not charged.
  const tax = 0;

  if (subtotal < 50) throw new CartError('Order total is below the minimum Stripe will charge.');
  if (subtotal > 500000) throw new CartError('Order total is above the ceiling this store will take.');

  return { items, subtotal, tax, requiresShipping };
}

/**
 * A product with no print file must never be sold for real money. Test mode is
 * fine: the store page says plainly that nothing ships.
 */
export function assertSellable(items, env) {
  const liveMoney = Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_SECRET_KEY.startsWith('sk_live'));
  if (!liveMoney) return;

  for (const item of items) {
    if (item.kind === 'pod' && !item.printKey) {
      throw new CartError(`${item.name} has no print file yet and cannot be ordered.`);
    }
  }
}

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

export class CartError extends Error {}
