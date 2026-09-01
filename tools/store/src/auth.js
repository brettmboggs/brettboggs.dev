// Sign in with a passkey. No passwords anywhere.
//
// There is nothing to leak, nothing to phish, and nothing for Brett to
// remember. A passkey is bound by the browser to this domain, so a convincing
// copy of the login page on another domain cannot use it. That property is the
// whole reason to prefer this over a password for a panel that can change
// prices and publish to a live store.
//
// The registration side leans on `response.getPublicKey()`, which hands back an
// SPKI key directly. The alternative is decoding CBOR out of the attestation
// object by hand, which is a lot of parsing to arrive at the same key. Browsers
// have exposed getPublicKey since 2021.
//
// Attestation is deliberately not verified. It answers "what brand of
// authenticator is this", which matters when an enterprise mandates hardware
// keys, and not at all here. Trust comes from the invite that let the
// enrollment happen, not from the make of the device.

const SESSION_DAYS = 30;
const CHALLENGE_MINUTES = 5;
const INVITE_HOURS = 48;

// --- small helpers -----------------------------------------------------------

export const b64url = {
  encode(buf) {
    const bytes = new Uint8Array(buf);
    let s = '';
    for (const b of bytes) s += String.fromCharCode(b);
    return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  },
  decode(str) {
    const s = str.replace(/-/g, '+').replace(/_/g, '/');
    const bin = atob(s + '='.repeat((4 - (s.length % 4)) % 4));
    const out = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
    return out;
  },
};

export function randomId(bytes = 24) {
  return b64url.encode(crypto.getRandomValues(new Uint8Array(bytes)));
}

const nowIso = () => new Date().toISOString();
const inMinutes = (m) => new Date(Date.now() + m * 60_000).toISOString();
const inHours = (h) => new Date(Date.now() + h * 3_600_000).toISOString();
const inDays = (d) => new Date(Date.now() + d * 86_400_000).toISOString();

