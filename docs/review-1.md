# Review 1: merge-blocking problems

Scope: BarrierCore (engine, reminders, mutations), Shared (store, intents), app (AppModel,
NotificationService, Services), every screen, widget and Live Activity. Only real bugs a user
would hit. Each item was traced through the actual code path. No source files were changed.

Ranked by severity. Items 1–9 block release. Items 10–15 should be fixed but don't block.

---

## Blockers

### 1. Siri "Mark my Barrier routine done" always logs the evening routine, even in the morning
- `Shared/Intents.swift:31` `@Parameter(title: "Routine", default: .evening)`, used at `:42`.
- `Barrier/App/BarrierApp.swift:43` registers the shortcut as `MarkRoutineDoneIntent()`, so the default is used.
- `RoutineChoice.now` (`Intents.swift:19`) was written for this case but nothing calls it.
- Scenario: at 8 a.m. the user says "I did my Barrier routine". Tonight's PM gets logged as done.
  Tonight's reminder and nudge are cancelled (`:48`), the rotation advances past tonight's
  retinoid, and the morning stays open.
- Fix: make the parameter optional with no default
  (`@Parameter(title: "Routine") var routine: RoutineChoice?`) and use
  `let slot = (routine ?? .now).slot`. The widget already passes an explicit routine.

### 2. If the state fails to load, the app saves a blank state over the user's whole history
- `Barrier/App/AppModel.swift:63` `state = SharedStore.loadState() ?? Presets.blankState(...)`.
- `Shared/SharedStore.swift:37` returns nil for any read or decode error.
- `Barrier/App/BarrierApp.swift:29-30` calls `saveNow()` every time the app goes to the background.
- Scenario: state.json can't be decoded or read (see item 5 for a concrete trigger, plus any
  future schema change or restore across versions). The app opens onboarding, and the first trip
  to the background overwrites state.json with the blank state. Routine, log, check-ins and photo
  metadata are all gone. The photo files are orphaned.
- Related: `Models.swift:409-417` decodes each array with `(try? …) ?? []`, so one bad `Entry`
  wipes the entire log on the next save.
- Fix: tell "no file" apart from "file exists but failed". On failure, copy the file to
  `state.corrupt-<timestamp>.json` and refuse to save over it, for example with a `loadFailed`
  flag that `saveNow()` checks. Better still, decode arrays element by element and drop only the
  bad elements.

### 3. Plan edits that don't rebase replay old history with the new plan, so tonight jumps
Most structural edits re-anchor (`rebase`): length, ease-in toggle, extra-rest, frequency, add
product. These don't:
- Removing a step: `Barrier/Screens/Routine/RoutineView.swift:117-121` (swipe) and
  `Barrier/Screens/Routine/StepEditorSheet.swift:115-119` (Remove button).
- Changing a product's type, start date or end date: `StepEditorSheet.swift:172` rebases only
  when `on` changed.
- Ease-in start date, phase length, and adding or removing a phase:
  `RoutineView.swift:285, 294, 300, 326`.

Scenario (verified against `Engine.timeline`):
- Setup: 2-night rotation with tretinoin on night 1 and azelaic acid on night 2. Log: tretinoin
  done, azelaic skipped (the rotation holds), azelaic done. Tonight is correctly "Retinoid night".
- The dermatologist stops azelaic, and the user swipes it away.
- The replay now treats the skipped night as a rest night that advances. It counts the logged
  azelaic night as a tretinoin night, and tonight flips to "Recovery night". The last real
  tretinoin was 3 nights ago.
- Unanswered "Did it happen?" questions can also flip.

Fix: capture `let tonight = model.instance(slot)` before each of these edits and call
`s.rebase(slot, today: model.today, keeping: tonight)` inside the same `update`. In
`StepEditorSheet.save`, always rebase.

### 4. "Not tonight" from the Lock Screen doesn't reliably update the next reminders, so tomorrow's reminder names the wrong night
- `Barrier/App/NotificationService.swift:136-146`: the skip (and done) action updates state, but
  rescheduling only happens through `scheduleNotifications()`, which first sleeps 1 s
  (`AppModel.swift:127-128`) in a Task.
- When the action launches or wakes the app in the background, iOS may suspend it as soon as
  `didReceive` returns, so the reschedule isn't guaranteed to run. If it starts and gets
  suspended, it has already removed every pending request (`NotificationService.swift:45-46`)
  and only some are re-added.
