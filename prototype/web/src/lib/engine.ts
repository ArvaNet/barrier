// The schedule engine. Pure functions only: state in, answers out.
//
// A slot (morning or evening) runs a rotation of `length` positions. The
// rotation advances one position per night that actually happened. A night
// with actives that was skipped or never logged does NOT advance it, so the
// next night picks up where you left off ("Barrier never skips ahead").
// Nights without actives (recovery) advance even when unlogged: the skin
// rested either way.

import { addDays, daysBetween, weekday } from './dates';
import type {
  AppState, Entry, Hue, ISODate, Product, ProductKind, Slot, SlotPlan, Step,
} from './types';

export const ACTIVE_KINDS: ProductKind[] = ['retinoid', 'exfoliant', 'treatment'];
export const isActiveKind = (k: ProductKind) => ACTIVE_KINDS.includes(k);

export interface DueStep {
  step: Step;
  product: Product;
  active: boolean;
}

export type RestReason = 'rotation' | 'inserted' | 'pause';

export type InstanceStatus =
  | 'done' // logged as done
  | 'skipped' // logged as not done
  | 'pending' // today, not logged yet
  | 'future'
  | 'unlogged' // in the past, nothing logged
  | 'off'; // slot disabled or before the plan existed

export interface Instance {
  date: ISODate;
  slot: Slot;
  pos: number;
  cycleLen: number;
  length: number;
  rest: RestReason | null;
  steps: DueStep[];
  label: string;
  hue: Hue;
  entry?: Entry;
  status: InstanceStatus;
  hasActives: boolean;
  conflicts: ConflictId[];
  phase: number; // ease-in phase index; phases.length = full plan
  easing: boolean;
  /** A product's course ends on this date. */
  lastDayOf: Product[];
}

export type ConflictId = 'retinoid+exfoliant' | 'bpo+tretinoin';

// ---------------------------------------------------------------------------

export function productMap(products: Product[]): Map<string, Product> {
  return new Map(products.map((p) => [p.id, p]));
}

export function phaseOn(sp: SlotPlan, date: ISODate): { index: number; extraRest: number } {
  const ease = sp.easeIn;
  if (!ease || ease.phases.length === 0) return { index: 0, extraRest: 0 };
  let day = Math.max(0, daysBetween(ease.start, date));
  for (let i = 0; i < ease.phases.length; i++) {
    if (day < ease.phases[i].days) return { index: i, extraRest: ease.phases[i].extraRest };
    day -= ease.phases[i].days;
  }
  return { index: ease.phases.length, extraRest: 0 };
}

export function cycleLenOn(sp: SlotPlan, date: ISODate): number {
  return Math.max(1, sp.length) + phaseOn(sp, date).extraRest;
}

export function isPaused(state: Pick<AppState, 'pauses'>, date: ISODate): boolean {
  return state.pauses.some((p) => p.from <= date && date <= p.to);
}

function inWindow(p: Product, date: ISODate): boolean {
  if (p.from && date < p.from) return false;
  if (p.until && date > p.until) return false;
  return true;
}

/** Steps due on a date at a rotation position. Rest mode drops actives. */
export function dueSteps(
  sp: SlotPlan,
  products: Map<string, Product>,
  date: ISODate,
  pos: number,
  restMode: boolean,
): DueStep[] {
  const out: DueStep[] = [];
  const restPos = pos >= sp.length;
  const wd = weekday(date);
  for (const step of sp.steps) {
    const product = products.get(step.productId);
    if (!product || !inWindow(product, date)) continue;
    const active = isActiveKind(product.kind);
    let due = false;
    if (step.on.type === 'all') due = true;
    else if (step.on.type === 'nights') due = !restPos && step.on.nights.includes(pos);
    else due = step.on.days.includes(wd);
    if (!due) continue;
    if ((restMode || restPos) && active) continue;
    out.push({ step, product, active });
  }
  return out;
}

/** Whether a base position (ignoring weekday steps and windows) carries actives. */
function positionHasActives(sp: SlotPlan, products: Map<string, Product>, pos: number): boolean {
  if (pos >= sp.length) return false;
  return sp.steps.some((s) => {
    const p = products.get(s.productId);
    if (!p || !isActiveKind(p.kind)) return false;
    return s.on.type === 'all' || (s.on.type === 'nights' && s.on.nights.includes(pos));
  });
}

const shortName = (p: Product) => p.name.replace(/\s*\d+([.,]\d+)?\s*%.*$/, '').trim() || p.name;

