// The admin API. Everything Brett needs to run the store without a deploy.
//
// Images and goods are rows, not code. Uploading, pricing, describing and
// publishing all happen here, and the public catalog reads the same tables, so
// a change is live the moment it is saved.
//
// Web-sized previews are resized in the BROWSER before upload. Workers cannot
// resize an image without a paid image service, and shipping a 40MB master to
// every visitor is not an option, so the admin page does it on a canvas and
// sends both files. It costs nothing and keeps the print file off the web.
//
// Files live in Workers KV rather than R2. R2 is the natural home for this and
// R2 requires a card on file even inside its free allowance. KV needs neither,
// gives 1GB and 100,000 reads a day on the free plan, and costs nothing at this
// scale. The tradeoff is a hard 25MB ceiling per value, which a 300dpi print of
// these sizes fits inside comfortably. If the store ever outgrows that, R2 is a
// small change: only put, get and delete differ.

import {
  SIZES,
  TIERS,
  sizesForAspect,
  priceFor,
  loadProducts,
} from './catalog.js';
import { randomId, requireAdmin, requireUser, audit, createInvite, AuthError } from './auth.js';

const nowIso = () => new Date().toISOString();

const MAX_PREVIEW_BYTES = 8 * 1024 * 1024;
// Workers KV refuses anything larger. Said in the error rather than discovered.
const MAX_PRINT_BYTES = 25 * 1024 * 1024;

/** Slug from a title. Ids are stable and appear in product ids, so never auto-change one. */
export function slugify(s) {
  return String(s)
    .toLowerCase()
    .normalize('NFKD')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .slice(0, 60);
}

/** Nearest supported aspect for a set of pixel dimensions. */
export function aspectFor(width, height) {
  if (!width || !height) return null;
  const r = width > height ? width / height : height / width;
  const candidates = [
    { name: '2:3', value: 3 / 2 },
    { name: '4:5', value: 5 / 4 },
  ];
  let best = null;
  for (const c of candidates) {
    const diff = Math.abs(r - c.value);
    // `value` has to travel with the winner: the tolerance below is relative to
    // it, and without it the comparison is against undefined and every picture
    // comes back shapeless.
    if (!best || diff < best.diff) best = { name: c.name, diff, value: c.value };
  }
  // More than about 6% off and it is a different shape. Offering a size that
  // does not fit means a print arrives cropped, which is worse than no listing.
  return best && best.diff / best.value < 0.06 ? best.name : null;
}

// --- images ------------------------------------------------------------------

async function listImages(env) {
  const [images, prices] = await Promise.all([
    env.DB.prepare(`SELECT * FROM images ORDER BY sort_order, created_at DESC`).all(),
    env.DB.prepare(`SELECT * FROM image_prices`).all(),
  ]);

  const overrides = {};
  for (const p of prices.results ?? []) (overrides[p.image_id] ??= {})[p.size_id] = p.price;

  return (images.results ?? []).map((img) => {
    const sizes = safeParse(img.sizes_json) ?? sizesForAspect(img.aspect);
    return {
      ...img,
      sizes,
      overrides: overrides[img.id] ?? {},
      // What each size will actually charge, so the panel never has to guess.
      effectivePrices: Object.fromEntries(
        sizes.filter((s) => SIZES[s]).map((s) => [s, priceFor(s, img.tier, overrides[img.id] ?? {})]),
      ),
    };
  });
}

async function createImage(env, session, body) {
  const title = String(body.title ?? '').trim();
  if (!title) throw new AdminError('A title is required.');

  const id = body.id ? slugify(body.id) : slugify(title);
  if (!id) throw new AdminError('That title does not make a usable id.');

  const exists = await env.DB.prepare(`SELECT id FROM images WHERE id = ?`).bind(id).first();
  if (exists) throw new AdminError(`There is already a picture called "${id}".`);

  const ts = nowIso();
  await env.DB.prepare(
    `INSERT INTO images (id, title, blurb, story, tier, status, sort_order, created_at, updated_at)
     VALUES (?, ?, ?, ?, ?, 'draft', ?, ?, ?)`,
  )
    .bind(id, title, body.blurb ?? '', body.story ?? '', validTier(body.tier), Number(body.sort_order) || 0, ts, ts)
    .run();

  await audit(env, session.id, 'image.create', id, { title });
  return { id };
}

