import { describe, expect, it } from 'vitest';
import { addDays } from '../../src/lib/dates';
import {
  describeOn, instanceOn, needsReconcile, nextOf, productMap, rings, setEvery, stats, timeline,
} from '../../src/lib/engine';
import { applyTemplate, blankState, makeProduct, makeStep } from '../../src/lib/presets';
import type { AppState, Entry } from '../../src/lib/types';

const START = '2026-10-05'; // a Monday

function cycling(): AppState {
  return { ...applyTemplate(blankState(START), 'cycling', START), onboarded: true };
}

function done(date: string, slot: 'am' | 'pm' = 'pm', extra: Partial<Entry> = {}): Entry {
  return { date, slot, status: 'done', at: 0, ...extra };
}

const labels = (s: AppState, from: string, to: string, today: string) =>
  timeline(s, 'pm', from, to, today).map((i) => i.label);

describe('skin cycling rotation', () => {
  it('projects the 4-night cycle from the first night', () => {
    const s = cycling();
    expect(labels(s, START, addDays(START, 5), START)).toEqual([
      'Exfoliation night', 'Retinoid night', 'Recovery night', 'Recovery night', 'Exfoliation night', 'Retinoid night',
    ]);
    const hues = timeline(s, 'pm', START, addDays(START, 3), START).map((i) => i.hue);
    expect(hues).toEqual(['gold', 'clay', 'sage', 'mist']);
  });

  it('a skipped retinoid night repeats the next night (never skips ahead)', () => {
    const s = cycling();
    s.log = [done('2026-10-05'), { date: '2026-10-06', slot: 'pm', status: 'skipped', at: 0 }];
    expect(instanceOn(s, 'pm', '2026-10-07', '2026-10-07').label).toBe('Retinoid night');
  });

  it('an unlogged active night holds, an unlogged recovery night still advances', () => {
    const s = cycling();
    // Night 1 (exfoliation) never logged → tonight is still exfoliation.
    expect(instanceOn(s, 'pm', '2026-10-06', '2026-10-06').label).toBe('Exfoliation night');
    // Exfoliation + retinoid done, recovery night 3 unlogged → night 4 recovery advances anyway.
    s.log = [done('2026-10-05'), done('2026-10-06')];
    const tl = timeline(s, 'pm', '2026-10-07', '2026-10-09', '2026-10-09');
    expect(tl.map((i) => i.label)).toEqual(['Recovery night', 'Recovery night', 'Exfoliation night']);
  });

  it('an irritation recovery night drops actives and holds the rotation', () => {
    const s = cycling();
    s.log = [done('2026-10-05'), { date: '2026-10-06', slot: 'pm', status: 'done', recovery: true, at: 0 }];
    const tonight = instanceOn(s, 'pm', '2026-10-06', '2026-10-06');
    expect(tonight.label).toBe('Recovery night');
    expect(tonight.rest).toBe('inserted');
    expect(tonight.steps.some((x) => x.active)).toBe(false);
    expect(instanceOn(s, 'pm', '2026-10-07', '2026-10-07').label).toBe('Retinoid night');
  });

  it('a pause makes simple nights and resumes where it left off', () => {
    const s = cycling();
    s.log = [done('2026-10-05')];
    s.pauses = [{ id: 'p', from: '2026-10-06', to: '2026-10-08', reason: 'travel' }];
    const tl = timeline(s, 'pm', '2026-10-06', '2026-10-09', '2026-10-06');
    expect(tl.map((i) => i.label)).toEqual(['Simple night', 'Simple night', 'Simple night', 'Retinoid night']);
    expect(tl[0].steps.map((x) => x.product.kind)).toEqual(['cleanser', 'moisturizer']);
  });

  it('projects the future assuming each night happens', () => {
    const s = cycling();
    const next = nextOf(s, 'pm', START, (x) => x.product.kind === 'exfoliant');
    expect(next?.date).toBe('2026-10-09');
  });
});