export function labelFor(
  slot: Slot,
  steps: DueStep[],
  rest: RestReason | null,
  sp: SlotPlan,
  pos: number,
  products: Map<string, Product>,
): { label: string; hue: Hue } {
  const word = slot === 'pm' ? 'night' : 'morning';
  if (rest === 'pause') return { label: `Simple ${word}`, hue: slot === 'pm' ? 'mist' : 'dawn' };
  if (rest === 'inserted') return { label: slot === 'pm' ? 'Recovery night' : 'Gentle morning', hue: 'sage' };
  const custom = sp.names?.[pos];
  const actives = steps.filter((s) => s.active);
  const has = (k: ProductKind) => actives.some((s) => s.product.kind === k);
  let label: string;
  let hue: Hue;
  if (has('retinoid') && has('exfoliant')) {
    label = `Retinoid + exfoliant ${word}`;
    hue = 'clay';
  } else if (has('retinoid')) {
    label = `Retinoid ${word}`;
    hue = 'clay';
  } else if (has('exfoliant')) {
    label = `Exfoliation ${word}`;
    hue = 'gold';
  } else if (actives.length === 1) {
    label = `${shortName(actives[0].product)} ${word}`;
    hue = 'rose';
  } else if (actives.length > 1) {
    label = `Treatment ${word}`;
    hue = 'rose';
  } else if (slot === 'am') {
    label = 'Morning routine';
    hue = 'dawn';
  } else {
    label = 'Recovery night';
    // Second recovery night in a row reads as "mist", like skin cycling's night 4.
    const prev = pos - 1;
    const prevIsRest = sp.length > 1 && (prev < 0 ? !positionHasActives(sp, products, sp.length - 1) : !positionHasActives(sp, products, prev));
    hue = prevIsRest && pos > 0 ? 'mist' : 'sage';
  }
  return { label: custom || label, hue };
}

export function conflictsIn(steps: DueStep[]): ConflictId[] {
  const out: ConflictId[] = [];
  const kinds = new Set(steps.map((s) => s.product.kind));
  if (kinds.has('retinoid') && kinds.has('exfoliant')) out.push('retinoid+exfoliant');
  const names = steps.map((s) => s.product.name.toLowerCase());
  const hasBpo = names.some((n) => n.includes('benzoyl'));
  const hasTret = steps.some((s) => s.product.kind === 'retinoid' && /tretinoin|retin-?a/i.test(s.product.name));
  if (hasBpo && hasTret) out.push('bpo+tretinoin');
  return out;
}

function findEntry(log: Entry[], date: ISODate, slot: Slot): Entry | undefined {
  for (let i = log.length - 1; i >= 0; i--) {
    const e = log[i];
    if (e.date === date && e.slot === slot) return e;
  }
  return undefined;
}

/**
 * Every instance of a slot from `from` to `to` (inclusive). Past days replay
 * the log; today and later are projected assuming each night happens.
 */
export function timeline(
  state: AppState,
  slot: Slot,
  from: ISODate,
  to: ISODate,
  today: ISODate,
): Instance[] {
  const sp = state.plan[slot];
  const products = productMap(state.products);
  const out: Instance[] = [];
  const anchor = sp.anchor;

  // Days before the anchor: history snapshots only.
  for (let d = from; d <= to && d < anchor.date; d = addDays(d, 1)) {
    const entry = findEntry(state.log, d, slot);
    out.push({
      date: d, slot, pos: entry?.pos ?? 0, cycleLen: sp.length, length: sp.length,
      rest: null, steps: [], label: entry?.label ?? '', hue: entry?.hue ?? 'sage', entry,
      status: entry ? (entry.status === 'done' ? 'done' : 'skipped') : 'off',
      hasActives: false, conflicts: [], phase: 0, easing: false, lastDayOf: [],
    });
  }

  let pos = anchor.pos;
  const totalPhases = sp.easeIn?.phases.length ?? 0;
  for (let d = anchor.date; d <= to; d = addDays(d, 1)) {
    const ph = phaseOn(sp, d);
    const cl = Math.max(1, sp.length) + ph.extraRest;
    if (pos >= cl || pos < 0) pos = 0;

    const entry = findEntry(state.log, d, slot);
    const paused = isPaused(state, d);
    const restPos = pos >= sp.length;
    const rest: RestReason | null = paused ? 'pause' : entry?.recovery ? 'inserted' : restPos ? 'rotation' : null;
    const full = dueSteps(sp, products, d, pos, false);
    const hasActives = full.some((s) => s.active);
    const steps = rest ? dueSteps(sp, products, d, pos, true) : full;

    if (d >= from) {
      const { label, hue } = labelFor(slot, steps, rest, sp, pos, products);
      let status: InstanceStatus;
      if (!sp.enabled) status = 'off';
      else if (entry?.status === 'done') status = 'done';
      else if (entry?.status === 'skipped') status = 'skipped';
      else if (d < today) status = 'unlogged';
      else if (d === today) status = 'pending';
      else status = 'future';
      out.push({
        date: d, slot, pos, cycleLen: cl, length: sp.length, rest, steps, label, hue, entry, status,
        hasActives: hasActives && !rest,
        conflicts: conflictsIn(steps),
        phase: ph.index,
        easing: totalPhases > 0 && ph.index < totalPhases,
        lastDayOf: state.products.filter((p) => p.until === d && steps.some((s) => s.product.id === p.id)),
      });
    }

    // Advance the rotation for the next day.
    if (!sp.enabled || paused || entry?.recovery) continue;
    const needsLog = hasActives && !restPos;
    let advance: boolean;
    if (d < today) advance = entry?.status === 'done' || !needsLog;
    else if (d === today) advance = entry?.status !== 'skipped' || !needsLog;
    else advance = true;
    if (advance) pos = (pos + 1) % cl;
  }
  return out;
}

