// Margin model. Run it whenever a price or a printer cost changes.
//
//   node tools/store/pricing.mjs
//
// Costs are Prodigi wholesale, quoted 2026-09-01 for US delivery.
//
// SHIPPING IS INCLUDED IN THE PRICE and free to the buyer. It is not free to
// Brett, so it is subtracted here along with Stripe's cut. `price` below is the
// whole amount the buyer pays.

const STRIPE_PCT = 0.029;
const STRIPE_FLAT = 30; // cents

// cents
const COSTS = {
  '8x10': { print: 900, ship: 1185 },
  '11x14': { print: 1400, ship: 1185 },
  '12x18': { print: 1400, ship: 1295 },
  '16x24': { print: 1500, ship: 1295 },
  '20x30': { print: 2000, ship: 1400 },
  '24x36': { print: 2200, ship: 1590 },
  '30x40': { print: 2800, ship: 1590 },
  deck: { print: 1083, ship: 1212 },
  digital: { print: 0, ship: 0 },
};

const money = (c) => `$${(c / 100).toFixed(2)}`;
const pad = (s, n) => String(s).padEnd(n);
const rpad = (s, n) => String(s).padStart(n);

function margin(key, price) {
  const c = COSTS[key];
  const charged = price; // shipping is inside the price now
  const stripe = Math.round(charged * STRIPE_PCT) + STRIPE_FLAT;
  const net = charged - stripe - c.print - c.ship;
  return { charged, stripe, cost: c.print + c.ship, net, pct: net / charged };
}

function table(title, rows) {
  console.log(`\n${title}`);
  console.log(
    `  ${pad('item', 12)}${rpad('price', 9)}${rpad('buyer pays', 12)}${rpad('your cost', 11)}${rpad('stripe', 8)}${rpad('you keep', 10)}${rpad('margin', 8)}`,
  );
  console.log('  ' + '-'.repeat(70));
  for (const [key, label, price] of rows) {
    const m = margin(key, price);
    console.log(
      `  ${pad(label, 12)}${rpad(money(price), 9)}${rpad(money(m.charged), 12)}${rpad(money(m.cost), 11)}${rpad(money(m.stripe), 8)}${rpad(money(m.net), 10)}${rpad((m.pct * 100).toFixed(0) + '%', 8)}`,
    );
  }
}

// --- Proposed open edition ladder -------------------------------------------
//
// Not cost-plus. Printing an 8x10 costs 9.00 and a 24x36 costs 22.00, so
// cost-plus would price a huge print at barely more than a small one, which is
// not how anyone buys art. This ladder is priced on size and presence, checked
// against the open-edition market: professionals sit at 75 to 500, and the
// common guidance for an emerging photographer at 16x24 is 150 to 300.
// Deliberately at the lower end of that: unknown name, open edition, and a
// first buyer is worth more than a first margin.
table('OPEN EDITION prints, delivered', [
  ['8x10', '8 x 10', 6000],
  ['12x18', '12 x 18', 9000],
  ['16x24', '16 x 24', 13500],
  ['20x30', '20 x 30', 19000],
  ['24x36', '24 x 36', 26000],
]);

// --- Limited edition ---------------------------------------------------------
//
// Same paper, same printer, same cost. The buyer is paying for scarcity, which
// only means anything if the cap is actually enforced. Roughly 2x open.
table('LIMITED EDITION prints, 25 each, numbered, delivered', [
  ['16x24', '16 x 24', 28500],
  ['20x30', '20 x 30', 40000],
  ['24x36', '24 x 36', 54500],
]);

// --- Everything else ---------------------------------------------------------
table('OTHER', [
  ['deck', 'cards', 4000],
  ['digital', 'file', 2500],
]);

// --- What multi-item orders do ----------------------------------------------
//
// Two prints share one tube, so the second one's shipping is pure margin. Worth
// knowing before anyone designs a multi-buy discount that is not needed.
console.log('\nA second print ships in the same tube, so its shipping is pure margin');
const one = margin('16x24', 13500);
const twoCharged = 13500 * 2;
const twoStripe = Math.round(twoCharged * STRIPE_PCT) + STRIPE_FLAT;
const twoNet = twoCharged - twoStripe - 1500 * 2 - 1295; // one tube, not two
console.log(`  one 16x24     buyer pays ${money(one.charged)}   you keep ${money(one.net)}`);
console.log(`  two 16x24     buyer pays ${money(twoCharged)}   you keep ${money(twoNet)}`);
console.log(`  the second adds ${money(twoNet - one.net)} on ${money(13500)} of price`);

console.log('\nFloor check: the price at which a size only breaks even');
for (const size of ['8x10', '12x18', '16x24', '20x30', '24x36']) {
  let p = 100;
  while (margin(size, p).net < 0) p += 25;
  console.log(`  ${pad(size, 10)}breaks even at about ${money(p)} delivered`);
}
