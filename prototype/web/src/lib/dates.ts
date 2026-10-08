import type { ISODate } from './types';

/** Before this hour, the app still treats it as "yesterday" (late-night routines). */
export const DAY_ROLLOVER_HOUR = 4;

const pad = (n: number) => String(n).padStart(2, '0');

export function toISO(d: Date): ISODate {
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

/** Local midnight of an ISO date. */
export function fromISO(iso: ISODate): Date {
  const [y, m, d] = iso.split('-').map(Number);
  return new Date(y, m - 1, d);
}

export function addDays(iso: ISODate, n: number): ISODate {
  const d = fromISO(iso);
  d.setDate(d.getDate() + n);
  return toISO(d);
}

/** Whole calendar days from a to b (b - a). DST-safe. */
export function daysBetween(a: ISODate, b: ISODate): number {
  const [ay, am, ad] = a.split('-').map(Number);
  const [by, bm, bd] = b.split('-').map(Number);
  return Math.round((Date.UTC(by, bm - 1, bd) - Date.UTC(ay, am - 1, ad)) / 86_400_000);
}

export function weekday(iso: ISODate): number {
  return fromISO(iso).getDay();
}

/** The routine day "now" belongs to (a 1 a.m. routine counts for the evening before). */
export function routineToday(now: Date = new Date()): ISODate {
  const d = new Date(now);
  if (d.getHours() < DAY_ROLLOVER_HOUR) d.setDate(d.getDate() - 1);
  return toISO(d);
}

/** Absolute time of HH:MM on a local date. Times before the rollover hour fall on the next calendar day. */
export function atTime(iso: ISODate, hhmm: string): Date {
  const [h, m] = hhmm.split(':').map(Number);
  const d = fromISO(iso);
  if (h < DAY_ROLLOVER_HOUR) d.setDate(d.getDate() + 1);
  d.setHours(h, m, 0, 0);
  return d;
}

export function minutesOf(hhmm: string): number {
  const [h, m] = hhmm.split(':').map(Number);
  return h * 60 + m;
}

const WD_SHORT = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const WD_LONG = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const MONTHS_LONG = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

export const weekdayShort = (i: number) => WD_SHORT[i];
export const weekdayLong = (i: number) => WD_LONG[i];
export const monthLong = (i: number) => MONTHS_LONG[i];

/** "Thu, Oct 9" */
export function shortDate(iso: ISODate): string {
  const d = fromISO(iso);
  return `${WD_SHORT[d.getDay()]}, ${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

/** "October 9" */
export function longDate(iso: ISODate): string {
  const d = fromISO(iso);
  return `${MONTHS_LONG[d.getMonth()]} ${d.getDate()}`;
}

/** "Oct 9" */
export function monthDay(iso: ISODate): string {
  const d = fromISO(iso);
  return `${MONTHS[d.getMonth()]} ${d.getDate()}`;
}

/** Relative day word: "tonight"/"today", "tomorrow", "Sat", "Oct 21". */
export function relativeDay(from: ISODate, to: ISODate, evening = true): string {
  const n = daysBetween(from, to);
  if (n === 0) return evening ? 'tonight' : 'today';
  if (n === 1) return evening ? 'tomorrow night' : 'tomorrow';
  if (n === -1) return evening ? 'last night' : 'yesterday';
  if (n > 1 && n < 7) return WD_LONG[weekday(to)];
  return monthDay(to);
}

/** 24h "21:30" → "9:30 PM" or keep 24h depending on locale preference. */
export function formatTime(hhmm: string, h12 = uses12h()): string {
  const [h, m] = hhmm.split(':').map(Number);
  if (!h12) return `${pad(h)}:${pad(m)}`;
  const suffix = h >= 12 ? 'PM' : 'AM';
  const hh = h % 12 === 0 ? 12 : h % 12;
  return `${hh}:${pad(m)} ${suffix}`;
}

let cached12h: boolean | undefined;
export function uses12h(): boolean {
  if (cached12h === undefined) {
    try {
      cached12h = new Intl.DateTimeFormat(undefined, { hour: 'numeric' }).resolvedOptions().hour12 === true;
    } catch {
      cached12h = false;
    }
  }
  return cached12h;
}

export function timezone(): string {
  try {
    return Intl.DateTimeFormat().resolvedOptions().timeZone || 'UTC';
  } catch {
    return 'UTC';
  }
}