export function instanceOn(state: AppState, slot: Slot, date: ISODate, today: ISODate): Instance {
  return timeline(state, slot, date, date, today)[0];
}

/** Past nights with actives that were never logged, earliest first (max 2 days back). */
export function needsReconcile(state: AppState, today: ISODate): Instance[] {
  const out: Instance[] = [];
  for (const slot of ['pm', 'am'] as Slot[]) {
    if (!state.plan[slot].enabled) continue;
    const from = addDays(today, -2);
    if (from < state.plan.createdAt && addDays(today, -1) < state.plan.createdAt) continue;
    for (const inst of timeline(state, slot, from, addDays(today, -1), today)) {
      if (inst.date < state.plan.createdAt) continue;
      if (inst.status === 'unlogged' && inst.hasActives) out.push(inst);
    }
  }
  return out.sort((a, b) => (a.date === b.date ? (a.slot === 'am' ? -1 : 1) : a.date < b.date ? -1 : 1));
}

/** Next date (after `today`) when a step with this product kind is due. */
export function nextOf(
  state: AppState,
  slot: Slot,
  today: ISODate,
  match: (s: DueStep) => boolean,
  horizon = 21,
): Instance | undefined {
  const tl = timeline(state, slot, addDays(today, 1), addDays(today, horizon), today);
  return tl.find((i) => i.steps.some(match));
}

// ---------------------------------------------------------------------------
// Stats & rings

export interface Stats {
  nightsDone: number;
  morningsDone: number;
  last28: { done: number; due: number };
  firstDate?: ISODate;
  byLabel: Record<string, number>;
}

export function stats(state: AppState, today: ISODate): Stats {
  const byLabel: Record<string, number> = {};
  let nightsDone = 0;
  let morningsDone = 0;
  let firstDate: ISODate | undefined;
  for (const e of state.log) {
    if (e.status !== 'done') continue;
    if (e.slot === 'pm') nightsDone++;
    else morningsDone++;
    if (!firstDate || e.date < firstDate) firstDate = e.date;
    if (e.slot === 'pm' && e.label) byLabel[e.label] = (byLabel[e.label] ?? 0) + 1;
  }
  const from = addDays(today, -27) < state.plan.createdAt ? state.plan.createdAt : addDays(today, -27);
  let done = 0;
  let due = 0;
  if (state.plan.pm.enabled && from <= today) {
    for (const i of timeline(state, 'pm', from, today, today)) {
      if (i.status === 'off') continue;
      if (i.date === today && i.status === 'pending') continue;
      due++;
      if (i.status === 'done') done++;
    }
  }
  return { nightsDone, morningsDone, last28: { done, due }, firstDate, byLabel };
}

export interface Ring {
  from: ISODate;
  to: ISODate;
  segments: { hue: Hue; done: boolean; date: ISODate }[];
}

/**
 * Growth rings for the Progress screen: one ring per rotation cycle when the
 * rotation is 3+ nights, otherwise one per week. The newest ring is last.
 */
export function rings(state: AppState, today: ISODate, max = 24): Ring[] {
  const sp = state.plan.pm;
  const start = state.plan.createdAt;
  if (!sp.enabled || start > today) return [];
  const tl = timeline(state, 'pm', start, today, today);
  const out: Ring[] = [];
  const byCycle = sp.length >= 3;
  let cur: Ring | null = null;
  for (const inst of tl) {
    const boundary = byCycle ? inst.pos === 0 && inst.rest !== 'inserted' && inst.rest !== 'pause' : weekday(inst.date) === 1;
    if (!cur || (boundary && cur.segments.length > 0)) {
      cur = { from: inst.date, to: inst.date, segments: [] };
      out.push(cur);
    }
    cur.to = inst.date;
    cur.segments.push({ hue: inst.hue, done: inst.status === 'done', date: inst.date });
  }
  return out.slice(-max);
}

