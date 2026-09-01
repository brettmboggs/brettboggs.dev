-- Admin and content tables.
--
-- The catalog used to live in catalog.js, which meant every new photograph was
-- a code change and a deploy. It lives here now so Brett runs the store from
-- the store.

-- One row per person who can sign in. Brett is 'admin'. Clients are 'client'
-- and see only the galleries they are granted.
CREATE TABLE IF NOT EXISTS users (
  id          TEXT PRIMARY KEY,
  email       TEXT NOT NULL UNIQUE,
  name        TEXT,
  role        TEXT NOT NULL CHECK (role IN ('admin', 'client')),
  status      TEXT NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'revoked')),
  created_at  TEXT NOT NULL,
  last_seen_at TEXT
);

-- Passkeys. No passwords anywhere: nothing to leak, nothing to phish, and
-- nothing for Brett to remember. A credential is bound to this domain by the
-- browser, so a copied link cannot be replayed elsewhere.
CREATE TABLE IF NOT EXISTS credentials (
  id             TEXT PRIMARY KEY,      -- base64url credential id
  user_id        TEXT NOT NULL REFERENCES users (id),
  public_key     TEXT NOT NULL,         -- base64url COSE key
  counter        INTEGER NOT NULL DEFAULT 0,
  transports     TEXT,
  label          TEXT,
  created_at     TEXT NOT NULL,
  last_used_at   TEXT
);

CREATE INDEX IF NOT EXISTS credentials_user_idx ON credentials (user_id);

-- Sessions, server side. The cookie holds a random id and nothing else, so a
-- stolen cookie dies the moment the row is deleted.
CREATE TABLE IF NOT EXISTS sessions (
  id          TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users (id),
  created_at  TEXT NOT NULL,
  expires_at  TEXT NOT NULL,
  user_agent  TEXT
);

CREATE INDEX IF NOT EXISTS sessions_user_idx ON sessions (user_id);

-- Short-lived challenges for passkey registration and sign in. Rows are
-- deleted on use, so a challenge cannot be replayed.
CREATE TABLE IF NOT EXISTS challenges (
  id         TEXT PRIMARY KEY,
  purpose    TEXT NOT NULL,
  user_id    TEXT,
  expires_at TEXT NOT NULL
);

-- One-time invitations. How a client gets in, and how Brett adds a second
-- passkey to his own account without touching a terminal.
CREATE TABLE IF NOT EXISTS invites (
  token       TEXT PRIMARY KEY,
  user_id     TEXT NOT NULL REFERENCES users (id),
  purpose     TEXT NOT NULL,            -- enroll
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL
);

-- --- Content -----------------------------------------------------------------

-- A photograph. `status` draft keeps it off the store until Brett says so.
CREATE TABLE IF NOT EXISTS images (
  id          TEXT PRIMARY KEY,          -- slug, e.g. copper-hour
  title       TEXT NOT NULL,
  blurb       TEXT,
  story       TEXT,                      -- longer write-up, optional
  tier        TEXT NOT NULL DEFAULT 'standard',
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live')),
  aspect      TEXT,                      -- 2:3, 4:5, computed on upload
  preview_key TEXT,                      -- R2 key of the web-sized preview
  print_key   TEXT,                      -- R2 key of the print-resolution file
  sizes_json  TEXT,                      -- which size ids are offered
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS images_status_idx ON images (status);

-- Per-image price overrides. Null means use the size ladder and tier.
CREATE TABLE IF NOT EXISTS image_prices (
  image_id  TEXT NOT NULL REFERENCES images (id) ON DELETE CASCADE,
  size_id   TEXT NOT NULL,
  price     INTEGER NOT NULL,
  PRIMARY KEY (image_id, size_id)
);

-- Standalone goods that are not image by size.
CREATE TABLE IF NOT EXISTS goods (
  id          TEXT PRIMARY KEY,
  name        TEXT NOT NULL,
  kind        TEXT NOT NULL,             -- pod | digital
  blurb       TEXT,
  material    TEXT,
  price       INTEGER NOT NULL,
  cost        INTEGER NOT NULL DEFAULT 0,
  sku         TEXT,
  asset_key   TEXT,
  preview_key TEXT,
  status      TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'live')),
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

-- --- Client galleries --------------------------------------------------------

CREATE TABLE IF NOT EXISTS galleries (
  id          TEXT PRIMARY KEY,
  title       TEXT NOT NULL,
  note        TEXT,
  created_at  TEXT NOT NULL,
  updated_at  TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS gallery_photos (
  id          TEXT PRIMARY KEY,
  gallery_id  TEXT NOT NULL REFERENCES galleries (id) ON DELETE CASCADE,
  r2_key      TEXT NOT NULL,
  filename    TEXT,
  width       INTEGER,
  height      INTEGER,
  sort_order  INTEGER NOT NULL DEFAULT 0,
  created_at  TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS gallery_photos_gallery_idx ON gallery_photos (gallery_id);

-- Who can see which gallery, and until when.
CREATE TABLE IF NOT EXISTS gallery_access (
  gallery_id TEXT NOT NULL REFERENCES galleries (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  expires_at TEXT,
  created_at TEXT NOT NULL,
  PRIMARY KEY (gallery_id, user_id)
);

-- What a client marked as a keeper.
CREATE TABLE IF NOT EXISTS gallery_selects (
  photo_id   TEXT NOT NULL REFERENCES gallery_photos (id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES users (id) ON DELETE CASCADE,
  created_at TEXT NOT NULL,
  PRIMARY KEY (photo_id, user_id)
);

-- Every consequential admin action, so a surprise has a paper trail.
CREATE TABLE IF NOT EXISTS audit_log (
  id         TEXT PRIMARY KEY,
  user_id    TEXT,
  action     TEXT NOT NULL,
  target     TEXT,
  detail     TEXT,
  created_at TEXT NOT NULL
);
