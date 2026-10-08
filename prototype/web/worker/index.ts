// Barrier Worker: serves the app, stores each device's upcoming reminders and
// sends them as Web Push from a once-a-minute cron. No routine data lives
// here, only notification texts and times.

import { MAX_REMINDERS, type PushPayload, type RegisterRequest, type ReminderIn } from '../shared/api';
import { sendPush, type VapidKeys } from './webpush';

export interface Env {
  DB: D1Database;
  ASSETS: Fetcher;
  VAPID_PUBLIC_KEY: string;
  VAPID_PRIVATE_KEY: string;
  VAPID_SUBJECT: string;
}

const PUSH_HOSTS = ['fcm.googleapis.com', 'push.apple.com', 'push.services.mozilla.com', 'notify.windows.com', 'android.googleapis.com'];
const SCHEDULED_KINDS = ['main', 'nudge', 'followup', 'spf'];

const json = (data: unknown, status = 200) =>
  new Response(JSON.stringify(data), { status, headers: { 'content-type': 'application/json', 'cache-control': 'no-store' } });

const bad = (msg: string, status = 400) => json({ error: msg }, status);

async function sha256(s: string): Promise<string> {
  const h = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(s));
  return [...new Uint8Array(h)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

function randomToken(bytes = 24): string {
  const a = crypto.getRandomValues(new Uint8Array(bytes));
  return btoa(String.fromCharCode(...a)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function validSubscription(s: RegisterRequest['subscription'] | undefined): boolean {
  if (!s || typeof s.endpoint !== 'string' || !s.keys?.p256dh || !s.keys?.auth) return false;
  try {
    const u = new URL(s.endpoint);
    if (u.protocol !== 'https:') return false;
    return PUSH_HOSTS.some((h) => u.hostname === h || u.hostname.endsWith(`.${h}`));
  } catch {
    return false;
  }
}

async function authDevice(req: Request, env: Env): Promise<string | null> {
  const h = req.headers.get('authorization') ?? '';
  const m = h.match(/^Bearer ([A-Za-z0-9_-]+)\.([A-Za-z0-9_-]+)$/);
  if (!m) return null;
  const row = await env.DB.prepare('SELECT token_hash FROM devices WHERE id = ?').bind(m[1]).first<{ token_hash: string }>();
  if (!row || row.token_hash !== (await sha256(m[2]))) return null;
  return m[1];
}

function clampText(s: unknown, max: number): string {
  return typeof s === 'string' ? s.slice(0, max) : '';
}

function cleanReminder(r: ReminderIn): ReminderIn | null {
  if (!r || typeof r.id !== 'string' || typeof r.fireAt !== 'number' || !Number.isFinite(r.fireAt)) return null;
  if (!['main', 'nudge', 'followup', 'spf', 'timer', 'snooze'].includes(r.kind)) return null;
  const url = typeof r.url === 'string' && r.url.startsWith('/') ? r.url.slice(0, 200) : '/';
  return {
    id: r.id.slice(0, 80),
    fireAt: Math.round(r.fireAt),
    kind: r.kind,
    slot: r.slot === 'am' || r.slot === 'pm' ? r.slot : undefined,
    date: typeof r.date === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(r.date) ? r.date : undefined,
    title: clampText(r.title, 120),
    body: clampText(r.body, 240),
    url,
    genericTitle: r.genericTitle ? clampText(r.genericTitle, 120) : undefined,
    genericBody: r.genericBody ? clampText(r.genericBody, 240) : undefined,
  };
}

function insertReminder(env: Env, deviceId: string, r: ReminderIn, orReplace = false) {
  return env.DB.prepare(
    `INSERT OR ${orReplace ? 'REPLACE' : 'IGNORE'} INTO reminders
     (device_id, id, fire_at, kind, slot, date, title, body, url, generic_title, generic_body, sent_at)
     VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL)`,
  ).bind(deviceId, r.id, r.fireAt, r.kind, r.slot ?? null, r.date ?? null, r.title, r.body, r.url, r.genericTitle ?? null, r.genericBody ?? null);
}

async function readJson<T>(req: Request): Promise<T | null> {
  try {
    const text = await req.text();
    if (text.length > 200_000) return null;
    return JSON.parse(text) as T;
  } catch {
    return null;
  }
}

function vapid(env: Env): VapidKeys {
  return { publicKey: env.VAPID_PUBLIC_KEY, privateKey: env.VAPID_PRIVATE_KEY, subject: env.VAPID_SUBJECT };
}

async function api(req: Request, env: Env, path: string): Promise<Response> {
  const method = req.method;

  if (path === '/api/config' && method === 'GET') {
    return json({ vapidPublicKey: env.VAPID_PUBLIC_KEY });
  }

  if (path === '/api/register' && method === 'POST') {
    const body = await readJson<RegisterRequest>(req);
    if (!body || !validSubscription(body.subscription)) return bad('invalid subscription');
    const { endpoint, keys } = body.subscription;
    const tz = clampText(body.tz, 64) || 'UTC';
    const now = Date.now();
    if (body.deviceId && body.token) {
      const row = await env.DB.prepare('SELECT token_hash FROM devices WHERE id = ?').bind(body.deviceId).first<{ token_hash: string }>();
      if (row && row.token_hash === (await sha256(body.token))) {
        await env.DB.prepare('UPDATE devices SET endpoint = ?, p256dh = ?, auth = ?, tz = ?, failures = 0 WHERE id = ?')
          .bind(endpoint, keys.p256dh, keys.auth, tz, body.deviceId).run();
        return json({ deviceId: body.deviceId, token: body.token });
      }
    }
    const deviceId = randomToken(12);
    const token = randomToken(24);
    await env.DB.prepare(
      'INSERT INTO devices (id, token_hash, endpoint, p256dh, auth, tz, synced_at, created_at, failures) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)',
    ).bind(deviceId, await sha256(token), endpoint, keys.p256dh, keys.auth, tz, now, now).run();
    return json({ deviceId, token });
  }

  const deviceId = await authDevice(req, env);
  if (!deviceId) return bad('unauthorized', 401);

  if (path === '/api/schedule' && method === 'POST') {
    const body = await readJson<{ reminders: ReminderIn[] }>(req);
    if (!body || !Array.isArray(body.reminders)) return bad('invalid body');
    const now = Date.now();
    const list = body.reminders
      .slice(0, MAX_REMINDERS)
      .map(cleanReminder)
      .filter((r): r is ReminderIn => !!r && SCHEDULED_KINDS.includes(r.kind) && r.fireAt > now - 60_000);
    const stmts = [
      env.DB.prepare(
        `DELETE FROM reminders WHERE device_id = ? AND sent_at IS NULL AND kind IN (${SCHEDULED_KINDS.map(() => '?').join(',')})`,
      ).bind(deviceId, ...SCHEDULED_KINDS),
      ...list.map((r) => insertReminder(env, deviceId, r)),
      env.DB.prepare('UPDATE devices SET synced_at = ? WHERE id = ?').bind(now, deviceId),
      env.DB.prepare('DELETE FROM acks WHERE device_id = ? AND at < ?').bind(deviceId, now - 3 * 86_400_000),
    ];
    await env.DB.batch(stmts);
    return json({ ok: true, count: list.length });
  }

  if (path === '/api/ack' && method === 'POST') {
    const body = await readJson<{ date: string; slot: string }>(req);
    if (!body || !/^\d{4}-\d{2}-\d{2}$/.test(body.date ?? '') || !['am', 'pm'].includes(body.slot)) return bad('invalid body');
    await env.DB.batch([
      env.DB.prepare('INSERT OR REPLACE INTO acks (device_id, date, slot, at) VALUES (?, ?, ?, ?)').bind(deviceId, body.date, body.slot, Date.now()),
      env.DB.prepare("DELETE FROM reminders WHERE device_id = ? AND date = ? AND slot = ? AND sent_at IS NULL AND kind IN ('main','nudge','snooze')")
        .bind(deviceId, body.date, body.slot),
    ]);
    return json({ ok: true });
  }

  if (path === '/api/snooze' && method === 'POST') {
    const body = await readJson<{ reminderId: string; minutes?: number }>(req);
    if (!body || typeof body.reminderId !== 'string') return bad('invalid body');
    const src = await env.DB.prepare('SELECT * FROM reminders WHERE device_id = ? AND id = ?').bind(deviceId, body.reminderId).first<ReminderRow>();
    if (!src) return bad('not found', 404);
    const minutes = Math.min(180, Math.max(5, Math.round(body.minutes ?? 30)));
    const r: ReminderIn = {
      id: `snooze:${src.slot ?? 'x'}:${src.date ?? ''}`,
      fireAt: Date.now() + minutes * 60_000,
      kind: 'snooze',
      slot: (src.slot as 'am' | 'pm' | null) ?? undefined,
      date: src.date ?? undefined,
      title: src.title,
      body: src.body,
      url: src.url,
    };
    await insertReminder(env, deviceId, r, true).run();
    return json({ ok: true, fireAt: r.fireAt });
  }

  if (path === '/api/timer' && method === 'POST') {
    const body = await readJson<ReminderIn>(req);
    const r = body && cleanReminder({ ...body, id: 'timer', kind: 'timer' });
    if (!r || r.fireAt < Date.now() || r.fireAt > Date.now() + 3 * 3600_000) return bad('invalid timer');
    await insertReminder(env, deviceId, r, true).run();
    return json({ ok: true });
  }

  if (path === '/api/timer' && method === 'DELETE') {
    await env.DB.prepare("DELETE FROM reminders WHERE device_id = ? AND id = 'timer' AND sent_at IS NULL").bind(deviceId).run();
    return json({ ok: true });
  }

  if (path === '/api/test' && method === 'POST') {
    const dev = await env.DB.prepare('SELECT endpoint, p256dh, auth FROM devices WHERE id = ?').bind(deviceId).first<DeviceRow>();
    if (!dev?.endpoint) return bad('no subscription', 409);
    const payload: PushPayload = {
      title: 'Reminders are on',
      body: 'This is how Barrier will tap you on the shoulder. See you tonight.',
      url: '/', tag: 'test', kind: 'main', reminderId: 'test',
    };
    const res = await sendPush({ endpoint: dev.endpoint, keys: { p256dh: dev.p256dh!, auth: dev.auth! } }, payload, vapid(env));
    if (res.gone) await env.DB.prepare('UPDATE devices SET endpoint = NULL WHERE id = ?').bind(deviceId).run();
    return json({ ok: res.ok, status: res.status, detail: res.text }, res.ok ? 200 : 502);
  }

  if (path === '/api/status' && method === 'GET') {
    const dev = await env.DB.prepare('SELECT endpoint, synced_at FROM devices WHERE id = ?').bind(deviceId).first<{ endpoint: string | null; synced_at: number }>();
    const next = await env.DB.prepare('SELECT fire_at, title FROM reminders WHERE device_id = ? AND sent_at IS NULL ORDER BY fire_at LIMIT 1')
      .bind(deviceId).first<{ fire_at: number; title: string }>();
    const count = await env.DB.prepare('SELECT COUNT(*) AS n FROM reminders WHERE device_id = ? AND sent_at IS NULL').bind(deviceId).first<{ n: number }>();
    return json({ subscribed: !!dev?.endpoint, syncedAt: dev?.synced_at, pending: count?.n ?? 0, next });
  }

  if (path === '/api/unregister' && method === 'POST') {
    await env.DB.batch([
      env.DB.prepare('DELETE FROM reminders WHERE device_id = ?').bind(deviceId),
      env.DB.prepare('DELETE FROM acks WHERE device_id = ?').bind(deviceId),
      env.DB.prepare('DELETE FROM devices WHERE id = ?').bind(deviceId),
    ]);
    return json({ ok: true });
  }

  return bad('not found', 404);
}

interface ReminderRow {
  device_id: string;
  id: string;
  fire_at: number;
  kind: string;
  slot: string | null;
  date: string | null;
  title: string;
  body: string;
  url: string;
  generic_title: string | null;
  generic_body: string | null;
}

interface DeviceRow {
  endpoint: string | null;
  p256dh: string | null;
  auth: string | null;
  synced_at?: number;
}

/** The once-a-minute sender. */
export async function sendDue(env: Env, now = Date.now()): Promise<{ sent: number; skipped: number; failed: number }> {
  const due = await env.DB.prepare(
    `SELECT r.*, d.endpoint, d.p256dh, d.auth, d.synced_at FROM reminders r
     JOIN devices d ON d.id = r.device_id
     WHERE r.sent_at IS NULL AND r.fire_at <= ? AND r.fire_at > ? AND d.endpoint IS NOT NULL
     ORDER BY r.fire_at LIMIT 200`,
  ).bind(now, now - 3 * 3600_000).all<ReminderRow & DeviceRow>();

  let sent = 0;
  let skipped = 0;
  let failed = 0;
  const keys = vapid(env);

  for (const r of due.results ?? []) {
    // Claim the row first so an overlapping cron run can't double-send.
    const claim = await env.DB.prepare('UPDATE reminders SET sent_at = ? WHERE device_id = ? AND id = ? AND sent_at IS NULL')
      .bind(now, r.device_id, r.id).run();
    if (!claim.meta.changes) continue;

    let title = r.title;
    let body = r.body;
    if (r.slot && r.date && ['main', 'nudge', 'snooze'].includes(r.kind)) {
      const acked = await env.DB.prepare('SELECT 1 AS x FROM acks WHERE device_id = ? AND date = ? AND slot = ?')
        .bind(r.device_id, r.date, r.slot).first();
      if (acked) {
        skipped++;
        continue;
      }
      // An earlier reminder for this slot went out after the phone last synced
      // and was never answered: the planned night may be off, so stay generic.
      const stale = await env.DB.prepare(
        `SELECT 1 AS x FROM reminders p WHERE p.device_id = ? AND p.slot = ? AND p.kind = 'main'
         AND p.sent_at IS NOT NULL AND p.sent_at > ? AND p.date < ?
         AND NOT EXISTS (SELECT 1 FROM acks a WHERE a.device_id = p.device_id AND a.date = p.date AND a.slot = p.slot)
         LIMIT 1`,
      ).bind(r.device_id, r.slot, r.synced_at ?? 0, r.date).first();
      if (stale && r.generic_title) {
        title = r.generic_title;
        body = r.generic_body ?? body;
      }
    }

    const payload: PushPayload = {
      title, body, url: r.url,
      tag: r.slot && r.date ? `${r.date}:${r.slot}` : r.id,
      kind: r.kind as PushPayload['kind'],
      slot: (r.slot as 'am' | 'pm' | null) ?? undefined,
      date: r.date ?? undefined,
      reminderId: r.id,
    };
    try {
      const res = await sendPush({ endpoint: r.endpoint!, keys: { p256dh: r.p256dh!, auth: r.auth! } }, payload, keys, {
        ttl: r.kind === 'timer' ? 600 : 4 * 3600,
      });
      if (res.ok) sent++;
      else {
        failed++;
        if (res.gone) await env.DB.prepare('UPDATE devices SET endpoint = NULL WHERE id = ?').bind(r.device_id).run();
        else await env.DB.prepare('UPDATE devices SET failures = failures + 1 WHERE id = ?').bind(r.device_id).run();
        console.log('push failed', res.status, res.text);
      }
    } catch (e) {
      failed++;
      console.log('push error', String(e));
    }
  }

  // Housekeeping: expire what was never sent in time, drop old rows.
  await env.DB.batch([
    env.DB.prepare('UPDATE reminders SET sent_at = -1 WHERE sent_at IS NULL AND fire_at <= ?').bind(now - 3 * 3600_000),
    env.DB.prepare('DELETE FROM reminders WHERE fire_at < ?').bind(now - 7 * 86_400_000),
  ]);
  return { sent, skipped, failed };
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    if (url.pathname.startsWith('/api/')) {
      try {
        return await api(req, env, url.pathname);
      } catch (e) {
        console.log('api error', String(e));
        return bad('server error', 500);
      }
    }
    return env.ASSETS.fetch(req);
  },

  async scheduled(_event: ScheduledController, env: Env, ctx: ExecutionContext): Promise<void> {
    ctx.waitUntil(sendDue(env).then((r) => {
      if (r.sent || r.failed) console.log('cron', JSON.stringify(r));
    }));
  },
} satisfies ExportedHandler<Env>;
