// The catalog. This file is the ONLY place a price exists.
//
// The browser sends product ids and quantities. It never sends a price, and
// nothing the browser sends about money is trusted. Every total is recomputed
// here, server side, on every checkout.
//
// A print is two things, not one: WHICH PICTURE and WHAT SIZE. They are modelled
// as separate axes and multiplied together, because otherwise every new photo
// means hand-writing five near-identical products and every price change means
// editing all of them. Product ids are `image-size`, e.g. `copper-hour-16x24`.
//
// live:false means inert: it will not price, will not appear in the catalog
// response, and is rejected at checkout. Nothing sells until Brett says so.

// --- Sizes -------------------------------------------------------------------
//
// SHIPPING IS INCLUDED IN EVERY PRICE. The buyer is told shipping is free and it
// genuinely is: there is no surcharge anywhere in checkout. `cost` is what
// Prodigi charges to print and `ship` what it charges to deliver in the US, both
// quoted 2026-09-01, and `base` already covers both.
//
// This is why the store is US only for now. Prodigi prints regionally so most
// countries are cheaper, but Canada is an outlier: a deck ships there for $23.35
// against $12.12 here, which would swallow a whole deck's margin. A free
// shipping promise that quietly excludes people is worse than not making it.
//
// `aspect` is the printable shape. A 3:2 photograph fits 12x18, 16x24, 20x30 and
// 24x36 exactly; 8x10 is 4:5 and would have to crop. Sizes are matched to each
// picture's shape rather than offered blindly.
//
// `base` is the open-edition price for an ordinary picture at that size, and it
// is deliberately NOT cost-plus. Printing an 8x10 costs $9.00 and a 24x36 costs
// $22.00, so cost-plus would price a wall-sized print at barely more than a
// small one, which is not how anyone buys a photograph. This ladder is priced on
// presence, checked against the open-edition market: working professionals sit
// between $75 and $500, and the usual advice for an emerging photographer at
// 16x24 is $150 to $300. It sits at the bottom of that on purpose. An unknown
// name selling an open edition should want the first buyer more than the first
// margin.
export const SIZES = {
  '8x10': { sku: 'GLOBAL-FAP-8X10', dims: { w: 8, h: 10, units: 'in' }, aspect: '4:5', base: 6000, cost: 900, ship: 1185 },
  '12x18': { sku: 'GLOBAL-FAP-12X18', dims: { w: 12, h: 18, units: 'in' }, aspect: '2:3', base: 9000, cost: 1400, ship: 1295 },
  '16x24': { sku: 'GLOBAL-FAP-16X24', dims: { w: 16, h: 24, units: 'in' }, aspect: '2:3', base: 13500, cost: 1500, ship: 1295 },
  '20x30': { sku: 'GLOBAL-FAP-20X30', dims: { w: 20, h: 30, units: 'in' }, aspect: '2:3', base: 19000, cost: 2000, ship: 1400 },
  '24x36': { sku: 'GLOBAL-FAP-24X36', dims: { w: 24, h: 36, units: 'in' }, aspect: '2:3', base: 26000, cost: 2200, ship: 1590 },
};

const PAPER = 'Enhanced Matte Art paper, 200gsm';

// --- Tiers -------------------------------------------------------------------
//
// Same paper, same printer, same cost. A tier is a claim about the picture, not
// about the object, so the only honest reasons to charge more are that the work
// is in more demand or that there is deliberately less of it.
//
// `limit` is a hard cap on how many of that image will ever be sold, across all
// sizes. It is enforced against the orders table, not merely advertised. An
// edition that is not counted is a lie.
export const TIERS = {
  standard: { label: 'Open edition', multiplier: 1 },
  premium: { label: 'Open edition', multiplier: 1.35 },
  limited: { label: 'Limited edition of 25', multiplier: 2.1, limit: 25 },
};

// --- Images ------------------------------------------------------------------
//
// Placeholders until Brett names each picture, its tier, and which sizes suit
// its shape. A 6:1 panorama must never be offered at 16x24: the crop would
// either lie about the photograph or arrive with the sky cut off.
export const IMAGES = {
  'copper-hour': {
    live: false,
    title: 'The Copper Hour',
    tier: 'standard',
    sizes: ['12x18', '16x24', '20x30'],
    asset: 'eclipse/copper-hour.tif',
    blurb: 'The lunar eclipse of 27 August 2026.',
  },
};

// --- Standalone goods, which are not image by size ---------------------------
export const GOODS = {
  'cards-deck': {
    live: true,
    name: 'Playing cards',
    kind: 'pod',
    // Prodigi charges $10.83 a deck plus $12.12 to ship it, with no minimum and
    // no stock to carry. Bulk printing is far cheaper per unit, roughly $2 to
    // $3, but means ordering hundreds up front. Art decks retail roughly $10 to
    // $46; $40 delivered sits mid-range once postage is counted.
    price: 4000,
    cost: 1083,
    ship: 1212,
    sku: 'PLAY-CARD',
    dims: { w: 2.5, h: 3.5, units: 'in' },
    material: '54 cards, standard poker size',
    blurb: 'A full deck. Custom faces, custom backs, custom tuck box.',

    // CANNOT BE FULFILLED BY PRODIGI, and must not go on sale until that is
    // resolved.
    //
    // Prodigi's PLAY-CARD takes ONE image, prints it on the back of every card,
    // and supplies its own standard faces in a plain white box. The deck in the
    // product photo has bespoke faces, a bespoke joker and a printed tuck box,
    // none of which that product can make. Selling this through Prodigi would
    // put a picture of one thing next to a description of another.
    //
    // It is live only because the store is in test mode and says so on the
    // page. Before real money: move it to a deck manufacturer that prints full
    // custom decks, or take it down.
    printerCanMake: false,
  },

  'print-file-eclipse': {
    live: false,
    name: 'The Copper Hour, print-ready file',
    kind: 'digital',
    price: 2500,
    cost: 0,
    asset: 'eclipse/copper-hour-3600.tif',
    blurb: 'Full resolution file, licensed for a single personal print.',
  },
};