/** Constant time compare, so a mismatch cannot be found one character at a time. */
function sameString(a, b) {
  if (typeof a !== 'string' || typeof b !== 'string' || a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return diff === 0;
}

// --- challenges --------------------------------------------------------------

async function issueChallenge(db, purpose, userId = null) {
  const id = randomId(32);
  await db
    .prepare(`INSERT INTO challenges (id, purpose, user_id, expires_at) VALUES (?, ?, ?, ?)`)
    .bind(id, purpose, userId, inMinutes(CHALLENGE_MINUTES))
    .run();
  return id;
}

/** Deleted on use. A challenge that can be replayed is not a challenge. */
async function consumeChallenge(db, id, purpose) {
  const row = await db
    .prepare(`SELECT * FROM challenges WHERE id = ? AND purpose = ?`)
    .bind(id, purpose)
    .first();
  if (!row) return null;
  await db.prepare(`DELETE FROM challenges WHERE id = ?`).bind(id).run();
  if (Date.parse(row.expires_at) < Date.now()) return null;
  return row;
}

// --- registration ------------------------------------------------------------

export async function startEnrollment(env, inviteToken, origin) {
  const invite = await env.DB.prepare(`SELECT * FROM invites WHERE token = ?`).bind(inviteToken).first();
  if (!invite || invite.used_at || Date.parse(invite.expires_at) < Date.now()) {
    throw new AuthError('This invitation is not valid any more.');
  }

  const user = await env.DB.prepare(`SELECT * FROM users WHERE id = ?`).bind(invite.user_id).first();
  if (!user || user.status !== 'active') throw new AuthError('This account is not active.');

  const challenge = await issueChallenge(env.DB, 'enroll', user.id);
  const existing = await env.DB.prepare(`SELECT id FROM credentials WHERE user_id = ?`).bind(user.id).all();

  return {
    challenge,
    rp: { name: 'Brett Boggs', id: new URL(origin).hostname },
    user: { id: b64url.encode(new TextEncoder().encode(user.id)), name: user.email, displayName: user.name || user.email },
    pubKeyCredParams: [
      { type: 'public-key', alg: -7 }, // ES256
      { type: 'public-key', alg: -257 }, // RS256
    ],
    authenticatorSelection: { residentKey: 'preferred', userVerification: 'preferred' },
    // Stops a device that is already enrolled from enrolling twice.
    excludeCredentials: (existing.results ?? []).map((c) => ({ type: 'public-key', id: c.id })),
    timeout: 120000,
  };
}

export async function finishEnrollment(env, body, origin) {
  const { credentialId, clientDataJSON, publicKey, algorithm, transports, inviteToken, label } = body;
  if (!credentialId || !clientDataJSON || !publicKey) throw new AuthError('Incomplete registration.');

  const clientData = JSON.parse(new TextDecoder().decode(b64url.decode(clientDataJSON)));
  if (clientData.type !== 'webauthn.create') throw new AuthError('Unexpected credential type.');
  if (clientData.origin !== origin) throw new AuthError('Credential was created for a different site.');

  const challenge = await consumeChallenge(env.DB, clientData.challenge, 'enroll');
  if (!challenge) throw new AuthError('That took too long. Start again.');

  const invite = await env.DB.prepare(`SELECT * FROM invites WHERE token = ?`).bind(inviteToken).first();
  if (!invite || invite.used_at || invite.user_id !== challenge.user_id) {
    throw new AuthError('This invitation is not valid any more.');
  }

  await env.DB.batch([
    env.DB.prepare(
      `INSERT INTO credentials (id, user_id, public_key, counter, transports, label, created_at)
       VALUES (?, ?, ?, 0, ?, ?, ?)`,
    ).bind(
      credentialId,
      challenge.user_id,
      publicKey,
      JSON.stringify(transports ?? []),
      label ?? 'passkey',
      nowIso(),
    ),
    env.DB.prepare(`UPDATE invites SET used_at = ? WHERE token = ?`).bind(nowIso(), inviteToken),
  ]);

  // Storing the algorithm alongside the key keeps verification honest later.
  await env.DB.prepare(`UPDATE credentials SET transports = ? WHERE id = ?`)
    .bind(JSON.stringify({ transports: transports ?? [], alg: algorithm ?? -7 }), credentialId)
    .run();

  return createSession(env, challenge.user_id, body.userAgent);
}

// --- sign in -----------------------------------------------------------------

export async function startLogin(env, origin) {
  const challenge = await issueChallenge(env.DB, 'login');
  return {
    challenge,
    rpId: new URL(origin).hostname,
    userVerification: 'preferred',
    timeout: 120000,
  };
}

export async function finishLogin(env, body, origin) {
  const { credentialId, clientDataJSON, authenticatorData, signature } = body;
  if (!credentialId || !clientDataJSON || !authenticatorData || !signature) {
    throw new AuthError('Incomplete sign in.');
  }

  const clientData = JSON.parse(new TextDecoder().decode(b64url.decode(clientDataJSON)));
  if (clientData.type !== 'webauthn.get') throw new AuthError('Unexpected assertion type.');
  if (clientData.origin !== origin) throw new AuthError('Assertion came from a different site.');

  const challenge = await consumeChallenge(env.DB, clientData.challenge, 'login');
  if (!challenge) throw new AuthError('That took too long. Try again.');

  const cred = await env.DB.prepare(`SELECT * FROM credentials WHERE id = ?`).bind(credentialId).first();
  if (!cred) throw new AuthError('That passkey is not registered here.');

  const user = await env.DB.prepare(`SELECT * FROM users WHERE id = ?`).bind(cred.user_id).first();
  if (!user || user.status !== 'active') throw new AuthError('This account is not active.');

  const meta = safeParse(cred.transports) ?? {};
  const alg = meta.alg ?? -7;

  const authData = b64url.decode(authenticatorData);
  const clientHash = new Uint8Array(
    await crypto.subtle.digest('SHA-256', b64url.decode(clientDataJSON)),
  );

  // The authenticator signs authenticatorData followed by the hash of the
  // client data. Anything else and the signature will not check out.
  const signed = new Uint8Array(authData.length + clientHash.length);
  signed.set(authData, 0);
  signed.set(clientHash, authData.length);

  const ok = await verifySignature(alg, cred.public_key, b64url.decode(signature), signed);
  if (!ok) throw new AuthError('That passkey did not check out.');

  // Bit 0 of the flags byte: the authenticator says a user was present. Without
  // this a key could be used by something the person never touched.
  const flags = authData[32];
  if ((flags & 0x01) === 0) throw new AuthError('No user present.');

  // A counter that goes backwards suggests a cloned authenticator. Many
  // authenticators keep it at zero, so only a real regression is refused.
  const counter = new DataView(authData.buffer, authData.byteOffset + 33, 4).getUint32(0);
  if (counter !== 0 && counter <= cred.counter) throw new AuthError('This passkey looks replayed.');

  await env.DB.prepare(`UPDATE credentials SET counter = ?, last_used_at = ? WHERE id = ?`)
    .bind(counter, nowIso(), credentialId)
    .run();
  await env.DB.prepare(`UPDATE users SET last_seen_at = ? WHERE id = ?`).bind(nowIso(), user.id).run();

  return createSession(env, user.id, body.userAgent);
}

async function verifySignature(alg, publicKeyB64, signature, data) {
  const spki = b64url.decode(publicKeyB64);

  if (alg === -257) {
    const key = await crypto.subtle.importKey(
      'spki',
      spki,
      { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
      false,
      ['verify'],
    );
    return crypto.subtle.verify('RSASSA-PKCS1-v1_5', key, signature, data);
  }

  const key = await crypto.subtle.importKey(
    'spki',
    spki,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['verify'],
  );
  // WebAuthn returns ECDSA signatures DER encoded; Web Crypto wants raw r||s.
  return crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, key, derToRaw(signature), data);
}

/** DER SEQUENCE { INTEGER r, INTEGER s } into the fixed 64 bytes Web Crypto wants. */
function derToRaw(der) {
  let i = 0;
  if (der[i++] !== 0x30) throw new AuthError('Malformed signature.');
  if (der[i] & 0x80) i += 1 + (der[i] & 0x7f);
  else i += 1;

  const readInt = () => {
    if (der[i++] !== 0x02) throw new AuthError('Malformed signature.');
    let len = der[i++];
    let val = der.slice(i, i + len);
    i += len;
    while (val.length > 32 && val[0] === 0) val = val.slice(1); // strip sign padding
    const out = new Uint8Array(32);
    out.set(val, 32 - val.length);
    return out;
  };

  const r = readInt();
  const s = readInt();
  const raw = new Uint8Array(64);
  raw.set(r, 0);
  raw.set(s, 32);
  return raw;
}

// --- sessions ----------------------------------------------------------------

export async function createSession(env, userId, userAgent) {
  const id = randomId(32);
  await env.DB.prepare(
    `INSERT INTO sessions (id, user_id, created_at, expires_at, user_agent) VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(id, userId, nowIso(), inDays(SESSION_DAYS), (userAgent ?? '').slice(0, 200))
    .run();
  return id;
}

export async function readSession(env, request) {
  const cookie = request.headers.get('Cookie') ?? '';
  const match = cookie.match(/(?:^|;\s*)bb_session=([^;]+)/);
  if (!match) return null;

  const row = await env.DB.prepare(
    `SELECT s.id AS sid, s.expires_at, u.* FROM sessions s
       JOIN users u ON u.id = s.user_id
      WHERE s.id = ?`,
  )
    .bind(match[1])
    .first();

  if (!row) return null;
  if (Date.parse(row.expires_at) < Date.now()) {
    await env.DB.prepare(`DELETE FROM sessions WHERE id = ?`).bind(row.sid).run();
    return null;
  }
  if (row.status !== 'active') return null;
  return row;
}

export async function endSession(env, request) {
  const cookie = request.headers.get('Cookie') ?? '';
  const match = cookie.match(/(?:^|;\s*)bb_session=([^;]+)/);
  if (match) await env.DB.prepare(`DELETE FROM sessions WHERE id = ?`).bind(match[1]).run();
}

export function sessionCookie(id, maxAgeSeconds = SESSION_DAYS * 86400) {
  // HttpOnly so script cannot read it, Secure so it never crosses plain HTTP,
  // and SameSite=None because the site and this API are different origins.
  return `bb_session=${id}; Path=/; HttpOnly; Secure; SameSite=None; Max-Age=${maxAgeSeconds}`;
}

export const clearCookie = () => sessionCookie('', 0);

// --- invitations -------------------------------------------------------------

export async function createInvite(env, userId, purpose = 'enroll') {
  const token = randomId(32);
  await env.DB.prepare(
    `INSERT INTO invites (token, user_id, purpose, expires_at, created_at) VALUES (?, ?, ?, ?, ?)`,
  )
    .bind(token, userId, purpose, inHours(INVITE_HOURS), nowIso())
    .run();
  return token;
}

// --- guards ------------------------------------------------------------------

export function requireAdmin(session) {
  if (!session) throw new AuthError('Sign in first.', 401);
  if (session.role !== 'admin') throw new AuthError('Not allowed.', 403);
  return session;
}

export function requireUser(session) {
  if (!session) throw new AuthError('Sign in first.', 401);
  return session;
}

export async function audit(env, userId, action, target, detail) {
  await env.DB.prepare(
    `INSERT INTO audit_log (id, user_id, action, target, detail, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
  )
    .bind(randomId(12), userId ?? null, action, target ?? null, detail ? JSON.stringify(detail).slice(0, 2000) : null, nowIso())
    .run();
}

function safeParse(s) {
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

export class AuthError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

export { sameString };
