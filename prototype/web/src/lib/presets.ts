// Starting points. Everything here is editable afterwards: a preset only saves
// typing, it never locks the plan.

import type { AppState, ISODate, Product, ProductKind, Settings, SlotPlan, Step } from './types';
import { uid } from './uid';

export interface QuickProduct {
  key: string;
  name: string;
  kind: ProductKind;
  slot: 'am' | 'pm' | 'both';
  amount?: string;
  how?: string;
  waitMin?: number;
  /** Suggested frequency in the evening rotation (1 = nightly). */
  every?: number;
}

/** Common things a dermatologist prescribes or recommends. */
export const QUICK_PRODUCTS: QuickProduct[] = [
  { key: 'cleanser', name: 'Gentle cleanser', kind: 'cleanser', slot: 'both', how: 'Lukewarm water, pat dry' },
  { key: 'tretinoin', name: 'Tretinoin', kind: 'retinoid', slot: 'pm', amount: 'Pea-size for the whole face', how: 'On completely dry skin', every: 2 },
  { key: 'adapalene', name: 'Adapalene', kind: 'retinoid', slot: 'pm', amount: 'Pea-size for the whole face', how: 'On completely dry skin', every: 2 },
  { key: 'retinol', name: 'Retinol serum', kind: 'retinoid', slot: 'pm', amount: 'Pea-size', how: 'On dry skin', every: 2 },
  { key: 'azelaic', name: 'Azelaic acid', kind: 'treatment', slot: 'both', amount: 'Thin layer' },
  { key: 'bpo', name: 'Benzoyl peroxide', kind: 'treatment', slot: 'am', amount: 'Thin layer on affected areas' },
  { key: 'clinda', name: 'Clindamycin', kind: 'treatment', slot: 'am', amount: 'Thin layer on affected areas' },
  { key: 'metro', name: 'Metronidazole', kind: 'treatment', slot: 'both', amount: 'Thin layer' },
  { key: 'ivermectin', name: 'Ivermectin cream', kind: 'treatment', slot: 'pm', amount: 'Pea-size per area' },
  { key: 'exfoliant', name: 'Exfoliant (AHA/BHA)', kind: 'exfoliant', slot: 'pm', amount: 'Thin layer', every: 4 },
  { key: 'vitc', name: 'Vitamin C serum', kind: 'serum', slot: 'am', amount: '3–4 drops' },
  { key: 'niacinamide', name: 'Niacinamide serum', kind: 'serum', slot: 'both', amount: '2–3 drops' },
  { key: 'moisturizer', name: 'Moisturizer', kind: 'moisturizer', slot: 'both' },
  { key: 'spf', name: 'Sunscreen SPF 30+', kind: 'spf', slot: 'am', how: 'Last step of the morning. Broad-spectrum.' },
  { key: 'oral', name: 'Oral medication', kind: 'oral', slot: 'am', how: 'With food and a full glass of water' },
];

export const KIND_LABEL: Record<ProductKind, string> = {
  cleanser: 'Cleanser',
  retinoid: 'Retinoid',
  exfoliant: 'Exfoliant',
  treatment: 'Treatment',
  serum: 'Serum',
  moisturizer: 'Moisturizer',
  spf: 'Sunscreen',
  oral: 'Medication',
  other: 'Other',
};

/** Where a new step of this kind goes in the order. */
export const KIND_ORDER: Record<ProductKind, number> = {
  oral: 0, cleanser: 1, exfoliant: 2, retinoid: 3, treatment: 3, serum: 4, moisturizer: 5, spf: 6, other: 5,
};

export function emptySlot(time: string, today: ISODate, enabled = true): SlotPlan {
  return { enabled, time, length: 1, steps: [], anchor: { date: today, pos: 0 } };
}

export const DEFAULT_SETTINGS: Settings = {
  theme: 'auto',
  nudge: true,
  nudgeAfterMin: 45,
  spfMidday: false,
  spfTime: '13:00',
  photoDay: 0,
  sound: true,
};

export function blankState(today: ISODate): AppState {
  return {
    version: 1,
    onboarded: false,
    plan: {
      am: emptySlot('08:00', today),
      pm: emptySlot('21:30', today),
      createdAt: today,
    },
    products: [],
    log: [],
    checkins: [],
    pauses: [],
    photos: [],
    questions: [],
    settings: { ...DEFAULT_SETTINGS },
    dismissed: [],
    milestonesSeen: [],
  };
}