async function updateImage(env, session, id, body) {
  const img = await env.DB.prepare(`SELECT * FROM images WHERE id = ?`).bind(id).first();
  if (!img) throw new AdminError('No such picture.', 404);

  const fields = [];
  const values = [];
  const set = (col, val) => {
    fields.push(`${col} = ?`);
    values.push(val);
  };

  if (body.title !== undefined) set('title', String(body.title).trim());
  if (body.blurb !== undefined) set('blurb', String(body.blurb));
  if (body.story !== undefined) set('story', String(body.story));
  if (body.tier !== undefined) set('tier', validTier(body.tier));
  if (body.sort_order !== undefined) set('sort_order', Number(body.sort_order) || 0);
  if (body.sizes !== undefined) {
    const sizes = (body.sizes ?? []).filter((s) => SIZES[s]);
    set('sizes_json', JSON.stringify(sizes));
  }

  if (body.status !== undefined) {
    const status = body.status === 'live' ? 'live' : 'draft';
    // Refuse to publish something with nothing to show or nothing to sell.
    if (status === 'live') {
      if (!img.preview_key) throw new AdminError('Add a picture before publishing.');
      const sizes = body.sizes ?? safeParse(img.sizes_json) ?? sizesForAspect(img.aspect);
      if (!sizes || sizes.length === 0) throw new AdminError('Choose at least one size before publishing.');
    }
    set('status', status);
  }

  if (fields.length === 0) return { ok: true };

  set('updated_at', nowIso());
  values.push(id);
  await env.DB.prepare(`UPDATE images SET ${fields.join(', ')} WHERE id = ?`).bind(...values).run();

  if (body.prices !== undefined) {
    await env.DB.prepare(`DELETE FROM image_prices WHERE image_id = ?`).bind(id).run();
    const rows = Object.entries(body.prices ?? {})
      .filter(([sizeId, price]) => SIZES[sizeId] && Number.isInteger(price) && price > 0)
      .map(([sizeId, price]) =>
        env.DB.prepare(`INSERT INTO image_prices (image_id, size_id, price) VALUES (?, ?, ?)`).bind(id, sizeId, price),
      );
    if (rows.length) await env.DB.batch(rows);
  }

  await audit(env, session.id, 'image.update', id, body.status ? { status: body.status } : undefined);
  return { ok: true };
}

async function deleteImage(env, session, id) {
  const img = await env.DB.prepare(`SELECT * FROM images WHERE id = ?`).bind(id).first();
  if (!img) throw new AdminError('No such picture.', 404);

  // Take the files with it, or the bucket fills with things nothing points at.
  if (env.MEDIA) {
    for (const key of [img.preview_key, img.print_key].filter(Boolean)) {
      await env.MEDIA.delete(key).catch(() => {});
    }
  }
  await env.DB.prepare(`DELETE FROM image_prices WHERE image_id = ?`).bind(id).run();
  await env.DB.prepare(`DELETE FROM images WHERE id = ?`).bind(id).run();
  await audit(env, session.id, 'image.delete', id, { title: img.title });
  return { ok: true };
}

/**
 * Receives one file. `kind=preview` is the web-sized version the browser made;
 * `kind=print` is the full resolution file, which is never served publicly and
 * only ever reaches the printer through a signed link.
 */
async function uploadImageFile(env, session, id, request, url) {
  if (!env.MEDIA) throw new AdminError('File storage is not switched on yet.', 503);

  const img = await env.DB.prepare(`SELECT * FROM images WHERE id = ?`).bind(id).first();
  if (!img) throw new AdminError('No such picture.', 404);

  const kind = url.searchParams.get('kind') === 'print' ? 'print' : 'preview';
  const width = Number(url.searchParams.get('w')) || null;
  const height = Number(url.searchParams.get('h')) || null;
  const type = request.headers.get('Content-Type') ?? 'application/octet-stream';

  const limit = kind === 'print' ? MAX_PRINT_BYTES : MAX_PREVIEW_BYTES;
  const mb = Math.round(limit / (1024 * 1024));
  const declared = Number(request.headers.get('Content-Length') ?? 0);
  if (declared > limit) throw new AdminError(`That file is over ${mb}MB, which is the limit.`, 413);

  const ext = extFor(type);
  const key = `images/${id}/${kind}-${randomId(6)}.${ext}`;
  const body = await request.arrayBuffer();
  if (body.byteLength > limit) throw new AdminError(`That file is over ${mb}MB, which is the limit.`, 413);

  await env.MEDIA.put(key, body, { metadata: { contentType: type } });

  const old = kind === 'print' ? img.print_key : img.preview_key;
  if (old) await env.MEDIA.delete(old).catch(() => {});

  const column = kind === 'print' ? 'print_key' : 'preview_key';
  const sets = [`${column} = ?`, 'updated_at = ?'];
  const values = [key, nowIso()];

  // The shape comes from the print file when there is one, otherwise from the
  // preview, and it decides which sizes are even offered.
  if (width && height) {
    const aspect = aspectFor(width, height);
    if (kind === 'print' || !img.print_key) {
      sets.splice(1, 0, 'aspect = ?');
      values.splice(1, 0, aspect);
      if (!img.sizes_json && aspect) {
        sets.splice(2, 0, 'sizes_json = ?');
        values.splice(2, 0, JSON.stringify(sizesForAspect(aspect)));
      }
    }
  }

  values.push(id);
  await env.DB.prepare(`UPDATE images SET ${sets.join(', ')} WHERE id = ?`).bind(...values).run();
  await audit(env, session.id, 'image.upload', id, { kind, bytes: body.byteLength });

  const fresh = await env.DB.prepare(`SELECT * FROM images WHERE id = ?`).bind(id).first();
  return { key, aspect: fresh.aspect, sizes: safeParse(fresh.sizes_json) ?? sizesForAspect(fresh.aspect) };
}

