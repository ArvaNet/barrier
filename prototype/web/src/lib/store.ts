import { create } from 'zustand';
import { addDays, routineToday } from './dates';
import { drainInbox, loadState, saveState } from './db';
import { instanceOn, type Instance } from './engine';
import { blankState, DEFAULT_SETTINGS } from './presets';
import type { AppState, CheckIn, Entry, Feeling, ISODate, Pause, PhotoMeta, Plan, Product, Question, Settings, Slot } from './types';
import { uid } from './uid';

interface Store {
  ready: boolean;
  s: AppState;
  /** Bumps on every change; the push sync listens to it. */
  rev: number;
  load: () => Promise<void>;
  replace: (s: AppState) => void;
  update: (fn: (s: AppState) => AppState) => void;
  // log
  markDone: (inst: Instance, steps?: string[]) => void;
  markSkipped: (inst: Instance) => void;
  clearEntry: (date: ISODate, slot: Slot) => void;
  setRecovery: (date: ISODate, slot: Slot, on: boolean) => void;
  // plan
  setPlan: (fn: (p: Plan) => Plan) => void;
  upsertProduct: (p: Product) => void;
  removeProduct: (id: string) => void;
  // journal
  checkIn: (date: ISODate, feel: Feeling[], note?: string) => void;
  addPause: (p: Omit<Pause, 'id'>) => void;
  endPause: (id: string, today: ISODate) => void;
  addPhoto: (m: PhotoMeta) => void;
  removePhoto: (id: string) => void;
  addQuestion: (text: string) => void;
  toggleQuestion: (id: string) => void;
  removeQuestion: (id: string) => void;
  setSettings: (patch: Partial<Settings>) => void;
  dismiss: (id: string) => void;
  ingestInbox: () => Promise<void>;
}

let saveTimer: ReturnType<typeof setTimeout> | undefined;
function persist(s: AppState) {
  clearTimeout(saveTimer);
  saveTimer = setTimeout(() => void saveState(s), 250);
}

/** Flush pending writes right away (page hide). */
export function flushSave() {
  if (saveTimer) {
    clearTimeout(saveTimer);
    saveTimer = undefined;
    void saveState(useStore.getState().s);
  }
}

function upsertEntry(log: Entry[], e: Entry): Entry[] {
  return [...log.filter((x) => !(x.date === e.date && x.slot === e.slot)), e].sort((a, b) =>
    a.date === b.date ? (a.slot < b.slot ? -1 : 1) : a.date < b.date ? -1 : 1,
  );
}

/** Fill in fields added after a state was first saved. */
function migrate(s: AppState): AppState {
  return {
    ...blankState(routineToday()),
    ...s,
    settings: { ...DEFAULT_SETTINGS, ...s.settings },
    dismissed: s.dismissed ?? [],
    milestonesSeen: s.milestonesSeen ?? [],
    questions: s.questions ?? [],
    photos: s.photos ?? [],
    pauses: s.pauses ?? [],
    checkins: s.checkins ?? [],
  };
}

