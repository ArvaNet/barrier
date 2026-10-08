-- Devices that turned on reminders. No routine data, only push details.
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  token_hash TEXT NOT NULL,
  endpoint TEXT,
  p256dh TEXT,
  auth TEXT,
  tz TEXT,
  synced_at INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL,
  failures INTEGER NOT NULL DEFAULT 0
);

-- Upcoming notifications, built on the phone.
CREATE TABLE reminders (
  device_id TEXT NOT NULL,
  id TEXT NOT NULL,
  fire_at INTEGER NOT NULL,
  kind TEXT NOT NULL,
  slot TEXT,
  date TEXT,
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  url TEXT NOT NULL,
  generic_title TEXT,
  generic_body TEXT,
  sent_at INTEGER,
  PRIMARY KEY (device_id, id)
);
CREATE INDEX reminders_due ON reminders (sent_at, fire_at);

-- "Done" taps from a notification, before the app has synced.
CREATE TABLE acks (
  device_id TEXT NOT NULL,
  date TEXT NOT NULL,
  slot TEXT NOT NULL,
  at INTEGER NOT NULL,
  PRIMARY KEY (device_id, date, slot)
);