// --- goods -------------------------------------------------------------------

async function upsertGood(env, session, body, id = null) {
  const name = String(body.name ?? '').trim();
  if (!id && !name) throw new AdminError('A name is required.');

  const goodId = id ?? slugify(body.id || name);
  const ts = nowIso();

  if (!id) {
    const exists = await env.DB.prepare(`SELECT id FROM goods WHERE id = ?`).bind(goodId).first();
    if (exists) throw new AdminError(`There is already an item called "${goodId}".`);
    await env.DB.prepare(
      `INSERT INTO goods (id, name, kind, blurb, material, price, cost, sku, status, sort_order, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, 'draft', ?, ?, ?)`,
    )
      .bind(
        goodId,
        name,
        body.kind === 'digital' ? 'digital' : 'pod',
        body.blurb ?? '',
        body.material ?? '',
        Number(body.price) || 0,
        Number(body.cost) || 0,
        body.sku ?? null,
        Number(body.sort_order) || 0,
        ts,
        ts,
      )
      .run();
    await audit(env, session.id, 'good.create', goodId, { name });
    return { id: goodId };
  }

  const fields = [];
  const values = [];
  const set = (c, v) => {
    fields.push(`${c} = ?`);
    values.push(v);
  };
  if (body.name !== undefined) set('name', String(body.name).trim());
  if (body.blurb !== undefined) set('blurb', String(body.blurb));
  if (body.material !== undefined) set('material', String(body.material));
  if (body.price !== undefined) set('price', Number(body.price) || 0);
  if (body.cost !== undefined) set('cost', Number(body.cost) || 0);
  if (body.sku !== undefined) set('sku', body.sku || null);
  if (body.sort_order !== undefined) set('sort_order', Number(body.sort_order) || 0);
  if (body.status !== undefined) set('status', body.status === 'live' ? 'live' : 'draft');
  if (fields.length === 0) return { ok: true };

  set('updated_at', ts);
  values.push(goodId);
  await env.DB.prepare(`UPDATE goods SET ${fields.join(', ')} WHERE id = ?`).bind(...values).run();
  await audit(env, session.id, 'good.update', goodId);
  return { ok: true };
}

// --- people ------------------------------------------------------------------

async function listUsers(env) {
  const rows = await env.DB.prepare(
    `SELECT u.*, (SELECT COUNT(*) FROM credentials c WHERE c.user_id = u.id) AS passkeys
       FROM users u ORDER BY u.role, u.created_at DESC`,
  ).all();
  return rows.results ?? [];
}

async function createUser(env, session, body) {
  const email = String(body.email ?? '').trim().toLowerCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) throw new AdminError('A valid email is required.');

  const role = body.role === 'admin' ? 'admin' : 'client';
  const existing = await env.DB.prepare(`SELECT * FROM users WHERE email = ?`).bind(email).first();

  const id = existing?.id ?? randomId(12);
  if (!existing) {
    await env.DB.prepare(
      `INSERT INTO users (id, email, name, role, status, created_at) VALUES (?, ?, ?, ?, 'active', ?)`,
    )
      .bind(id, email, body.name ?? null, role, nowIso())
      .run();
  }

  // An invite is the only way in. It expires, and it is single use.
  const token = await createInvite(env, id);
  await audit(env, session.id, 'user.invite', id, { email, role });
  return { id, email, role, inviteToken: token };
}

