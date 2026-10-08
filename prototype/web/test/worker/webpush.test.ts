import { describe, expect, it } from 'vitest';
import { b64uDecode, b64uEncode, encryptPayload, generateVapidKeys, vapidAuth } from '../../worker/webpush';

// RFC 8291, Section 5 / Appendix A.
const RFC = {
  plaintext: 'V2hlbiBJIGdyb3cgdXAsIEkgd2FudCB0byBiZSBhIHdhdGVybWVsb24',
  asPrivate: 'yfWPiYE-n46HLnH0KqZOF1fJJU3MYrct3AELtAQ-oRw',
  asPublic: 'BP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27mlmlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A8',
  uaPublic: 'BCVxsr7N_eNgVRqvHtD0zTZsEc6-VV-JvLexhqUzORcxaOzi6-AYWXvTBHm4bjyPjs7Vd8pZGH6SRpkNtoIAiw4',
  auth: 'BTBZMqHH6r4Tts7J_aSIgg',
  salt: 'DGv6ra1nlYgDCS1FRnbzlw',
  body:
    'DGv6ra1nlYgDCS1FRnbzlwAAEABBBP4z9KsN6nGRTbVYI_c7VJSPQTBtkgcy27ml' +
    'mlMoZIIgDll6e3vCYLocInmYWAmS6TlzAC8wEqKK6PBru3jl7A_yl95bQpu6cVPT' +
    'pK4Mqgkf1CXztLVBSt2Ks3oZwbuwXPXLWyouBWLVWGNWQexSgSxsj_Qulcy4a-fN',
};

describe('RFC 8291 encryption', () => {
  it('matches the RFC test vector byte for byte', async () => {
    const out = await encryptPayload(b64uDecode(RFC.plaintext), RFC.uaPublic, RFC.auth, {
      asPrivate: b64uDecode(RFC.asPrivate),
      asPublic: b64uDecode(RFC.asPublic),
      salt: b64uDecode(RFC.salt),
    });
    expect(b64uEncode(out)).toBe(RFC.body);
  });

  it('round-trips with a random sender key (decrypt as the user agent)', async () => {
    // User agent key pair + auth secret, like a browser subscription.
    const ua = (await crypto.subtle.generateKey({ name: 'ECDH', namedCurve: 'P-256' }, true, ['deriveBits'])) as CryptoKeyPair;
    const uaPub = new Uint8Array((await crypto.subtle.exportKey('raw', ua.publicKey)) as ArrayBuffer);
    const auth = crypto.getRandomValues(new Uint8Array(16));
    const msg = JSON.stringify({ title: 'Tonight: Retinoid night', body: 'Tretinoin: pea-size' });
    const body = await encryptPayload(new TextEncoder().encode(msg), b64uEncode(uaPub), b64uEncode(auth));

    // Decrypt per RFC 8291.
    const salt = body.slice(0, 16);
    const idlen = body[20];
    const asPub = body.slice(21, 21 + idlen);
    const ct = body.slice(21 + idlen);
    const asKey = await crypto.subtle.importKey('raw', asPub, { name: 'ECDH', namedCurve: 'P-256' }, false, []);
    const secret = new Uint8Array(await crypto.subtle.deriveBits({ name: 'ECDH', public: asKey } as unknown as Parameters<typeof crypto.subtle.deriveBits>[0], ua.privateKey, 256));
    const te = new TextEncoder();
    const hk = async (s: Uint8Array, ikm: Uint8Array, info: Uint8Array, n: number) => {
      const k = await crypto.subtle.importKey('raw', ikm, 'HKDF', false, ['deriveBits']);
      return new Uint8Array(await crypto.subtle.deriveBits({ name: 'HKDF', hash: 'SHA-256', salt: s, info }, k, n * 8));
    };
    const keyInfo = new Uint8Array([...te.encode('WebPush: info\0'), ...uaPub, ...asPub]);
    const ikm = await hk(auth, secret, keyInfo, 32);
    const cek = await hk(salt, ikm, te.encode('Content-Encoding: aes128gcm\0'), 16);
    const nonce = await hk(salt, ikm, te.encode('Content-Encoding: nonce\0'), 12);
    const aes = await crypto.subtle.importKey('raw', cek, 'AES-GCM', false, ['decrypt']);
    const plain = new Uint8Array(await crypto.subtle.decrypt({ name: 'AES-GCM', iv: nonce }, aes, ct));
    expect(plain[plain.length - 1]).toBe(2);
    expect(new TextDecoder().decode(plain.slice(0, -1))).toBe(msg);
  });
});

describe('VAPID', () => {
  it('produces a JWT that verifies against the public key', async () => {
    const keys = await generateVapidKeys();
    const header = await vapidAuth('https://web.push.apple.com/abc123', { ...keys, subject: 'https://barrier.example' }, 1_760_000_000_000);
    const m = header.match(/^vapid t=([^,]+), k=(.+)$/);
    expect(m).not.toBeNull();
    const [h, c, s] = m![1].split('.');
    const claims = JSON.parse(new TextDecoder().decode(b64uDecode(c)));
    expect(claims.aud).toBe('https://web.push.apple.com');
    expect(claims.sub).toBe('https://barrier.example');
    expect(claims.exp - 1_760_000_000).toBe(12 * 3600);
    const pub = await crypto.subtle.importKey('raw', b64uDecode(m![2]), { name: 'ECDSA', namedCurve: 'P-256' }, false, ['verify']);
    const ok = await crypto.subtle.verify({ name: 'ECDSA', hash: 'SHA-256' }, pub, b64uDecode(s), new TextEncoder().encode(`${h}.${c}`));
    expect(ok).toBe(true);
  });
});