- Scenario: Retinoid night → the user taps "Not tonight" on the Lock Screen. The engine now holds
  the retinoid for tomorrow. Tomorrow's pending reminder was planned assuming tonight happened,
  so it still says "Tonight: Recovery night · No actives tonight". The user skips the retinoid
  again. Tapping Done on that reminder logs the Retinoid night as done
  (`markDone(slot, on:day,…)` computes from state), and the rotation moves on without the
  retinoid ever being applied.
- Fix: at the end of both action cases, `await NotificationService.shared.reschedule(model.state)`
  (call it directly, no debounce). The async delegate keeps the app alive until it returns.
- Note: the same stale copy appears when an active night is simply never logged and the app isn't
  opened. Consider generic copy for +1/+2 days whenever tonight has actives and isn't logged yet.

### 5. Day math assumes the Gregorian calendar but reads `Calendar.current`
- `Packages/BarrierCore/Sources/BarrierCore/Day.swift:103-118` (`Day.of`, `routineDay`,
  `Day.date`) and `:181` (`DayTime.date`) take year, month and day from `Calendar.current`.
  `ordinal`, `weekday`, `adding`, `daysInMonth` and `Day(iso:)` are proleptic-Gregorian.
- Thai iPhones default to the Buddhist calendar, so today is `Day(2569,10,9)`. `weekday` then
  says Monday when it's Friday (3 days off). Weekday steps (e.g. exfoliant Tue/Sat), the photo
  night, the Monday recap and the week strip all land on the wrong days. In leap years, 29 Feb and
  1 Mar get the same ordinal.
- Islamic, Persian and Hebrew calendars have different month lengths, so days collide or get
  skipped. Hebrew Elul is month 13, which fails `Day(iso:)` (`Day.swift:19`) on the next launch →
  item 2 wipes the data.
- Fix: one shared Gregorian calendar
  (`Calendar(identifier: .gregorian)` with `timeZone = .current`) as the default for every
  `calendar:` parameter in `Day.swift`, and for `Reminders.plan` (`Reminders.swift:80`) and
  `NotificationService.swift:47` where it computes `fire.date(calendar:)`. Trigger components can
  stay as they are, built from the absolute Date.

### 6. "Start over from a template" resets `createdAt`, which hides all history and breaks the report
- `Barrier/Screens/Routine/RoutineView.swift:56-61` calls `Presets.apply`, which sets
  `s.plan.createdAt = today` (`Presets.swift:148`). The footer promises "Your history and photos
  stay."
- Effects:
  - Progress rings start from today ("Your first ring starts tonight").
  - The calendar drops every dot before today (`ProgressScreen.swift:91`).
  - The week strip blanks past days.
  - The 4-week stats restart and Monday recaps stop.
  - The PDF for the dermatologist prints "45 of 0 evenings done since Oct 9"
    (`ReportView.swift:187`: all-time `nightsDone` against `nightsDue` counted from `createdAt`).
- Fix: in the RoutineView action, keep `createdAt` the way it already keeps the times:
  `let created = s.plan.createdAt … s.plan.createdAt = created`.

### 7. Adding an "every Nth" step can silently break an existing prescription pattern (rotation capped at 8)
- `Packages/BarrierCore/Sources/BarrierCore/Engine.swift:413`
  `resize(plan, to: min(want, 8))`.
- Scenario: tretinoin is set to "Every 3rd night" (length 3). The user adds the
  "Exfoliant (AHA/BHA)" quick product, whose `every` is 4. `lcm` = 12 is capped to 8, so
  tretinoin becomes nights 0, 3, 6 of 8. Two retinoid nights now sit 2 apart at every wrap, and
  the user never touched the tretinoin. The same happens with every-4th on a 3-night rotation, or
  every-3rd on a 4-night one.
- Fix: raise the cap to 12 (and the length stepper at `RoutineView.swift:156` to `1...12`). If
  `lcm` still exceeds the cap, don't resize: leave the other steps alone and tell the user the
  combination doesn't fit.

### 8. The wait timer, its Live Activity and its notification outlive the routine
- `TimerActivity.end()` and `cancelTimer()` are only called inside `RitualView`. `close()` during
  a wait keeps both on purpose (`RitualView.swift:250-257`).
- Scenario: Start → cleanser → 20-min wait → close the ritual → tap Done on Today (or in the
  widget, a notification or Siri).
  - The Lock Screen keeps a "0:00 · Skin should be completely dry · Next: Tretinoin" activity
    for hours, until iOS ends it.
  - "Time for Tretinoin, your 20-minute wait is over" fires after the night is logged.
  - `RitualMemory` keeps the stale wait, so the widget's ritual link reopens it.
  - Killing the app mid-wait also orphans the activity.
