-- Store schema (Cloudflare D1 / SQLite).
--
-- Two rules this schema exists to enforce:
--   1. Every amount is an integer number of cents. No floats anywhere.
--   2. An order's line items are FROZEN at checkout time (items_json), so a
--      later catalog price change can never rewrite what someone was charged.

CREATE TABLE IF NOT EXISTS orders (
  id                TEXT PRIMARY KEY,          -- ord_<random>, ours, not Stripe's
  payment_intent_id TEXT UNIQUE,               -- pi_..., filled once Stripe replies
  status            TEXT NOT NULL,             -- pending|paid|partial|fulfilled|failed|refunded|review
  amount_subtotal   INTEGER NOT NULL,          -- cents
  amount_shipping   INTEGER NOT NULL DEFAULT 0,
  amount_tax        INTEGER NOT NULL DEFAULT 0,
  amount_total      INTEGER NOT NULL,          -- what we told Stripe to charge
  -- What the order costs Brett, recorded so margin is a fact rather than a
  -- guess. Shipping is free to the buyer, not free to us.
  cost_print        INTEGER,
  cost_ship         INTEGER,
  currency          TEXT    NOT NULL DEFAULT 'usd',
  email             TEXT    NOT NULL,
  requires_shipping INTEGER NOT NULL DEFAULT 0,
  shipping_json     TEXT,                      -- null for all-digital orders
  items_json        TEXT    NOT NULL,          -- frozen priced snapshot
  note              TEXT,                      -- why an order landed in review
  created_at        TEXT    NOT NULL,
  updated_at        TEXT    NOT NULL
);

CREATE INDEX IF NOT EXISTS orders_status_idx ON orders (status);
CREATE INDEX IF NOT EXISTS orders_email_idx  ON orders (email);

-- Webhook idempotency. Stripe retries on any non-2xx and can legitimately
-- deliver the same event twice, so every event is claimed here before any
-- fulfillment work happens. See webhook.js for the claim/complete protocol.
CREATE TABLE IF NOT EXISTS processed_events (
  event_id   TEXT PRIMARY KEY,                 -- evt_...
  type       TEXT NOT NULL,
  status     TEXT NOT NULL,                    -- processing|done|failed
  order_id   TEXT,
  claimed_at TEXT NOT NULL,
  done_at    TEXT
);

-- One row per thing actually delivered. Separate from orders because a single
-- order can contain a download, a print-on-demand item, and something Brett
-- ships himself, each completing at a different time.
CREATE TABLE IF NOT EXISTS fulfillments (
  id          TEXT PRIMARY KEY,
  order_id    TEXT NOT NULL REFERENCES orders (id),
  product_id  TEXT NOT NULL,
  kind        TEXT NOT NULL,                   -- digital|pod|manual
  status      TEXT NOT NULL,                   -- pending|sent|shipped|failed
  detail_json TEXT,                            -- download token, POD order id, tracking
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL,
  -- A webhook retry re-enters fulfillment. Without this, every retry inserts a
  -- fresh set of rows and the digital adapter issues a second download token.
  UNIQUE (order_id, product_id)
);

CREATE INDEX IF NOT EXISTS fulfillments_order_idx  ON fulfillments (order_id);
CREATE INDEX IF NOT EXISTS fulfillments_status_idx ON fulfillments (status);
