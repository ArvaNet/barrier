// Web Push with plain WebCrypto: RFC 8291 (aes128gcm payload encryption) and
// RFC 8292 (VAPID). Runs in Workers and in Node for tests.

const te = new TextEncoder();

export function b64uDecode(s: string): Uint8Array {
  const clean = s.replace(/\s+/g, '').replace(/-/g, '+').replace(/_/g, '/');
  const padded = clean + '='.repeat((4 - (clean.length % 4)) % 4);
  const bin = atob(padded);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

export function b64uEncode(buf: ArrayBuffer | Uint8Array): string {
  const bytes = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
  let bin = '';
  for (let i = 0; i < bytes.length; i++) bin += String.fromCharCode(bytes[i]);
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function concat(...parts: Uint8Array[]): Uint8Array {
  const len = parts.reduce((n, p) => n + p.length, 0);
  const out = new Uint8Array(len);
  let o = 0;
  for (const p of parts) {
    out.set(p, o);
    o += p.length;
  }
  return out;
}

async function hkdf(salt: Uint8Array, ikm: Uint8Array, info: Uint8Array, bytes: number): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey('raw', ikm as BufferSource, 'HKDF', false, ['deriveBits']);
  const bits = await crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: salt as BufferSource, info: info as BufferSource },
    key,
    bytes * 8,
  );
  return new Uint8Array(bits);
}

/** Import a P-256 private key from raw d + uncompressed public point. */
export async function importEcPrivate(d: Uint8Array, pub: Uint8Array, usage: 'ecdh' | 'sign'): Promise<CryptoKey> {
  const jwk: JsonWebKey = {
    kty: 'EC', crv: 'P-256', d: b64uEncode(d), x: b64uEncode(pub.slice(1, 33)), y: b64uEncode(pub.slice(33, 65)), ext: true,
  };
  return usage === 'ecdh'
    ? crypto.subtle.importKey('jwk', jwk, { name: 'ECDH', namedCurve: 'P-256' }, false, ['deriveBits'])
    : crypto.subtle.importKey('jwk', jwk, { name: 'ECDSA', namedCurve: 'P-256' }, false, ['sign']);
}

export interface EncryptOptions {
  /** For tests: fixed sender key pair and salt. */
  asPrivate?: Uint8Array;
  asPublic?: Uint8Array;
  salt?: Uint8Array;
  recordSize?: number;
}