- Fix: in `AppModel.markDone` and `markSkipped` (and after `ingestInbox`), end the activity,
  cancel the timer and clear `RitualMemory.shared.progress[id]`. In `becameActive`, end any
  activity whose `endsAt` has passed when no ritual is on screen.

### 9. Done from the widget or Siri doesn't stop a snoozed reminder
- `Shared/Intents.swift:48` removes only `…:main` and `…:nudge`. `AppModel.ingestInbox`
  (`AppModel.swift:89-94`) never calls `clearDelivered`, and `reschedule` deliberately keeps
  `snooze:` requests (`NotificationService.swift:45`).
- Scenario: the user taps "In 30 minutes", does the routine, then taps Done in the widget.
  30 minutes later the reminder fires again, and the delivered banners stay in Notification
  Center. This breaks the README promise that reminders stop once you're done.
- Fix: add `"snooze:\(today.iso):\(slot.rawValue)"` to the ids in the intent. In `ingestInbox`,
  call `NotificationService.shared.clearDelivered(day:slot:)` for each applied `.done` item.

---

## Should fix (not blocking)

### 10. Skin check-in collapses after the first tap
- `Barrier/Screens/Today/TodayCards.swift:114-122`: chips show only while `existing == nil || editing`.
- The first tap creates the check-in and hides the chips, so picking "Dry + Flaky" needs an extra
  Edit tap. It reads as single-select.
- Fix: set `editing = true` when the first chip creates the check-in.

### 11. History before the anchor is misread after any plan edit
- Pre-anchor instances have `steps: []` and `pos: e?.pos ?? 0` (`Engine.swift:209`).
- Recap counts only nights with steps (`Recap.swift:53`). After a Monday-morning edit, last
  week's recap says "A quiet week".
- Skin-cycling rings start a new ring on every unlogged pre-anchor day (`Engine.swift:357`).
- An unanswered "Did it happen?" for last night disappears on any edit and can't be logged from
  the day sheet (status `.off`).
- Fix:
  - Recap: count `i.entry != nil` too.
  - Rings: only treat a day as a ring boundary when it has an entry or is on or after the anchor.
  - Rebase: when last night still needs an answer, anchor on that night instead of today.

### 12. The compare slider and the camera ghost re-read full-size JPEGs from disk on every frame
- `ProgressScreen.swift:450-458` and `CameraScreen.swift:17-20` (`lastPhoto` is read 3 times per
  body).
- Dragging the compare handle or the ghost slider decodes 2048 px images on the main thread each
  frame, which makes the drag visibly janky.
- Fix: load the images once into `@State` in `.task`.

### 13. Onboarding: Back then Continue on the template page wipes what was entered
- `Barrier/Screens/Onboarding/OnboardingView.swift:121` re-applies the template on every
  Continue, which replaces products and steps added on the next pages.
- Fix: apply only when the selected template differs from the last applied one.

### 14. The inbox is deleted before the tap is saved
- `AppModel.swift:89-94`: `drainInbox()` removes inbox.json, and the state is saved 250 ms later
  by the debounce.
- In a background wake (Siri in the app process, background refresh), suspension or a kill in
  that window loses the widget or Siri tap.
- Fix: call `saveNow()` right after `update` in `ingestInbox`.

### 15. Restore freezes the app
- `SettingsView.swift:176-186` decodes, resizes and re-encodes every photo synchronously on the
  main thread. With a few dozen photos, the app is frozen for several seconds.
- Fix: write the backup's JPEG bytes straight to disk (no re-encode), off the main actor.

---

## Couldn't verify without a device
- The PDF photo page (`ReportView.swift`, `ReportPhotosPage`) uses `LazyVGrid` inside
  `ImageRenderer`. The CI demo data has no photos, so this page has never been rendered. Check
  once on the phone with 2+ photos. If it comes out empty, swap in plain HStacks, as the calendar
  already does.

## Checked and fine
- Engine advance/hold rules, ease-in phase resets, pause hold and recovery hold match the intended
  rules.
- `Engine.instance(...)[0]` always has an element.
- `Guidance.tip` can't get an empty pool (two tips need nothing).
- No division by zero in rings, orbit or report.
- Every sheet and cover gets the model environment.
- DST: fire times are built per day from components, and nudges add absolute minutes.
- 4 a.m. rollover math is consistent.
- The pending count stays ≤ 60 plus timer and snoozes.
- The notification delegate is set in `didFinishLaunching`, so background actions are delivered.
- The widget never writes state.json.
- `BGTaskSchedulerPermittedIdentifiers` matches the registered id.