export const KINDS_REQUIRING_SHIPPING = new Set(['pod']);

/** Rounded to the nearest $5 so a tier multiplier never produces $162.37. */
const round5 = (cents) => Math.round(cents / 500) * 500;

/** Expands the image by size grid into concrete, priced products. */
function buildPrints() {
  const out = {};
  for (const [imageId, image] of Object.entries(IMAGES)) {
    const tier = TIERS[image.tier];
    if (!tier) throw new Error(`Image ${imageId} has unknown tier ${image.tier}`);

    for (const sizeId of image.sizes) {
      const size = SIZES[sizeId];
      if (!size) throw new Error(`Image ${imageId} lists unknown size ${sizeId}`);

      out[`${imageId}-${sizeId}`] = {
        live: image.live,
        name: `${image.title}, ${size.dims.w} x ${size.dims.h}`,
        kind: 'pod',
        price: round5(size.base * tier.multiplier),
        cost: size.cost,
        sku: size.sku,
        dims: size.dims,
        material: `${PAPER}, ${size.dims.w} x ${size.dims.h} in`,
        blurb: image.blurb,
        imageId,
        imageTitle: image.title,
        sizeId,
        asset: image.asset,
        tier: image.tier,
        tierLabel: tier.label,
        editionLimit: tier.limit ?? null,
      };
    }
  }
  return out;
}

export const PRODUCTS = { ...buildPrints(), ...GOODS };


// A limited edition that is not counted is a lie, and the counting is not built
// yet. Until it is, refuse to boot with a limited product switched on, so the
// claim can never reach a buyer ahead of the enforcement.
for (const [id, p] of Object.entries(PRODUCTS)) {
  if (p.live && p.editionLimit) {
    throw new Error(
      `${id} is live with an edition limit, but edition counting is not implemented. ` +
        'Build the enforcement before selling a numbered edition.',
    );
  }
}

export function getProduct(id) {
  const p = PRODUCTS[id];
  return p && p.live ? p : null;
}

export function publicCatalog() {
  return Object.entries(PRODUCTS)
    .filter(([, p]) => p.live)
    .map(([id, p]) => ({
      id,
      name: p.name,
      kind: p.kind,
      price: p.price,
      blurb: p.blurb,
      // Sent so the store can draw the thing at true scale. A buyer who cannot
      // picture 16 by 24 inches is being asked to guess, and guessing is how
      // people end up disappointed by a parcel.
      dims: p.dims ?? null,
      material: p.material ?? null,
      tierLabel: p.tierLabel ?? null,
      editionLimit: p.editionLimit ?? null,
      imageId: p.imageId ?? null,
      // The site groups by these. It never learns where the picture lives: the
      // preview is found by convention at /photo/store/<imageId>.webp, so the
      // Worker stays out of the image business and the site stays out of the
      // pricing business.
      imageTitle: p.imageTitle ?? null,
      sizeId: p.sizeId ?? null,
    }));
}

// Turns an untrusted [{id, qty}] cart into a priced, frozen set of line items.
// Throws on anything it does not recognise rather than guessing.
export function priceCart(cart) {
  if (!Array.isArray(cart) || cart.length === 0) throw new CartError('Cart is empty.');
  if (cart.length > 20) throw new CartError('Too many line items.');

  const items = [];
  let subtotal = 0;
  let requiresShipping = false;

  for (const raw of cart) {
    const product = getProduct(raw?.id);
    if (!product) throw new CartError(`Unknown or unavailable item: ${String(raw?.id).slice(0, 40)}`);

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
      // Carried onto the frozen line item so an order records what it cost us
      // on the day it was placed, not what the catalog says months later.
      cost: product.cost ?? 0,
      imageId: product.imageId ?? null,
      editionLimit: product.editionLimit ?? null,
      unitPrice: product.price,
      qty,
      lineTotal,
    });
  }

  // Shipping is deliberately NOT computed here. It depends on the whole cart in
  // ways no per-item figure can express: two prints share one tube, but a print
  // and a deck ship as two parcels from two different labs. It is quoted live
  // from the printer and added by the caller.
  //
  // Tax is a hard zero by Brett's decision: reflected in the prices rather than
  // charged as a line.
  const tax = 0;

  if (subtotal < 50) throw new CartError('Order total is below the minimum Stripe will charge.');
  if (subtotal > 500000) throw new CartError('Order total is above the ceiling this store will take.');

  return { items, subtotal, tax, requiresShipping };
}

export class CartError extends Error {}

/**
 * A product the printer cannot actually make must never be sold for real money.
 * Test mode is fine: the store page says plainly that nothing ships.
 *
 * Called from checkout, where the key in use is known. Module load is too early
 * to know it, and a guard that cannot see the environment is only decoration.
 */
export function assertSellable(items, env) {
  const liveMoney = Boolean(env.STRIPE_SECRET_KEY && env.STRIPE_SECRET_KEY.startsWith('sk_live'));
  if (!liveMoney) return;

  for (const item of items) {
    if (PRODUCTS[item.id]?.printerCanMake === false) {
      throw new CartError(`${PRODUCTS[item.id].name} is not available to order yet.`);
    }
  }
}