export const useStore = create<Store>((set, get) => {
  const commit = (fn: (s: AppState) => AppState) => {
    const next = fn(get().s);
    set({ s: next, rev: get().rev + 1 });
    persist(next);
  };

  return {
    ready: false,
    s: blankState(routineToday()),
    rev: 0,

    load: async () => {
      let s: AppState | undefined;
      try {
        s = await loadState();
      } catch (e) {
        console.error('load failed', e);
      }
      set({ s: s ? migrate(s) : blankState(routineToday()), ready: true });
      await get().ingestInbox();
    },

    replace: (s) => commit(() => migrate(s)),
    update: commit,

    markDone: (inst, steps) =>
      commit((s) => {
        const prev = s.log.find((e) => e.date === inst.date && e.slot === inst.slot);
        const e: Entry = {
          date: inst.date, slot: inst.slot, status: 'done', pos: inst.pos, label: inst.label, hue: inst.hue, at: Date.now(),
        };
        if (prev?.recovery) e.recovery = true;
        if (steps) e.steps = steps;
        return { ...s, log: upsertEntry(s.log, e) };
      }),

    markSkipped: (inst) =>
      commit((s) => ({
        ...s,
        log: upsertEntry(s.log, {
          date: inst.date, slot: inst.slot, status: 'skipped', pos: inst.pos, label: inst.label, hue: inst.hue, at: Date.now(),
        }),
      })),

    clearEntry: (date, slot) => commit((s) => ({ ...s, log: s.log.filter((e) => !(e.date === date && e.slot === slot)) })),

    setRecovery: (date, slot, on) =>
      commit((s) => {
        const prev = s.log.find((e) => e.date === date && e.slot === slot);
        if (on) {
          const e: Entry = { ...(prev ?? { date, slot, status: 'open', at: Date.now() }), recovery: true, label: 'Recovery night', hue: 'sage' };
          return { ...s, log: upsertEntry(s.log, e) };
        }
        if (!prev) return s;
        if (prev.status === 'open') return { ...s, log: s.log.filter((e) => e !== prev) };
        const { recovery: _r, ...rest } = prev;
        return { ...s, log: upsertEntry(s.log, rest) };
      }),

    setPlan: (fn) => commit((s) => ({ ...s, plan: fn(s.plan) })),

    upsertProduct: (p) =>
      commit((s) => {
        const exists = s.products.some((x) => x.id === p.id);
        return { ...s, products: exists ? s.products.map((x) => (x.id === p.id ? p : x)) : [...s.products, p] };
      }),

    removeProduct: (id) =>
      commit((s) => ({
        ...s,
        products: s.products.filter((p) => p.id !== id),
        plan: {
          ...s.plan,
          am: { ...s.plan.am, steps: s.plan.am.steps.filter((x) => x.productId !== id) },
          pm: { ...s.plan.pm, steps: s.plan.pm.steps.filter((x) => x.productId !== id) },
        },
      })),

    checkIn: (date, feel, note) =>
      commit((s) => {
        const c: CheckIn = { date, feel, at: Date.now() };
        if (note) c.note = note;
        return { ...s, checkins: [...s.checkins.filter((x) => x.date !== date), c].sort((a, b) => (a.date < b.date ? -1 : 1)) };
      }),

    addPause: (p) => commit((s) => ({ ...s, pauses: [...s.pauses, { ...p, id: uid() }] })),
    endPause: (id, today) =>
      commit((s) => ({
        ...s,
        pauses: s.pauses
          .map((p) => (p.id === id ? { ...p, to: today > p.from ? addDays(today, -1) : p.from } : p))
          .filter((p) => !(p.id === id && today <= p.from)),
      })),

    addPhoto: (m) => commit((s) => ({ ...s, photos: [...s.photos, m].sort((a, b) => a.at - b.at) })),
    removePhoto: (id) => commit((s) => ({ ...s, photos: s.photos.filter((p) => p.id !== id) })),

    addQuestion: (text) => commit((s) => ({ ...s, questions: [...s.questions, { id: uid(), text, at: Date.now() } as Question] })),
    toggleQuestion: (id) => commit((s) => ({ ...s, questions: s.questions.map((q) => (q.id === id ? { ...q, answered: !q.answered } : q)) })),
    removeQuestion: (id) => commit((s) => ({ ...s, questions: s.questions.filter((q) => q.id !== id) })),

    setSettings: (patch) => commit((s) => ({ ...s, settings: { ...s.settings, ...patch } })),
    dismiss: (id) => commit((s) => (s.dismissed.includes(id) ? s : { ...s, dismissed: [...s.dismissed, id] })),

    ingestInbox: async () => {
      let items;
      try {
        items = await drainInbox();
      } catch {
        return;
      }
      if (!items.length) return;
      const today = routineToday();
      commit((s) => {
        let log = s.log;
        for (const it of items) {
          if (log.some((e) => e.date === it.date && e.slot === it.slot && e.status === 'done')) continue;
          const inst = instanceOn({ ...s, log }, it.slot, it.date, today);
          log = upsertEntry(log, {
            date: it.date, slot: it.slot, status: 'done', pos: inst.pos, label: inst.label, hue: inst.hue, at: it.at,
          });
        }
        return { ...s, log };
      });
    },
  };
});

// ---------------------------------------------------------------------------
// Clock: the current routine day, refreshed every minute and on focus.

interface Clock {
  now: number;
  today: ISODate;
  tick: () => void;
}

export const useClock = create<Clock>((set) => ({
  now: Date.now(),
  today: routineToday(),
  tick: () => set({ now: Date.now(), today: routineToday() }),
}));

if (typeof window !== 'undefined') {
  setInterval(() => useClock.getState().tick(), 30_000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      useClock.getState().tick();
      void useStore.getState().ingestInbox();
    } else {
      flushSave();
    }
  });
  window.addEventListener('pagehide', flushSave);
}
