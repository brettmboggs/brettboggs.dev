// Shared store front end: where the API lives, what is in the cart, and how
// money is written down.
//
// The cart holds product ids and quantities and NOTHING about price. Prices are
// read from the API for display only, and the server prices the order again at
// checkout from its own catalog. Nothing the browser believes about money is
// ever trusted, including by this file.

// The deployed Worker is the DEFAULT, not the fallback.
//
// These are compiled into the bundle at build time, and the CI build has no
// .env file. Defaulting to localhost meant the published page asked every
// visitor's own machine for the catalogue, which is why a deployed store looked
// empty while it worked perfectly in development.
//
// Both values are public by design: a hostname, and a Stripe publishable key
// that is meant to sit in the browser. Set PUBLIC_STORE_API in .env to point at
// a local Worker while developing.
export const STORE_API =
  import.meta.env.PUBLIC_STORE_API ?? 'https://brettboggs-store.brettmboggs.workers.dev';

export const STRIPE_PK =
  import.meta.env.PUBLIC_STRIPE_PK ??
  'pk_test_51UAtaB2Yr32StLP0VmliMflz813vYNkeWRSg2WMAnywpTggPKs3JOG5szgXnhJ2J0d2uL91iiLPf3ZdAS3IeJSqw00p6YQZ8cg';

export type Dims = { w: number; h: number; units: string };

export type Product = {
  id: string;
  name: string;
  kind: 'digital' | 'pod';
  price: number;
  blurb: string;
  dims: Dims | null;
  material: string | null;
  tierLabel: string | null;
  editionLimit: number | null;
  /** Prints belong to a picture and group under it. Goods have no image. */
  imageId: string | null;
  imageTitle: string | null;
  sizeId: string | null;
};

export type Cart = Record<string, number>;

const KEY = 'bb.cart';
const MAX_QTY = 10;

export function readCart(): Cart {
  try {
    const raw = sessionStorage.getItem(KEY);
    if (!raw) return {};
    const parsed = JSON.parse(raw) as unknown;
    if (!parsed || typeof parsed !== 'object') return {};
    const clean: Cart = {};
    for (const [id, qty] of Object.entries(parsed as Record<string, unknown>)) {
      if (typeof qty === 'number' && Number.isInteger(qty) && qty > 0 && qty <= MAX_QTY) {
        clean[id] = qty;
      }
    }
    return clean;
  } catch {
    // Private windows and cleared storage both land here. An empty cart is the
    // right answer, not an error.
    return {};
  }
}

export function writeCart(cart: Cart): void {
  try {
    sessionStorage.setItem(KEY, JSON.stringify(cart));
  } catch {
    /* nothing to do; the page still works, the cart just will not survive */
  }
  document.dispatchEvent(new CustomEvent('cart:change', { detail: cart }));
}

export function setQty(id: string, qty: number): Cart {
  const cart = readCart();
  if (qty <= 0) delete cart[id];
  else cart[id] = Math.min(Math.max(Math.round(qty), 1), MAX_QTY);
  writeCart(cart);
  return cart;
}

export function cartCount(cart: Cart = readCart()): number {
  return Object.values(cart).reduce((n, q) => n + q, 0);
}

export function cartItems(cart: Cart = readCart()): { id: string; qty: number }[] {
  return Object.entries(cart).map(([id, qty]) => ({ id, qty }));
}

export function clearCart(): void {
  writeCart({});
}

/** Cents to a plain dollar string. Integer in, never a float anywhere. */
export function money(cents: number): string {
  return `$${(cents / 100).toFixed(2)}`;
}

export async function fetchCatalog(): Promise<Product[]> {
  const res = await fetch(`${STORE_API}/catalog`);
  if (!res.ok) throw new Error(`Catalog unavailable (${res.status})`);
  const body = (await res.json()) as { products: Product[] };
  return body.products ?? [];
}