// ---------------------------------------------------------------------------
// Editing helpers

export function lcm(a: number, b: number): number {
  const g = (x: number, y: number): number => (y === 0 ? x : g(y, x % y));
  return (a * b) / g(a, b);
}

/** Positions a step is on, within the base rotation. */
export function nightsOf(step: Step, length: number): number[] {
  if (step.on.type === 'all') return Array.from({ length }, (_, i) => i);
  if (step.on.type === 'nights') return step.on.nights.filter((n) => n < length);
  return [];
}

/**
 * Change the rotation length, keeping each step's pattern: a step on every
 * other night stays on every other night.
 */
export function resizeRotation(sp: SlotPlan, newLength: number): SlotPlan {
  const old = sp.length;
  const steps = sp.steps.map((s) => {
    if (s.on.type !== 'nights') return s;
    const set = new Set(s.on.nights);
    const nights: number[] = [];
    for (let i = 0; i < newLength; i++) if (set.has(i % old)) nights.push(i);
    return { ...s, on: { type: 'nights' as const, nights } };
  });
  return { ...sp, length: newLength, steps, names: undefined };
}

/**
 * Put a step on "every Nth night", choosing the offset that collides least
 * with other actives. Grows the rotation if needed (up to 8).
 */
export function setEvery(sp: SlotPlan, stepId: string, n: number, products: Map<string, Product>): SlotPlan {
  let plan = sp;
  if (n <= 1) {
    return { ...plan, steps: plan.steps.map((s) => (s.id === stepId ? { ...s, on: { type: 'all' } } : s)) };
  }
  const want = lcm(plan.length, n);
  if (want !== plan.length) plan = resizeRotation(plan, Math.min(want, 8));
  const L = plan.length;
  const usage = new Array(L).fill(0);
  for (const s of plan.steps) {
    if (s.id === stepId) continue;
    const p = products.get(s.productId);
    if (!p || !isActiveKind(p.kind)) continue;
    for (const i of nightsOf(s, L)) usage[i]++;
  }
  let best = 0;
  let bestScore = Infinity;
  for (let off = 0; off < n; off++) {
    let score = 0;
    for (let i = off; i < L; i += n) score += usage[i];
    if (score < bestScore) {
      bestScore = score;
      best = off;
    }
  }
  const nights: number[] = [];
  for (let i = best; i < L; i += n) nights.push(i);
  return { ...plan, steps: plan.steps.map((s) => (s.id === stepId ? { ...s, on: { type: 'nights', nights } } : s)) };
}

/** How a step's schedule reads in plain words. */
export function describeOn(step: Step, sp: SlotPlan): string {
  if (step.on.type === 'all') return 'Every time';
  if (step.on.type === 'weekdays') {
    const names = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    const d = [...step.on.days].sort((a, b) => a - b);
    if (d.length === 7) return 'Every day';
    return d.map((i) => names[i]).join(', ');
  }
  const n = step.on.nights;
  const L = sp.length;
  if (n.length === 0) return 'Not scheduled';
  if (n.length === L) return 'Every night';
  // Regular spacing?
  if (L % n.length === 0) {
    const gap = L / n.length;
    const regular = n.every((v, i) => i === 0 || v - n[i - 1] === gap);
    if (regular) {
      if (gap === 2) return 'Every other night';
      if (gap === 3) return 'Every 3rd night';
      return `Every ${gap}th night`;
    }
  }
  return `${n.length} of every ${L} nights`;
}

/** Every position of the rotation as it stands on a date (for the orbit). */
export function rotationNodes(state: AppState, slot: Slot, date: ISODate): { pos: number; label: string; hue: Hue; rest: boolean }[] {
  const sp = state.plan[slot];
  const products = productMap(state.products);
  const cl = cycleLenOn(sp, date);
  const out: { pos: number; label: string; hue: Hue; rest: boolean }[] = [];
  for (let i = 0; i < cl; i++) {
    const rest = i >= sp.length;
    const steps = dueSteps(sp, products, date, i, rest);
    const { label, hue } = labelFor(slot, steps, rest ? 'rotation' : null, sp, i, products);
    out.push({ pos: i, label, hue, rest });
  }
  return out;
}