export function makeProduct(q: Pick<QuickProduct, 'name' | 'kind'>, today: ISODate): Product {
  const p: Product = { id: uid(), name: q.name, kind: q.kind };
  if (q.kind === 'retinoid' || q.kind === 'treatment' || q.kind === 'exfoliant' || q.kind === 'oral') p.from = today;
  return p;
}

export function makeStep(productId: string, q: Partial<QuickProduct>): Step {
  const s: Step = { id: uid(), productId, on: { type: 'all' } };
  if (q.amount) s.amount = q.amount;
  if (q.how) s.how = q.how;
  if (q.waitMin) s.waitMin = q.waitMin;
  return s;
}

/** Insert a step in a sensible position based on product kind. */
export function insertByKind(steps: Step[], step: Step, kind: ProductKind, kinds: Map<string, ProductKind>): Step[] {
  const rank = KIND_ORDER[kind];
  const idx = steps.findIndex((s) => KIND_ORDER[kinds.get(s.productId) ?? 'other'] > rank);
  if (idx === -1) return [...steps, step];
  return [...steps.slice(0, idx), step, ...steps.slice(idx)];
}

export type TemplateKey = 'derm' | 'cycling' | 'retinoid' | 'simple';

export const TEMPLATES: { key: TemplateKey; title: string; sub: string }[] = [
  { key: 'derm', title: 'My dermatologist’s routine', sub: 'Start empty and add what you were given' },
  { key: 'retinoid', title: 'Starting a retinoid', sub: 'Tretinoin or adapalene, easing in. Adjust the weeks to your plan' },
  { key: 'simple', title: 'Just the basics', sub: 'Cleanse, moisturize, sunscreen' },
  { key: 'cycling', title: 'Skin cycling', sub: 'Popular 4-night routine. Not for prescription plans' },
];

/** Build products + plan for a template. */
export function applyTemplate(state: AppState, key: TemplateKey, today: ISODate): AppState {
  const products: Product[] = [];
  const add = (qk: string, override?: Partial<QuickProduct>) => {
    const q = { ...QUICK_PRODUCTS.find((x) => x.key === qk)!, ...override };
    const p = makeProduct(q, today);
    products.push(p);
    return { p, q };
  };
  const am: SlotPlan = emptySlot(state.plan.am.time, today);
  const pm: SlotPlan = emptySlot(state.plan.pm.time, today);

  if (key === 'derm') {
    return { ...state, products: [], plan: { ...state.plan, am, pm, createdAt: today } };
  }

  const cleanser = add('cleanser');
  const moist = add('moisturizer');
  const spf = add('spf');
  am.steps = [makeStep(cleanser.p.id, cleanser.q), makeStep(moist.p.id, moist.q), makeStep(spf.p.id, spf.q)];

  if (key === 'simple') {
    pm.steps = [makeStep(cleanser.p.id, cleanser.q), makeStep(moist.p.id, moist.q)];
  } else if (key === 'retinoid') {
    const ret = add('tretinoin');
    pm.steps = [
      makeStep(cleanser.p.id, { ...cleanser.q, waitMin: 20 }),
      makeStep(ret.p.id, ret.q),
      makeStep(moist.p.id, moist.q),
    ];
    pm.length = 1;
    pm.easeIn = { start: today, phases: EASE_IN_PHASES };
  } else if (key === 'cycling') {
    const ex = add('exfoliant');
    const ret = add('retinol');
    pm.length = 4;
    pm.steps = [
      makeStep(cleanser.p.id, cleanser.q),
      { ...makeStep(ex.p.id, ex.q), on: { type: 'nights', nights: [0] } },
      { ...makeStep(ret.p.id, ret.q), on: { type: 'nights', nights: [1] } },
      makeStep(moist.p.id, moist.q),
    ];
  }
  return { ...state, products, plan: { ...state.plan, am, pm, createdAt: today } };
}

/** Weeks 1–2: every 3rd night. Weeks 3–4: every other night. Then the full plan. */
export const EASE_IN_PHASES = [
  { days: 14, extraRest: 2 },
  { days: 14, extraRest: 1 },
];
