# Review 2: merge-blocking problems

Scope: the fixes in `fa38c0f..HEAD` (Packages, Shared, Barrier, BarrierWidget), checked against
`docs/review-1.md`, plus new bugs those changes introduced. Every item was traced through the code.
No source files were changed. There is no Swift toolchain on this machine, so nothing was run.
Anything that depends on iOS runtime behaviour is marked **(not device-verified)**.

Verdict: 12 of 15 fixed (one of them opened a new hole, B2), 3 partly fixed (#2, #5, #8). Four
blockers remain (B1–B4), each with a fix of a few lines. Then six should-fix items (S1–S6).

---

## Review-1 items

| # | Status | Notes |
|---|--------|-------|
| 1 Siri logs evening in the morning | FIXED | Optional parameter, `routine ?? .now`. Widget still passes an explicit routine. |
| 2 Load failure overwrites history | PARTLY | Save, schedule and inbox are all gated on `loadFailed`; Lossy arrays work. But the background refresh still plans reminders from the blank fallback state. See **B4**. |
| 3 Plan edits replay old history | FIXED, with a new hole | Every listed edit now goes through `editPlan`. But anchoring on an unanswered night can itself change tonight. See **B2**. |
| 4 Lock Screen "Not tonight" doesn't re-plan | FIXED | Both actions await `reschedule`. Later active nights get generic copy. Small residual race: see S5. |
| 5 Day math vs non-Gregorian calendars | PARTLY | Day math is Gregorian now, but notification triggers are now built from Gregorian components that iOS reads in the phone's calendar. See **B1**. |
| 6 "Start over" resets `createdAt` | FIXED | |
| 7 Every-Nth breaks another step (cap 8) | FIXED | Cap 12, refuses when it doesn't fit. The refusal alert has a typo: see S2. |
| 8 Wait timer outlives the routine | PARTLY | The reported scenario is fixed, but `endRitual` now stops *any* running wait, including one for a different routine. See **B3**. |
| 9 Widget/Siri Done doesn't stop a snooze | FIXED | Intent removes the snooze id and delivered banners. `ingestInbox` clears delivered. |
| 10 Skin check-in collapses | FIXED | |
| 11 History before the anchor misread | FIXED | Recap counts logged nights. Rings skip unknown pre-anchor days. The open question survives edits (but see B2). |
| 12 Compare/ghost re-decode JPEGs per frame | FIXED | Decoded once in `.task`. |
| 13 Onboarding Back/Continue wipes entries | FIXED | |
| 14 Inbox deleted before the tap is saved | FIXED | `saveNow()` right after `update`. |
| 15 Restore freezes the app | FIXED | Photo bytes written as-is, off the main actor. The backup JSON is still decoded on the main thread in the file importer callback (a few hundred ms for big backups). Fine. Interrupted restore: see S6. |

---

## Blockers

### B1. Reminders never fire on iPhones set to a non-Gregorian calendar (Thai Buddhist by default)
- `Barrier/App/NotificationService.swift:47,61-63`: `let cal = Calendar.barrier` (Gregorian), then
  `cal.dateComponents([.year, .month, .day, .hour, .minute], from: fireDate)`. The components carry
  no `calendar`, so `UNCalendarNotificationTrigger` reads them in the phone's current calendar
  **(not device-verified)**.
- Scenario: a Thai iPhone (Buddhist calendar is the default there). Tonight's reminder is planned for
  Gregorian 2026-10-09 21:30. The trigger reads year 2026 as Buddhist Era, which is 1483 CE, so it
  never fires. The same happens to every main, nudge, sunscreen, follow-up and keep-alive reminder.
  Japanese-calendar phones get Reiwa 2026 (far future). "Send a test reminder" uses a time-interval
  trigger, so it still works and hides the problem.
- Review 1 recommended Gregorian for the fire *date* and leaving the trigger components as they were.
  The fix switched both.
- Fix: make it `var comps = cal.dateComponents(...)` and add `comps.calendar = cal`. That pins the interpretation to the
  calendar the components were made in, whatever iOS defaults to.

### B2. Editing the plan while a "Did it happen?" question is open can change tonight
- `Packages/BarrierCore/Sources/BarrierCore/Mutations.swift:126-134` `editPlan` anchors on the
  earliest unanswered night (`pending.day`, `pending.pos`), so the nights between it and today are
  replayed **with the new plan**. When the edit changes whether those positions carry actives, the
  hold/advance pattern changes and tonight moves. That's the exact bug class #3 was about, now limited
  to a 2-day window.
- Scenario (traced through `Engine.timeline`):
  - Evening rotation of 3: night 1 tretinoin, night 2 azelaic acid, night 3 recovery.
  - Monday is a tretinoin night. The user forgets to log it, so the rotation holds.
  - Tuesday is tretinoin again. They do it and tap Done on the Lock Screen. Wednesday is correctly
    "Azelaic acid night", and Today asks "Monday: did it happen?".
  - Wednesday, the dermatologist stops tretinoin and the user removes it (swipe or Remove).
  - `editPlan` anchors at (Monday, night 1). Under the new plan Monday has no actives, so it advances.
    Tuesday's Done now counts as the azelaic night. Tonight flips to "Recovery night" and azelaic slides
    to Friday. In Progress, Tuesday shows as an azelaic night.
- Also reachable by changing the pending night's product type or start/end date.
- Fix: keep the pending anchor only when it reproduces tonight, otherwise anchor today:
  ```swift
  change(&self)
  let keep = max(0, min(tonight.pos, Engine.cycleLen(plan[slot], on: today) - 1))
  if let p = pending {
      plan[slot].anchor = Anchor(day: p.day, pos: max(0, min(p.pos, Engine.cycleLen(plan[slot], on: p.day) - 1)))
      if Engine.instance(self, slot: slot, on: today, today: today).pos == keep { return }
  }
  plan[slot].anchor = Anchor(day: today, pos: keep)
  ```
  (When it falls back, the question for that night goes away. That's acceptable: tonight matters more.)
- Checked: the anchor pos is always valid (clamped to the cycle length on that day), `pending` is
  always a post-anchor instance, and an edit that leaves the plan unchanged reproduces tonight exactly.

### B3. Logging any other routine kills a running wait timer
- `Barrier/App/AppModel.swift:221-227` `endRitual` skips only when *this* ritual is on screen.
  Otherwise it calls `TimerActivity.end()` (ends every Live Activity) and `cancelTimer()` (the single
  `timer` notification), whichever routine they belong to. It runs from `markDone`, `markSkipped`,
  `ingestInbox` and both notification actions.
- Scenario: 9 p.m., the user starts the evening routine. After the cleanser, the 20-minute "skin
  completely dry" wait starts and they close the ritual. While waiting they see the morning row on
  Today and tap Done to log the morning, or answer "Last night: did it happen? Yes". The Lock Screen
  countdown disappears and "Time for Tretinoin" never comes. Reopening the ritual still shows the wait
  (its progress was kept), so the user has no idea the ping is gone.
- Fix: only stop the wait if the routine being logged owns it.
  ```swift
  func endRitual(_ slot: Slot, _ day: Day) {
      let id = RitualRequest(slot: slot, day: day).id
      guard ritual?.id != id else { return }
      guard RitualMemory.shared.progress.removeValue(forKey: id)?.waitEnds != nil else { return }
      TimerActivity.end()
      NotificationService.shared.cancelTimer()
  }
  ```
  Orphans from a killed app are already handled by `endStale` in `becameActive`.

### B4. Background refresh still plans reminders from the blank fallback state
- `Barrier/App/Services.swift:134-144`: the BG task calls `refreshClock()` and `ingestInbox()` (gated),
  then `NotificationService.shared.reschedule(model.state)` directly. It doesn't go through
  `scheduleNotifications` (gated on `loadFailed`) and never calls `retryLoadIfNeeded()`.
- When `loadFailed` is true, `model.state` is the blank state with `onboarded == false`. So
  `Reminders.plan` returns `[]`, and `reschedule` removes every pending reminder and adds none.
- Scenario: iOS installs an update overnight and restarts the phone. The app is woken in the background
  before first unlock (the case the comment on `retryLoadIfNeeded` describes), so `AppModel.shared`
  starts with `loadFailed = true`. When the refresh runs, then or later in the same process after the
  user unlocks, all reminders are wiped. Every later refresh repeats it, because nothing in that path
  retries the load. Reminders stay silent until the user happens to open the app.
  **(Whether iOS runs BG refresh before first unlock wasn't verified. The "same process, after unlock"
  path doesn't depend on it.)**
- Fix:
  ```swift
  let model = AppModel.shared
  model.refreshClock()
  model.retryLoadIfNeeded()
  guard !model.loadFailed, model.state.onboarded else { task.setTaskCompleted(success: false); return }
  model.ingestInbox()
  await NotificationService.shared.reschedule(model.state)
  ```

---

## Should fix (not blocking)

### S1. Saving a step re-places its "every Nth" nights even when the schedule wasn't touched (pre-existing, missed in review 1)
- `Barrier/Screens/Routine/StepEditorSheet.swift:179-181`: whenever `freq` is `.every(n)`, `save()`
  calls `Engine.setEvery`, which picks the least-used offset, with ties going to the lowest. `load()`
  maps any evenly spaced step to `.every(gap)`, so editing just the name, amount or note re-runs it.
- Scenario: the review 1 #3 setup, a 2-night rotation with tretinoin on night 1 and azelaic acid on
  night 2. The dermatologist stops tretinoin and the user removes it, so azelaic is alone on night 2.
  Later they add a note to azelaic and tap Save. Azelaic silently moves to night 1. If last night was
  azelaic, tonight is azelaic again. If tonight was azelaic, it turns into a recovery night. With a
  retinoid left alone on night 2, the same edit gives two retinoid nights in a row. On skin cycling
  with the exfoliant removed, editing the retinol moves it one night earlier.
- Fix: only call `setEvery` (and the pre-check) when the frequency actually changed:
  `let oldEvery = original.flatMap { Engine.every(of: $0, length: plan.length) }` and skip when
  `n == oldEvery`, keeping `st.on` as loaded.

### S2. "That pattern doesn't fit" alert shows a literal "(Engine.maxRotation)"
- `StepEditorSheet.swift:127`: `"…more than (Engine.maxRotation) nights…"` is missing the backslash.
  Users read "more than (Engine.maxRotation) nights".
- Fix: `\(Engine.maxRotation)`.

### S3. "Uncertain" makes reminders generic for routines that can't shift
- `Reminders.swift:94` marks everything after an open active night as uncertain, even when
  `cycleLen == 1` (e.g. tretinoin or adapalene every night after ease-in, or a BPO morning). Nothing can
  shift there, but tomorrow's reminder becomes "Evening routine · Open Barrier to see tonight's steps",
  and tomorrow's and the next day's nudges aren't planned until something re-plans. Logging via the
  widget or Siri doesn't re-plan. `needsReconcile` already excludes these with `cycleLen > 1`.
- Fix: `if inst.hasActives && !inst.isResolved && inst.cycleLen > 1 { uncertain = true }`.

### S4. Lock Screen Done/Not tonight are silently dropped while the state is unreadable
- `NotificationService.swift:131-133,148-150` returns `nil` when `loadFailed` and records nothing.
  iOS has already dismissed the notification, and `clearDelivered` clears the rest. The user believes
  the night is logged. When the data loads again (retry, or restoring a backup after a damaged file),
  the night shows as unlogged and the rotation holds.
- Fix: in the `loadFailed` branch, record the tap where the widget and Siri already do:
  `SharedStore.appendInbox(InboxItem(day: day, slot: slot, action: .done))` (or `.skip`).
  `ingestInbox` applies it once `loadFailed` clears. Before first unlock the write can fail too, and
  nothing more can be done there.

### S5. The debounced reschedule still races the awaited one after a Lock Screen action
- In both actions, `model.update` also queues `scheduleNotifications()` (1 s debounce). If iOS suspends
  the app while that second pass is between `removePendingNotificationRequests` and its `add` loop,
  later reminders stay missing until the app runs again. It's low odds, because adds go in time order
  and the next action re-plans everything.
- Fix: make `reschedule` diff-based. Add or replace the planned ids first, then remove only the pending
  ids that aren't in the plan (still keeping `timer` and `snooze:`). Then any interruption leaves a
  valid set.

### S6. An interrupted restore loses the current photos
- `SettingsView.swift:182-190`: `store.deleteAll()` runs first, then the copy runs detached. Because
  the UI no longer freezes, the user can leave the app mid-restore. If iOS suspends and later kills it,
  the old `state.json` comes back with its photo files deleted. It's recoverable by restoring the same
  file again.
- Fix: wrap the detached work in `UIApplication.shared.beginBackgroundTask`, or write the new photos
  first and delete only ids not in the backup.

---

## Checked and fine
- `Lossy<T>` never throws, so the unkeyed container always advances: one bad element is dropped and the
  rest decode. `plan` is still strict, so a bad plan goes down the `.failed` path (alert, no overwrite).
- `SharedStore.load()`: `fileExists` works on a locked file, so before first unlock you get `.failed`
  (not `.empty`). Decode failures keep a copy before anything can overwrite.
- `loadFailed` can't block saving permanently: onboarding always ends in `finishOnboarding`, which
  clears it, and so do Start fresh, Restore and Erase. Nothing saves over the file while it's set.
  The foreground retry runs before the alert can be answered.
- `acceptFreshStart`, `finishOnboarding` and `Backup.restore` only overwrite after an explicit user
  choice. For a damaged file, the unreadable copy is already on disk by then.
- `Engine.setEvery` returning nil: both callers handle it. StepEditorSheet pre-checks with the same
  inputs it later uses. AddProductSheet adds the step unscheduled and says so.
- `editPlan`: the position is always in range, there's no off-by-one when the plan is unchanged, and
  disabled or onboarding slots behave the same as before.
- `endStale` never ends a countdown that's still running while a ritual is open or remembered. Finished
  countdowns are ended on the next foreground.
- Concurrency: `TimerActivity` and `RitualMemory` are only touched on the main actor. The notification
  handlers hop with `MainActor.run` and return a Sendable `AppState`. The detached restore only touches
  `AppModel` inside `MainActor.run`, and `PhotoStore` is file-only. In Swift 5 mode there are no
  dynamic isolation traps, and no `@MainActor` closure is handed to a system callback.
- Intent: an optional `@Parameter` with no default isn't prompted for by Siri or App Shortcuts, so
  `.now` applies.
- `Day`/`Calendar.barrier`: the remaining `Calendar.current` uses are hour/minute or weekday-symbol
  lookups, which are the same in every calendar.
