// Order records and the webhook idempotency claim.

export function newId(prefix) {
  const bytes = crypto.getRandomValues(new Uint8Array(12));
  const hex = [...bytes].map((b) => b.toString(16).padStart(2, '0')).join('');
  return `${prefix}_${hex}`;
}

const nowIso = () => new Date().toISOString();

export async function createOrder(db, order) {
  const ts = nowIso();
  await db
    .prepare(
      `INSERT INTO orders
         (id, status, amount_subtotal, amount_shipping, amount_tax, amount_total,
          cost_print, cost_ship,
          currency, email, requires_shipping, shipping_json, items_json, created_at, updated_at)
       VALUES (?, 'pending', ?, ?, ?, ?, ?, ?, 'usd', ?, ?, ?, ?, ?, ?)`,
    )
    .bind(
      order.id,
      order.subtotal,
      order.shipping,
      order.tax,
      order.total,
      order.costPrint ?? null,
      order.costShip ?? null,
      order.email,
      order.requiresShipping ? 1 : 0,
      order.shippingAddress ? JSON.stringify(order.shippingAddress) : null,
      JSON.stringify(order.items),
      ts,
      ts,
    )
    .run();
}

export async function attachPaymentIntent(db, orderId, paymentIntentId) {
  await db
    .prepare(`UPDATE orders SET payment_intent_id = ?, updated_at = ? WHERE id = ?`)
    .bind(paymentIntentId, nowIso(), orderId)
    .run();
}

export function getOrderByPaymentIntent(db, paymentIntentId) {
  return db.prepare(`SELECT * FROM orders WHERE payment_intent_id = ?`).bind(paymentIntentId).first();
}

export async function setOrderStatus(db, orderId, status, note = null) {
  await db
    .prepare(`UPDATE orders SET status = ?, note = COALESCE(?, note), updated_at = ? WHERE id = ?`)
    .bind(status, note, nowIso(), orderId)
    .run();
}

// --- Webhook idempotency -----------------------------------------------------
//
// Protocol, in order:
//   claimEvent()    tries to insert the event id. Winning the insert means this
//                   delivery owns the work. Losing means someone already has it.
//   completeEvent() marks it done only after fulfillment actually succeeded.
//
// A delivery that loses the claim to a row already marked 'done' is a duplicate
// and returns 200 immediately, doing nothing. A delivery that loses to a row
// still 'processing' is either a concurrent duplicate or the wreckage of a run
// that crashed. Those get a 500 so Stripe retries, and a claim older than the
// stale window can be taken over, so a crash cannot strand an order forever.

const STALE_CLAIM_MS = 15 * 60 * 1000;

export async function claimEvent(db, eventId, type) {
  const ts = nowIso();

  const inserted = await db
    .prepare(
      `INSERT OR IGNORE INTO processed_events (event_id, type, status, claimed_at)
       VALUES (?, ?, 'processing', ?)`,
    )
    .bind(eventId, type, ts)
    .run();

  if (inserted.meta.changes === 1) return { claimed: true };

  const existing = await db
    .prepare(`SELECT status, claimed_at FROM processed_events WHERE event_id = ?`)
    .bind(eventId)
    .first();

  if (existing?.status === 'done') return { claimed: false, reason: 'duplicate' };

  // A previous attempt that finished and failed is not "in flight". Let the
  // next delivery take it straight away rather than sitting out the stale
  // window, so a transient outage costs one retry instead of fifteen minutes.
  const age = Date.now() - Date.parse(existing?.claimed_at ?? ts);
  if (existing?.status === 'failed' || age > STALE_CLAIM_MS) {
    await db
      .prepare(`UPDATE processed_events SET status = 'processing', claimed_at = ? WHERE event_id = ?`)
      .bind(ts, eventId)
      .run();
    return { claimed: true, reason: 'took over stale claim' };
  }

  return { claimed: false, reason: 'in flight' };
}

export async function completeEvent(db, eventId, orderId, status = 'done') {
  await db
    .prepare(`UPDATE processed_events SET status = ?, order_id = ?, done_at = ? WHERE event_id = ?`)
    .bind(status, orderId, nowIso(), eventId)
    .run();
}

// Safe to call on every webhook delivery. A retry re-enters fulfillment, and
// without OR IGNORE each pass would insert a second set of lines and hand out a
// second download token for an order that was already delivered.
export async function recordFulfillments(db, orderId, items) {
  const ts = nowIso();
  const rows = items.map((item) =>
    db
      .prepare(
        `INSERT OR IGNORE INTO fulfillments
           (id, order_id, product_id, kind, status, created_at, updated_at)
         VALUES (?, ?, ?, ?, 'pending', ?, ?)`,
      )
      .bind(newId('ful'), orderId, item.id, item.kind, ts, ts),
  );
  if (rows.length) await db.batch(rows);
}
