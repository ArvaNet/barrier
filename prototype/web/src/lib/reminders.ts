// Builds the upcoming notifications from the plan. The server only stores and
// sends these; all routine logic stays on the phone.

import type { ReminderIn } from '../../shared/api';
import { addDays, atTime, routineToday, weekday } from './dates';
import { timeline, type Instance } from './engine';
import type { AppState, Slot } from './types';

export const HORIZON_DAYS = 14;

function stepNames(inst: Instance, max = 4): string {
  const names = inst.steps.map((s) => s.product.name);
  if (names.length === 0) return '';
  const shown = names.slice(0, max).join(' → ');
  return names.length > max ? `${shown} +${names.length - max}` : shown;
}

function activeLine(inst: Instance): string {
  const a = inst.steps.find((s) => s.active);
  if (!a) return '';
  return a.step.amount ? `${a.product.name}: ${a.step.amount.toLowerCase()}` : a.product.name;
}

export function mainCopy(inst: Instance, photoNight: boolean): { title: string; body: string } {
  const slot = inst.slot;
  if (inst.rest === 'pause') {
    return {
      title: slot === 'pm' ? 'Simple night' : 'Simple morning',
      body: slot === 'pm' ? 'Plan paused. Just cleanse and moisturize.' : 'Plan paused. Keep the basics going.',
    };
  }
  const photo = photoNight ? ' · photo night' : '';
  if (slot === 'pm') {
    const title = `Tonight: ${inst.label}${photo}`;
    if (inst.hasActives) {
      const line = activeLine(inst);
      return { title, body: line ? `${line}. Tap to start.` : `${stepNames(inst)}. Tap to start.` };
    }
    return { title, body: `${stepNames(inst) || 'Cleanse and moisturize'}. No actives tonight.` };
  }
  return { title: inst.label === 'Morning routine' ? 'Morning routine' : `This morning: ${inst.label}`, body: stepNames(inst) || 'Open Barrier for your steps.' };
}

function nudgeCopy(inst: Instance): { title: string; body: string } {
  if (inst.slot === 'am') return { title: 'Morning routine still open', body: 'Two minutes now saves the whole day. Sunscreen last.' };
  const n = inst.steps.length;
  const waits = inst.steps.reduce((m, s) => m + (s.step.waitMin ?? 0), 0);
  const time = waits > 0 ? `, about ${waits + n * 2} min` : '';
  if (inst.hasActives) return { title: `Still on for ${inst.label.toLowerCase()}?`, body: `${n} steps${time}. If tonight's not happening, tap and mark it skipped.` };
  return { title: 'Quick one tonight', body: 'Recovery night: cleanse, moisturize, sleep.' };
}

const GENERIC = {
  pm: { title: 'Evening routine time', body: 'Open Barrier to see tonight’s steps.' },
  am: { title: 'Morning routine time', body: 'Open Barrier to see this morning’s steps.' },
};

export function buildReminders(state: AppState, now: Date = new Date()): ReminderIn[] {
  const today = routineToday(now);
  const end = addDays(today, HORIZON_DAYS - 1);
  const out: ReminderIn[] = [];
  const t = now.getTime();
  const { settings } = state;

  for (const slot of ['am', 'pm'] as Slot[]) {
    const sp = state.plan[slot];
    if (!sp.enabled || sp.steps.length === 0) continue;
    for (const inst of timeline(state, slot, today, end, today)) {
      if (inst.status === 'done' || inst.status === 'skipped' || inst.status === 'off') continue;
      if (inst.steps.length === 0) continue;
      const fire = atTime(inst.date, sp.time).getTime();
      const url = `/ritual/${slot}?date=${inst.date}`;
      const base = { slot, date: inst.date, url };
      const photoNight = slot === 'pm' && settings.photoDay >= 0 && weekday(inst.date) === settings.photoDay;
      if (fire > t) {
        const c = mainCopy(inst, photoNight);
        out.push({
          ...base, id: `${inst.date}:${slot}:main`, fireAt: fire, kind: 'main', title: c.title, body: c.body,
          genericTitle: GENERIC[slot].title, genericBody: GENERIC[slot].body,
        });
      }
      if (settings.nudge && inst.rest !== 'pause') {
        const nudgeAt = fire + settings.nudgeAfterMin * 60_000;
        if (nudgeAt > t) {
          const c = nudgeCopy(inst);
          out.push({
            ...base, id: `${inst.date}:${slot}:nudge`, fireAt: nudgeAt, kind: 'nudge', title: c.title, body: c.body,
            genericTitle: GENERIC[slot].title, genericBody: GENERIC[slot].body,
          });
        }
      }
    }
  }

  // Midday sunscreen top-up, only when the morning includes sunscreen.
  const hasSpf = state.plan.am.enabled && state.plan.am.steps.some((s) => state.products.find((p) => p.id === s.productId)?.kind === 'spf');
  if (settings.spfMidday && hasSpf) {
    for (let i = 0; i < HORIZON_DAYS; i++) {
      const d = addDays(today, i);
      const fire = atTime(d, settings.spfTime).getTime();
      if (fire <= t) continue;
      out.push({
        id: `${d}:spf`, fireAt: fire, kind: 'spf', date: d, url: '/',
        title: 'Sunscreen top-up', body: 'Outside today? Reapply every 2 hours, and after sweating or swimming.',
      });
    }
  }

  // Dermatologist follow-up: the evening before.
  const fu = state.plan.followUp;
  if (fu) {
    const fire = atTime(addDays(fu.date, -1), '18:00').getTime();
    const open = state.questions.filter((q) => !q.answered).length;
    if (fire > t) {
      out.push({
        id: `${fu.date}:followup`, fireAt: fire, kind: 'followup', date: fu.date, url: '/report',
        title: `${fu.with || 'Dermatologist'} tomorrow`,
        body: open > 0 ? `Your report is ready, with ${open} question${open === 1 ? '' : 's'} to ask.` : 'Your report is ready to show. Add any questions tonight.',
      });
    }
  }

  return out.sort((a, b) => a.fireAt - b.fireAt).slice(0, 200);
}