async function setUserStatus(env, session, id, status) {
  if (id === session.id) throw new AdminError('You cannot revoke your own access.');
  const next = status === 'revoked' ? 'revoked' : 'active';
  await env.DB.prepare(`UPDATE users SET status = ? WHERE id = ?`).bind(next, id).run();
  // Revoking has to end their sessions too, or they stay signed in until it expires.
  if (next === 'revoked') await env.DB.prepare(`DELETE FROM sessions WHERE user_id = ?`).bind(id).run();
  await audit(env, session.id, 'user.status', id, { status: next });
  return { ok: true };
}

// --- routing -----------------------------------------------------------------

export async function handleAdmin(request, env, url, session, json) {
  requireAdmin(session);
  const path = url.pathname.replace(/^\/admin/, '');
  const method = request.method;
  // Only the JSON routes get parsed here. A PUT carries a file, and reading it
  // as JSON first consumes the stream, so the upload handler finds an empty
  // body and the whole request dies with "Body has already been used".
  const body = method === 'POST' || method === 'PATCH' ? await safeJson(request) : {};

  // Everything the panel needs to draw itself in one call.
  if (path === '/bootstrap' && method === 'GET') {
    const [images, users, orders] = await Promise.all([
      listImages(env),
      listUsers(env),
      env.DB.prepare(
        `SELECT id, status, amount_total, cost_print, cost_ship, email, created_at
           FROM orders ORDER BY created_at DESC LIMIT 50`,
      ).all(),
    ]);
    const goods = await env.DB.prepare(`SELECT * FROM goods ORDER BY sort_order, created_at DESC`).all();
    return json(
      {
        me: { id: session.id, email: session.email, name: session.name },
        sizes: SIZES,
        tiers: TIERS,
        images,
        goods: goods.results ?? [],
        users,
        orders: orders.results ?? [],
        storageReady: Boolean(env.MEDIA),
      },
      200,
      request,
    );
  }

  if (path === '/images' && method === 'POST') return json(await createImage(env, session, body), 200, request);

  let m;
  if ((m = path.match(/^\/images\/([^/]+)\/file$/)) && method === 'PUT') {
    return json(await uploadImageFile(env, session, m[1], request, url), 200, request);
  }
  if ((m = path.match(/^\/images\/([^/]+)$/))) {
    if (method === 'PATCH') return json(await updateImage(env, session, m[1], body), 200, request);
    if (method === 'DELETE') return json(await deleteImage(env, session, m[1]), 200, request);
  }

  if (path === '/goods' && method === 'POST') return json(await upsertGood(env, session, body), 200, request);
  if ((m = path.match(/^\/goods\/([^/]+)$/)) && method === 'PATCH') {
    return json(await upsertGood(env, session, body, m[1]), 200, request);
  }

  if (path === '/users' && method === 'POST') return json(await createUser(env, session, body), 200, request);
  if ((m = path.match(/^\/users\/([^/]+)\/status$/)) && method === 'POST') {
    return json(await setUserStatus(env, session, m[1], body.status), 200, request);
  }
  if ((m = path.match(/^\/users\/([^/]+)\/invite$/)) && method === 'POST') {
    const token = await createInvite(env, m[1]);
    await audit(env, session.id, 'user.reinvite', m[1]);
    return json({ inviteToken: token }, 200, request);
  }

  return json({ error: 'Not found' }, 404, request);
}

/** Serves a preview from R2. Print files are never reachable this way. */
export async function serveMedia(request, env, url) {
  if (!env.MEDIA) return new Response('Not found', { status: 404 });

  const key = decodeURIComponent(url.pathname.replace(/^\/media\//, ''));
  if (!key || key.includes('..')) return new Response('Not found', { status: 404 });
  // Print files stay off the web entirely. Only the printer sees one, through a
  // signed link, and only for as long as it needs it.
  if (/\/print-/.test(key)) return new Response('Not found', { status: 404 });

  const { value, metadata } = await env.MEDIA.getWithMetadata(key, { type: 'arrayBuffer' });
  if (!value) return new Response('Not found', { status: 404 });

  // Keys carry a random suffix and never change contents, so this can be
  // cached hard. A replaced picture gets a new key.
  return new Response(value, {
    headers: {
      'Content-Type': metadata?.contentType ?? 'application/octet-stream',
      'Cache-Control': 'public, max-age=31536000, immutable',
    },
  });
}

async function safeJson(request) {
  try {
    return await request.json();
  } catch {
    return {};
  }
}

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

const validTier = (t) => (TIERS[t] ? t : 'standard');

function extFor(type) {
  if (/jpeg|jpg/.test(type)) return 'jpg';
  if (/png/.test(type)) return 'png';
  if (/webp/.test(type)) return 'webp';
  if (/tiff?/.test(type)) return 'tif';
  return 'bin';
}

export class AdminError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}