/** RFC 8291 aes128gcm body for a single record. */
export async function encryptPayload(
  plaintext: Uint8Array,
  uaPublicB64: string,
  authB64: string,
  opts: EncryptOptions = {},
): Promise<Uint8Array> {
  const uaPublic = b64uDecode(uaPublicB64);
  const auth = b64uDecode(authB64);
  const rs = opts.recordSize ?? 4096;

  let asPrivKey: CryptoKey;
  let asPublic: Uint8Array;
  if (opts.asPrivate && opts.asPublic) {
    asPrivKey = await importEcPrivate(opts.asPrivate, opts.asPublic, 'ecdh');
    asPublic = opts.asPublic;
  } else {
    const kp = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'])) as CryptoKeyPair;
    asPrivKey = kp.privateKey;
    asPublic = new Uint8Array((await crypto.subtle.exportKey('raw', kp.publicKey)) as ArrayBuffer);
  }

  const uaKey = await crypto.subtle.importKey('raw', uaPublic as BufferSource, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
  const ecdhSecret = new Uint8Array(
    // workers-types spells this ; the runtime (and the spec) use 'public'.
    await crypto.subtle.deriveBits({ name: 'ECDH', public: uaKey } as unknown as Parameters<typeof crypto.subtle.deriveBits>[0], asPrivKey, 256),
  );

  const keyInfo = concat(te.encode('WebPush: info\0'), uaPublic, asPublic);
  const ikm = await hkdf(auth, ecdhSecret, keyInfo, 32);
  const salt = opts.salt ?? crypto.getRandomValues(new Uint8Array(16));
  const cek = await hkdf(salt, ikm, te.encode('Content-Encoding: aes128gcm\0'), 16);
  const nonce = await hkdf(salt, ikm, te.encode('Content-Encoding: nonce\0'), 12);

  const record = concat(plaintext, new Uint8Array([2]));
  if (record.length + 16 > rs) throw new Error('payload too large');
  const aesKey = await crypto.subtle.importKey('raw', cek as BufferSource, 'AES-GCM', false, ['encrypt']);
  const ct = new Uint8Array(await crypto.subtle.encrypt({ name: 'AES-GCM', iv: nonce as BufferSource }, aesKey, record as BufferSource));

  const header = new Uint8Array(16 + 4 + 1 + asPublic.length);
  header.set(salt, 0);
  new DataView(header.buffer).setUint32(16, rs);
  header[20] = asPublic.length;
  header.set(asPublic, 21);
  return concat(header, ct);
}

export interface VapidKeys {
  publicKey: string; // base64url uncompressed point (65 bytes)
  privateKey: string; // base64url d (32 bytes)
  subject: string; // https URL or mailto:
}

/** RFC 8292 VAPID Authorization header value. */
export async function vapidAuth(endpoint: string, keys: VapidKeys, now = Date.now()): Promise<string> {
  const aud = new URL(endpoint).origin;
  const header = b64uEncode(te.encode(JSON.stringify({ typ: 'JWT', alg: 'ES256' })));
  const claims = b64uEncode(
    te.encode(JSON.stringify({ aud, exp: Math.floor(now / 1000) + 12 * 3600, sub: keys.subject })),
  );
  const unsigned = `${header}.${claims}`;
  const key = await importEcPrivate(b64uDecode(keys.privateKey), b64uDecode(keys.publicKey), 'sign');
  // WebCrypto returns the raw r||s signature JOSE wants.
  const sig = await crypto.subtle.sign({ name: 'ECDSA', hash: 'SHA-256' }, key, te.encode(unsigned) as BufferSource);
  return `vapid t=${unsigned}.${b64uEncode(sig)}, k=${keys.publicKey}`;
}

export interface Subscription {
  endpoint: string;
  keys: { p256dh: string; auth: string };
}

export interface SendResult {
  ok: boolean;
  status: number;
  gone: boolean; // subscription expired; delete it
  text?: string;
}

export async function sendPush(
  sub: Subscription,
  payload: unknown,
  keys: VapidKeys,
  opts: { ttl?: number; urgency?: 'very-low' | 'low' | 'normal' | 'high'; topic?: string } = {},
): Promise<SendResult> {
  const body = await encryptPayload(te.encode(JSON.stringify(payload)), sub.keys.p256dh, sub.keys.auth);
  const headers: Record<string, string> = {
    Authorization: await vapidAuth(sub.endpoint, keys),
    'Content-Encoding': 'aes128gcm',
    'Content-Type': 'application/octet-stream',
    TTL: String(opts.ttl ?? 4 * 3600),
    Urgency: opts.urgency ?? 'high',
  };
  if (opts.topic) headers.Topic = opts.topic.replace(/[^A-Za-z0-9_-]/g, '').slice(0, 32);
  const res = await fetch(sub.endpoint, { method: 'POST', headers, body: body as BodyInit });
  const gone = res.status === 404 || res.status === 410;
  let text: string | undefined;
  if (!res.ok) text = (await res.text().catch(() => '')).slice(0, 300);
  return { ok: res.ok, status: res.status, gone, text };
}

/** Generate a VAPID key pair (used by scripts/vapid.mjs too). */
export async function generateVapidKeys(): Promise<{ publicKey: string; privateKey: string }> {
  const kp = (await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify'])) as CryptoKeyPair;
  const jwk = (await crypto.subtle.exportKey('jwk', kp.privateKey)) as JsonWebKey;
  const pub = new Uint8Array((await crypto.subtle.exportKey('raw', kp.publicKey)) as ArrayBuffer);
  return { publicKey: b64uEncode(pub), privateKey: jwk.d! };
}
