// Prints a fresh VAPID key pair. Public key → wrangler.jsonc vars,
// private key → `wrangler secret put VAPID_PRIVATE_KEY` (and .dev.vars locally).
const kp = await crypto.subtle.generateKey({ name: 'ECDSA', namedCurve: 'P-256' }, true, ['sign', 'verify']);
const jwk = await crypto.subtle.exportKey('jwk', kp.privateKey);
const pub = new Uint8Array(await crypto.subtle.exportKey('raw', kp.publicKey));
const b64u = (b) => Buffer.from(b).toString('base64url');
console.log(`VAPID_PUBLIC_KEY=${b64u(pub)}`);
console.log(`VAPID_PRIVATE_KEY=${jwk.d}`);
