// Admin client: talking to the store API, passkeys, and shrinking a photograph
// in the browser before it is uploaded.

import { STORE_API } from './store';

// --- api ---------------------------------------------------------------------

export async function api(path: string, options: RequestInit = {}): Promise<any> {
  const res = await fetch(`${STORE_API}${path}`, {
    // Without this the session cookie never travels, because the panel and the
    // API are different origins.
    credentials: 'include',
    ...options,
    headers: {
      ...(options.body && !(options.body instanceof ArrayBuffer) ? { 'Content-Type': 'application/json' } : {}),
      ...(options.headers ?? {}),
    },
  });
  const text = await res.text();
  const data = text ? JSON.parse(text) : {};
  if (!res.ok) throw new Error(data.error ?? `Request failed (${res.status})`);
  return data;
}

// --- passkeys ----------------------------------------------------------------

const b64urlToBytes = (s: string): Uint8Array => {
  const b = s.replace(/-/g, '+').replace(/_/g, '/');
  const bin = atob(b + '='.repeat((4 - (b.length % 4)) % 4));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
};

const bytesToB64url = (buf: ArrayBuffer): string => {
  let s = '';
  for (const b of new Uint8Array(buf)) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
};

export function passkeysSupported(): boolean {
  return typeof window !== 'undefined' && Boolean(window.PublicKeyCredential);
}

/** Registers a passkey against a one-time invitation. */
export async function enroll(inviteToken: string, label: string): Promise<void> {
  const options = await api('/auth/enroll/start', {
    method: 'POST',
    body: JSON.stringify({ inviteToken }),
  });

  const credential = (await navigator.credentials.create({
    publicKey: {
      challenge: b64urlToBytes(options.challenge),
      rp: options.rp,
      user: {
        id: b64urlToBytes(options.user.id),
        name: options.user.name,
        displayName: options.user.displayName,
      },
      pubKeyCredParams: options.pubKeyCredParams,
      authenticatorSelection: options.authenticatorSelection,
      excludeCredentials: (options.excludeCredentials ?? []).map((c: any) => ({
        type: 'public-key',
        id: b64urlToBytes(c.id),
      })),
      timeout: options.timeout,
    },
  })) as PublicKeyCredential | null;

  if (!credential) throw new Error('No passkey was created.');
  const response = credential.response as AuthenticatorAttestationResponse;

  // getPublicKey hands back an SPKI key directly. The alternative is decoding
  // CBOR out of the attestation object by hand to reach the same key.
  const publicKey = response.getPublicKey?.();
  if (!publicKey) throw new Error('This browser is too old to register a passkey.');

  await api('/auth/enroll/finish', {
    method: 'POST',
    body: JSON.stringify({
      inviteToken,
      credentialId: credential.id,
      clientDataJSON: bytesToB64url(response.clientDataJSON),
      publicKey: bytesToB64url(publicKey),
      algorithm: response.getPublicKeyAlgorithm?.() ?? -7,
      transports: response.getTransports?.() ?? [],
      label,
    }),
  });
}

export async function signIn(): Promise<void> {
  const options = await api('/auth/login/start', { method: 'POST', body: '{}' });

  const credential = (await navigator.credentials.get({
    publicKey: {
      challenge: b64urlToBytes(options.challenge),
      rpId: options.rpId,
      userVerification: options.userVerification,
      timeout: options.timeout,
    },
  })) as PublicKeyCredential | null;

  if (!credential) throw new Error('No passkey was offered.');
  const response = credential.response as AuthenticatorAssertionResponse;

  await api('/auth/login/finish', {
    method: 'POST',
    body: JSON.stringify({
      credentialId: credential.id,
      clientDataJSON: bytesToB64url(response.clientDataJSON),
      authenticatorData: bytesToB64url(response.authenticatorData),
      signature: bytesToB64url(response.signature),
    }),
  });
}

export const signOut = () => api('/auth/logout', { method: 'POST', body: '{}' });

// --- images ------------------------------------------------------------------

export type Shrunk = { blob: Blob; width: number; height: number; type: string };

/**
 * Makes the web-sized copy here, in the browser, before anything is uploaded.
 *
 * Two reasons. A Worker cannot resize an image without a paid image service, and
 * the full resolution file has no business being served to visitors: a 6000px
 * master is a free print for anyone who right-clicks it. The original still
 * uploads, separately, and is never served publicly.
 */
export function shrink(file: File, maxEdge = 1600, quality = 0.82): Promise<Shrunk> {
  return new Promise((resolve, reject) => {
    const url = URL.createObjectURL(file);
    const img = new Image();
    img.onload = () => {
      const scale = Math.min(1, maxEdge / Math.max(img.naturalWidth, img.naturalHeight));
      const w = Math.round(img.naturalWidth * scale);
      const h = Math.round(img.naturalHeight * scale);

      const canvas = document.createElement('canvas');
      canvas.width = w;
      canvas.height = h;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        URL.revokeObjectURL(url);
        reject(new Error('Could not draw the picture.'));
        return;
      }
      ctx.imageSmoothingQuality = 'high';
      ctx.drawImage(img, 0, 0, w, h);

      canvas.toBlob(
        (blob) => {
          URL.revokeObjectURL(url);
          if (!blob) reject(new Error('Could not shrink the picture.'));
          else resolve({ blob, width: img.naturalWidth, height: img.naturalHeight, type: 'image/webp' });
        },
        'image/webp',
        quality,
      );
    };
    img.onerror = () => {
      URL.revokeObjectURL(url);
      reject(new Error('That file is not an image this browser can read.'));
    };
    img.src = url;
  });
}

/** Uploads one file to an image. `kind` is preview or print. */
export async function uploadFile(
  imageId: string,
  kind: 'preview' | 'print',
  blob: Blob,
  width?: number,
  height?: number,
): Promise<any> {
  const params = new URLSearchParams({ kind });
  if (width) params.set('w', String(width));
  if (height) params.set('h', String(height));

  const res = await fetch(`${STORE_API}/admin/images/${encodeURIComponent(imageId)}/file?${params}`, {
    method: 'PUT',
    credentials: 'include',
    headers: { 'Content-Type': blob.type || 'application/octet-stream' },
    body: blob,
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) throw new Error((data as any).error ?? 'Upload failed.');
  return data;
}

export const mediaUrl = (key: string) => `${STORE_API}/media/${key}`;

export const money = (cents: number) => `$${(cents / 100).toFixed(2)}`;

export function parseMoney(input: string): number | null {
  const n = Number(String(input).replace(/[^0-9.]/g, ''));
  if (!Number.isFinite(n) || n < 0) return null;
  return Math.round(n * 100);
}