describe('retinoid ease-in', () => {
  it('every 3rd night for 2 weeks, every other night for 2 weeks, then nightly', () => {
    const s = { ...applyTemplate(blankState(START), 'retinoid', START), onboarded: true };
    // Log every night as done so the rotation advances daily.
    const days = Array.from({ length: 34 }, (_, i) => addDays(START, i));
    s.log = days.map((d) => done(d));
    const today = addDays(START, 40);
    const tl = timeline(s, 'pm', START, addDays(START, 33), today);
    const ret = tl.map((i) => (i.steps.some((x) => x.product.kind === 'retinoid') ? 'R' : '.')).join('');
    expect(ret.slice(0, 14)).toBe('R..R..R..R..R.');
    expect(ret.slice(14, 28)).toBe('R.R.R.R.R.R.R.');
    expect(ret.slice(28)).toBe('RRRRRR');
    expect(tl[0].easing).toBe(true);
    expect(tl[30].easing).toBe(false);
  });
});

describe('reconcile', () => {
  it('asks about last night when it had actives and nothing was logged', () => {
    const s = cycling();
    s.log = [done('2026-10-05')];
    const r = needsReconcile(s, '2026-10-07');
    expect(r.map((i) => [i.date, i.label])).toEqual([['2026-10-06', 'Retinoid night']]);
  });

  it('does not ask about recovery nights', () => {
    const s = cycling();
    s.log = [done('2026-10-05'), done('2026-10-06')];
    expect(needsReconcile(s, '2026-10-09')).toEqual([]);
  });
});

describe('editing', () => {
  it('every other night tretinoin + azelaic on the other nights', () => {
    let s = blankState(START);
    const clean = makeProduct({ name: 'Cleanser', kind: 'cleanser' }, START);
    const tret = makeProduct({ name: 'Tretinoin 0.025%', kind: 'retinoid' }, START);
    const aze = makeProduct({ name: 'Azelaic acid 15%', kind: 'treatment' }, START);
    s.products = [clean, tret, aze];
    const st = [makeStep(clean.id, {}), makeStep(tret.id, {}), makeStep(aze.id, {})];
    s.plan.pm.steps = st;
    const pm = productMap(s.products);
    let plan = setEvery(s.plan.pm, st[1].id, 2, pm);
    plan = setEvery(plan, st[2].id, 2, pm);
    s = { ...s, plan: { ...s.plan, pm: plan }, onboarded: true };
    expect(plan.length).toBe(2);
    expect(labels(s, START, addDays(START, 3), START)).toEqual([
      'Retinoid night', 'Azelaic acid night', 'Retinoid night', 'Azelaic acid night',
    ]);
    expect(describeOn(plan.steps[1], plan)).toBe('Every other night');
  });

  it('weekday steps follow the calendar, product windows are respected', () => {
    const s = blankState(START);
    const clean = makeProduct({ name: 'Cleanser', kind: 'cleanser' }, START);
    const ex = makeProduct({ name: 'BHA', kind: 'exfoliant' }, START);
    const pill = { ...makeProduct({ name: 'Doxycycline', kind: 'oral' }, START), until: '2026-10-07' };
    s.products = [clean, ex, pill];
    s.plan.pm.steps = [
      makeStep(clean.id, {}),
      { ...makeStep(ex.id, {}), on: { type: 'weekdays', days: [2, 6] } }, // Tue, Sat
      makeStep(pill.id, {}),
    ];
    const tl = timeline(s, 'pm', START, addDays(START, 6), START);
    expect(tl.map((i) => i.label)).toEqual([
      'Recovery night', 'Exfoliation night', 'Recovery night', 'Recovery night', 'Recovery night', 'Exfoliation night', 'Recovery night',
    ]);
    expect(tl[2].lastDayOf.map((p) => p.name)).toEqual(['Doxycycline']);
    expect(tl[3].steps.some((x) => x.product.name === 'Doxycycline')).toBe(false);
  });
});

describe('stats & rings', () => {
  it('counts nights and builds a ring per cycle', () => {
    const s = cycling();
    s.log = ['2026-10-05', '2026-10-06', '2026-10-07', '2026-10-08', '2026-10-09'].map((d) => done(d, 'pm', { label: 'x' }));
    const st = stats(s, '2026-10-09');
    expect(st.nightsDone).toBe(5);
    const r = rings(s, '2026-10-09');
    expect(r.length).toBe(2);
    expect(r[0].segments.length).toBe(4);
    expect(r[0].segments.every((x) => x.done)).toBe(true);
  });
});
