import { describe, expect, it } from 'vitest';
import { buildReminders } from '../../src/lib/reminders';
import { applyTemplate, blankState } from '../../src/lib/presets';

const START = '2026-10-05';

describe('buildReminders', () => {
  it('builds morning + evening + nudges for two weeks, skipping the past', () => {
    const s = { ...applyTemplate(blankState(START), 'cycling', START), onboarded: true };
    const now = new Date(2026, 9, 5, 12, 0); // noon on day 1
    const r = buildReminders(s, now);
    const first = r.filter((x) => x.date === START);
    // Morning at 08:00 has passed (and its nudge at 08:45), evening + nudge remain.
    expect(first.map((x) => x.kind)).toEqual(['main', 'nudge']);
    expect(first[0].title).toBe('Tonight: Exfoliation night');
    expect(first[0].body).toContain('Exfoliant (AHA/BHA)');
    expect(r.filter((x) => x.kind === 'main').length).toBe(14 + 13);
    expect(r.every((x) => x.fireAt > now.getTime())).toBe(true);
  });

  it('drops the evening reminders once tonight is logged', () => {
    const s = { ...applyTemplate(blankState(START), 'cycling', START), onboarded: true };
    s.log = [{ date: START, slot: 'pm', status: 'done', at: 0 }];
    const r = buildReminders(s, new Date(2026, 9, 5, 21, 0));
    expect(r.some((x) => x.date === START && x.slot === 'pm')).toBe(false);
    // Tomorrow is the retinoid night.
    expect(r.find((x) => x.date === '2026-10-06' && x.slot === 'pm' && x.kind === 'main')?.title).toBe('Tonight: Retinoid night');
  });

  it('marks photo nights and the follow-up eve', () => {
    const s = { ...applyTemplate(blankState(START), 'simple', START), onboarded: true };
    s.settings.photoDay = 0; // Sunday
    s.plan.followUp = { date: '2026-10-12', with: 'Dr. Jonaitis' };
    s.questions = [{ id: 'q', text: 'Can I use vitamin C?', at: 0 }];
    const r = buildReminders(s, new Date(2026, 9, 5, 12, 0));
    expect(r.find((x) => x.id === '2026-10-11:pm:main')?.title).toBe('Tonight: Recovery night · photo night');
    const fu = r.find((x) => x.kind === 'followup');
    expect(fu?.title).toBe('Dr. Jonaitis tomorrow');
    expect(fu?.body).toContain('1 question');
    expect(new Date(fu!.fireAt).getDate()).toBe(11);
  });
});
