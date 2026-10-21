# Barrier v1 (native iPhone app): build checklist

Finish line: Barrier compiles, passes tests, and every screen has been
screenshot-checked on the iOS Simulator in CI, ready for the founder to run on
their iPhone from Xcode.

- [x] Fact-check the guidance (docs/derm-facts.md)
- [x] Core package: models, schedule engine, reminders, guidance, milestones, recap (37 tests, Linux + macOS)
- [x] App: model, storage (App Group), notifications with actions, background refresh
- [x] Screens: onboarding, Today, ritual, routine editor, progress, camera, compare, derm, report PDF, settings
- [x] Widget (home + Lock Screen, Done button), Live Activity timer, Siri intents
- [x] App icon, asset catalog, privacy manifest
- [x] CI: core tests, simulator build, 15 screenshots with demo data, hang sampler
- [x] Green CI build, zero warnings
- [x] Screenshot review + polish (Progress hang, finish layout, tints, status bar, copy)
- [x] Review 1 (docs/review-1.md): 9 blockers + 6 should-fix, all fixed with regression tests
- [x] Review 2 on the fixes (docs/review-2.md): 4 blockers + 6 should-fix, all fixed
- [x] Generated Barrier.xcodeproj committed; CI warns when stale
- [x] Vault status + decision log updated

## On the founder's Mac (not doable from Windows)
- [ ] Set Team on both targets, run on iPhone (README → Run it on your iPhone)
- [ ] Enter the real dermatologist routine; send a test reminder; take the "before" photo
- [x] Check once with 2+ photos that the report's photo page renders (done in CI with demo photos, screenshot 20)

# Body routine (back, chest, body treatments)

Finish line: a third routine ("Body", user-named, e.g. "Back") with its own time or
"after shower" cue, reminders with Done, Today row, guided routine, log, back photos
(rear camera + self-timer), face/back check-ins, report section. Tested, green CI with
screenshots, pushed.

- [x] Core: Slot.body, Plan.body (old saves still load), SlotPlan name/cue, Area on photos + check-ins
- [x] Core: engine labels, reconcile, stats, reminders, recap, presets, demo data + tests
- [x] App: Today row, ritual, routine editor (third segment), onboarding page
- [x] App: camera face/back (rear camera, self-timer), photo areas, compare same-area
- [x] App: skin check-in face/back, progress dots + counts, report section
- [x] Notifications: body category (Skip today), intent case, widget unaffected
- [x] Fact-checked body tips (docs/body-facts.md)
- [x] CI green + screenshots reviewed, review pass (docs/review-3.md, all fixed), pushed, vault note

# Procedures (subcision, laser, peels, microneedling, injections)

Finish line: procedures logged, reminded, paired with before/after photos, linked to
actives breaks, shown on Today, Calendar, Derm and the report. Tested, green CI with
screenshots, reviewed, pushed.

- [x] Fact-check aftercare wording (docs/procedure-facts.md)
- [x] Core: Procedure model (old saves still load), quick names, upcoming/recent, before/after pick
- [x] Core: linked actives break (pause), day-before reminder, recovery-day notes, photo prompts + tests (72 tests)
- [x] App: Derm section (upcoming + past), add/edit sheet, before/after compare
- [x] App: Today card (upcoming, days after, photo nudge), calendar marker, day detail
- [x] App: report "Procedures and photos" page, demo data, CI screenshots
- [x] CI green + screenshots reviewed, review pass (docs/review-4.md, all fixed), pushed, vault note

# Timeline, change log, skin score (for the dermatologist)

Finish line: the report opens with a one-glance timeline (use per day, skin, weekly score,
changes, procedures, photos, breaks), a dated list of routine changes, and a weekly one-tap
skin score; the same timeline in Progress; a sample report to show the dermatologist.
Tested, green CI with screenshots, reviewed, pushed.

- [x] Core: plan snapshots + change list (coalesced per day), weekly score, timeline data + tests
- [x] App: weekly score card on Today, routine history in Routine, timeline card in Progress
- [x] Report: page 1 "at a glance" (timeline, how it went, changes, questions), page 2 routine + skin log, page 3 procedures + photos
- [x] Sample report (demo data) from the Derm tab, demo history + scores, CI screenshots
- [x] CI green + screenshots reviewed, review pass (docs/review-5.md, all fixed), pushed, vault note

# Design pass (Apple HIG, "impress")

Finish line: every screen and sheet (light and dusk) screenshot-reviewed against a written
spec (docs/design-spec.md: type scale, spacing grid, radii, page headers, card anatomy,
buttons, empty states, dark mode, alignment); every issue found fixed; an independent
design critique (docs/design-review.md) fixed; before/after screenshots compared; CI green; pushed.

- [x] Screenshot coverage for every sheet and state (editor, add product, day detail, not tonight, pause, procedure new, onboarding pages, camera, dusk variants)
- [x] Design spec written from what's there + HIG (docs/design-spec.md)
- [x] Independent design critique of all screenshots (docs/design-review.md)
- [x] Phase 1, one system: brand surfaces on lists and sheets, 16 pt line, ink tint (clay only for the primary action and treatment), type tokens, dusk contrast, halos not glows, icons, native chrome
- [x] Phase 2, defects: clipping, overprint, ritual progress, chip heights, list cut-off, dev copy, gaps, truncation, button mismatch, separators, 44 pt targets, one card anatomy
- [x] Phase 3, screens: Today (6 cards max, "Also today", one check-in, one "for you"), ritual focus layout, Progress order + rings hero, Derm report hero, report preview, onboarding
- [x] Phase 4, impress: Tonight done moment, bedtime dim, finish with tomorrow, welcome orbit with motion, day-one states
- [x] Review of all 42 after-shots: dusk button contrast (fill token), stats label collision, day-one rings + report, report preview fade, separators, Settings action icons, onboarding bottom fade, done checkmark on the orbit
- [x] CI green, before/after reviewed, pushed, vault note

# Fill in the weeks before Barrier (2026-10-21)

Finish line: someone who followed the routine on paper can say since when and tap the days they
missed; those weeks show in rings, calendar, timeline and report (marked as filled in afterwards);
tonight doesn't change; skin notes can be added for any past day; core tests; CI green.

- [x] Core: `fillIn(since:missed:today:)` moves the start, ease-in and treatment start dates, replays the rotation so tonight stays, marks entries `filledIn` (FillIn.swift, 9 tests)
- [x] "Before Barrier" sheet: date + a calendar per routine, tap to mark missed, Undo on the toast
- [x] Ways in: Progress card (first four weeks), Routine tab row
- [x] Day detail: skin chips for any day up to today
- [x] Report: "Oct 1–Oct 20 filled in afterwards by the patient."
- [x] CI green, screenshots 43-45 checked (evening first in the picker; report "Now" line notes the ease-in)
