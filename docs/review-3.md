# Review 3: the body routine

Scope: commit `b2d6e2e` ("Body routine"), Packages, Shared, Barrier, BarrierWidget. Every item was
traced through the code. No source files were changed. No Swift toolchain on this machine, so nothing
was run. Anything that depends on iOS runtime behaviour is marked **(not device-verified)**.

Verdict: the foundations hold. Old saves load, the face routines' schedule is untouched, notifications
stay under the limit, and every `Slot` switch handles `.body`. There are five blockers, each a few
lines to fix. Then ten polish items.

---

## Blockers

### B1. Every body step says "Every morning", in the Routine tab and in the PDF report
- `Packages/BarrierCore/Sources/BarrierCore/Engine.swift:484` and `:495`:
  `slot == .pm ? "Every night" : "Every morning"`. Body quick-adds are `.all` (`Presets.makeStep`).
- Shown by `StepRow.detail` (`RoutineView.swift:253`) and by the report's step lines
  (`ReportView.swift:116`).
- Scenario: the user adds "Clindamycin lotion" to an evening, after-shower back routine. The Routine
  tab reads "Every morning · Thin layer on affected areas". The report for the dermatologist prints the
  same line right under "After shower, around 8:30 PM."
- `testDescribeUsesDays` only checks "every other day", so CI didn't catch it. The new
  `16-routine-body` screenshot shows it.
- Fix: in both places, `return "Every \(word)"` ("Every night", "Every morning", "Every day").

### B2. The report prints "26 of 1 back days done" after any edit to the body routine
- `Barrier/Screens/Derm/ReportView.swift:129-131`, shown at `:211`.
- `bodyDue` keeps only instances with `!$0.steps.isEmpty`. Days before the anchor always have
  `steps: []` (`Engine.swift:217`), so they never count as due. `bodyDone` counts every `.done`,
  including those days.
- Every body edit moves the anchor to today (`Mutations.swift:150`): `StepEditorSheet.save`,
  `AddProductSheet.insert` and swipe-delete all go through `editPlan`.
- Scenario: the back routine has run for 30 days, 26 done. Today the user changes the lotion's amount
  and taps Save.
  - Today the stat disappears (`bodyDue == 0`).
  - Tomorrow the PDF says "26 of 1 back days done".
- The weekly recap doesn't have this bug: `Recaps.counts` also counts days with a done or skipped
  entry. The evening stat doesn't either, because it has no steps filter.
- Fix: use the recap's rule. Make `Recaps.counts` `public` (or move it to `Engine`) and:
  ```swift
  bodyDue = btl.filter { $0.status != .pending && Recaps.counts($0) }.count
  ```

### B3. On days the body routine isn't due, Today shows it as due, with an active Done button
- Back treatments are often every other day ("BPO wash every other day") or on set weekdays. On the
  off days `inst.steps` is empty, but:
  - `AppModel.otherSlots` (`AppModel.swift:202-205`) lists the body whenever the routine has any steps.
  - The compact row (`TodayView.swift:337-339`) reads "Back · 0 steps · after shower · 8:30 PM" with
    an enabled Done. Tapping the row opens a ritual that says "Nothing to do here."
  - The label is always the name (`Engine.swift:132-139`), so nothing says it's an off day.
  - For a body-only user, the big card says "Nothing scheduled. Add steps in Routine."
    (`TodayView.swift:219-224`), which is wrong. Start and Done are disabled there, so the day can't be
    logged.
  - The day sheet offers Mark done and Mark skipped, and calls a past off day "Not logged".
- The same happens on a body "gentle day" when every body step is a treatment: all the steps drop out.
- Done on an off day logs a day that the report and the recap then count.
- Reminders are already correct (no reminder on off days). Only the screens are wrong.
- Fix:
  - `otherSlots`: drop `.body` when `instance(.body).steps.isEmpty && instance(.body).entry == nil`.
  - Compact row: `.disabled(inst.steps.isEmpty)` on Done, as the big card already does.
  - Big card, body with no steps today: "Nothing today. Next: Thu", from
    `Engine.next(state, slot: .body, today:, where: { _ in true })`, instead of "Add steps in Routine".
  - `DayDetailSheet` (`TodaySheets.swift:172-179`): when `inst.steps.isEmpty` and there's no entry,
    show "Nothing due" instead of the buttons and "Not logged".

### B4. A back photo imported from Progress is filed as a face photo, permanently
- `Barrier/Screens/Progress/ProgressScreen.swift:290`: `PhotoMeta(day:…, area: photoArea ?? .face)`.
  The filter defaults to "All" (`photoArea == nil`), so every import from the default view is "face".
  Nothing can change a photo's area afterwards.
- Scenario: someone photographs the user's back with the iPhone Camera app, the most natural way to
  get a back photo. The user opens Progress and taps Import. The photo is saved as Face:
  - It's the newest face photo, so it becomes the ghost overlay the next time the front camera opens
    (`CameraScreen.swift:93`).
  - It can be paired with face photos in Compare.
  - The PDF labels it as a face photo.
- Fix: when `showAreas && photoArea == nil`, ask before saving: a `confirmationDialog` "Which area?"
  with Face and the body name, then save with that area.

### B5. The widget and Siri ignore the body routine, so a body-only user logs phantom face routines
- Body-only is a supported setup: onboarding offers "Skip for now" on the evening and morning pages, and
  `AppModel.leadSlot` (`AppModel.swift:194`) leads Today with the body routine in that case. The
  morning and evening stay enabled but empty (`Presets.emptySlot`).
- Widget, `BarrierWidget/TonightWidget.swift:51-56`: only `.am` and `.pm` are candidates, so it falls
  through to the empty morning. It shows "MORNING · 8:00 AM / Morning routine / 0 steps". Done
  (`:169`, `routine: isNight ? .evening : .morning`) logs a done morning with nothing in it. Progress
  then shows "1 mornings" and the report "1 mornings logged".
- Siri, `Shared/Intents.swift:26-29,50`: "I did my Barrier routine" in the evening logs the empty
  evening as a done "Recovery night". That adds to "nights done" and unlocks "First night done".
  `TonightIntent` (`:85`) answers "Tonight is recovery night: ."
- Fix:
  - Widget `entry`: `if !amOn && !pmOn && state.plan.activeSlots.contains(.body) { slot = .body }`.
  - Widget view:
    - `isNight = entry.slot != .am` (or store `isDusk` in the entry).
    - A body kicker ("Back · 8:30 PM") and the `figure.stand` symbol.
    - `MarkRoutineDoneIntent(routine: RoutineChoice(slot: entry.slot))`, after adding `init(slot:)`.
  - Intent: when `routine == nil`, choose from the state:
    `state?.plan.activeSlots == [.body] ? .body : RoutineChoice.now.slot`.
  - `TonightIntent`: when the evening isn't active and the body is, answer with the body routine.

---

## Polish (within scope)

### P1. PDF page 1 can now overflow A4 and cut off the questions (estimate, not rendered)
- `ReportView.swift:178-231`. The left column (fixed 250 pt) now stacks:
  - Evening and Morning.
  - The new body block (`:188-193`).
  - Treatments, which now includes body products (`usedProductIDs`, `:138`).
- The page is a fixed 842 pt frame with 36 pt padding (770 pt usable). Anything below that is cut off.
- Estimate for a realistic derm plan (4 evening, 4 morning and 2 body steps, 5 treatments with short
  notes, 12 check-ins, 5 questions, an irritation instruction):
  - Without the body routine: ~748 pt. It fits.
  - With it: ~905 pt. Questions, "Instructions noted" and the "Not a medical record" footer fall off
    the page.
  - The demo state is lighter (~690 pt), so the CI report screenshot won't show it.
- Fix:
  - Move the body block to the top of the right column, which is ~170 pt shorter.
  - Show 6 skin-log rows instead of 12 when the body block is present.
  - Give the product notes in Treatments `.lineLimit(2)` in place of `fixedSize`.
  - Then check once on a device with a full plan.

### P2. "Night"/"tonight" copy left in body screens
- Rotation section, `RoutineView.swift:168-169,183,190,207-208,215,220`. A body routine gets one as
  soon as a step is "every other day". It reads "Repeats every 2 nights", "Night 1", "Tonight" and
  "Make tonight night 2?". Use `slot.word`, and `slot == .body ? "Today" : "Tonight"`.
- `StepEditorSheet.swift:67,73,94`: "Pick nights in the rotation", chips "Night 1", and the footer
  "Barrier counts nights you actually do…". Use `target.slot.word`.
- `TodayCards.swift:19` (ReconcileCard for a body day): "Logging it keeps tonight right". For body,
  use "keeps the next one right".
- `TodayView.swift:307-308` (skipped banner, when the body leads): moon icon, and "Tomorrow picks up
  where you left off" on a daily routine where nothing is held back. Use the rule from the new
  `skipDetail` (`hasActives && cycleLen > 1`).
- `TodaySheets.swift:58`: "Next time picks up back where you left off." For body, drop the label:
  "Next time picks up where you left off."

### P3. "Pause the plan…" from the body's "Not today?" sheet also pauses the face routines
- `TodaySheets.swift:28-30`: the option is offered for body with the generic detail "Traveling, a
  procedure, or a break." Pauses are global (`Engine.isPaused`).
- Scenario: the back is irritated and the user pauses from the Back row for 5 days. The evening
  tretinoin goes to basics for 5 days and the rotation holds.
- Fix: for `inst.slot == .body`, use the detail "Pauses your face routines too."

### P4. A back photo counts as the week's face photo
- `TodayCards.swift:245-248,256` (PhotoPromptCard): `tookToday`, `lastPhoto` and `photos.isEmpty` look
  at both areas. Weekly back photos keep the face photo from ever being "overdue". A back photo taken
  on photo night hides the face prompt.
- `RitualView.swift:278`: the same check hides "Take this week’s photo" after the evening routine.
- `Milestones.swift:32`: "Before and after, unlocked" fires with one face and one back photo, which
  can't be compared.
- `ProgressScreen.swift:212`: under "All", Compare appears with one face and one back photo, then
  every pair is refused.
- `ProgressScreen.swift:206`: if Back was selected and the body routine is then turned off with no
  back photos, the picker hides but the filter stays on Back. The grid stays empty, and Take photo
  opens the rear camera with the timer.
- Fix:
  - Filter on `$0.place == .face` in the first three.
  - Show Compare when some area has 2+ photos.
  - Use `let filter = showAreas ? photoArea : nil` for the grid and the camera.

### P5. Camera access denied: switching to the back turns "Open Settings" into "No camera here"
- `CameraScreen.swift:69-74` calls `camera.switchTo` on every area change. `switchTo` (`:304`) sets
  `.unavailable` when `AVCaptureDeviceInput` throws, which it does when access is denied.
- Fix: in `onChange(of: area)`, only call `switchTo` when `camera.state == .running`.

### P6. Morning routine plus body routine: the evening body routine never leads Today
- `AppModel.swift:195`: `if !hasPM { return .am }`. After the morning is done, the big card stays on
  "Morning done" all evening, and the back routine is a small row.
- Fix: compute `amOpen` first, then
  `if !hasPM { return (amOpen || !active.contains(.body)) ? .am : .body }`.

### P7. The day sheet shows an empty "Back" section for days before the body routine existed
- `TodaySheets.swift:129`: the condition uses `plan.createdAt`, not the body routine's start. Any
  calendar day from before the back routine was set up shows an empty BACK section, with no status and
  no steps.
- Fix: for `.body`, also require `day >= sp.anchor.day || entry != nil`.

### P8. Body UI shows when the body routine is on but empty
- Turning it on in onboarding and then tapping "Skip for now" leaves `enabled == true, steps == []`.
  The Face/Back pickers then appear with nothing behind them, in:
  - the check-in card (`TodayCards.swift:104`)
  - the camera (`CameraScreen.swift:28`)
  - Progress (`ProgressScreen.swift:99,137,164,205`), along with the calendar legend
- Fix: use `state.plan.activeSlots.contains(.body)` in those checks.

### P9. A body "gentle day" is stored with the label "Gentle morning"
- `Mutations.swift:69`: `slot == .pm ? "Recovery night" : "Gentle morning"`. If that day isn't logged
  and the routine is edited later, the day sheet shows "Gentle morning" under BACK.
- Fix: `slot == .body ? "\(plan.body.displayName), gentle" : …`.

### P10. The report's photo page mixes areas
- `ReportView.swift:155-160` picks the first, the middle and the latest four photos across both areas.
  Weekly back photos can push out the latest face photo, leaving no face "after" on the page.
- Fix: pick per area. Take the first and latest face photos and the first and latest body photos, then
  fill with recent ones.

---

## Checked and fine
- Old saves: `Plan.init(from:)` defaults `body` when the key is missing. `CheckIn.area` and
  `PhotoMeta.area` are optional (`nil` = face), so old check-ins and photos read as face everywhere.
  `testOldSavesWithoutABodyRoutineStillLoad` covers the plan.
- Every `switch` over `Slot` is exhaustive with no `default`, so nothing silently treats `.body` as
  face.
- Notifications:
  - Body reminders use the `routine-day` category with the same `done`/`snooze`/`skip` action ids.
    The existing handler logs the right slot and clears its own delivered and snooze ids.
  - Snoozes copy the category.
  - The worst-case plan is 60 (3×14 mains, 3×3 nudges, 7 sunscreen, a follow-up, keep-alive), capped
    at 58. The cap drops the two furthest day-13 reminders, which the next refresh plans again.
  - Per-routine timers, snoozes and the test reminder can briefly push the pending count past 64. iOS
    then drops the furthest-out one **(not device-verified)**.
- The face schedule isn't touched by the body routine:
  - The `uncertain` flag is per slot.
  - `editPlan`'s open question is filtered by slot.
  - Conflicts are checked per instance, so BPO on the back doesn't flag tretinoin on the face.
  - Templates keep the body routine and its products.
  - `removeProduct` and `pruneOrphanProducts` cover all three slots.
  - AddProductSheet no longer offers face products to the body.
  - Journey cards and the face tip stay face-only.
- Wait timers are per ritual id, so a body wait and a face wait don't end each other.
- SwiftUI ids:
  - The check-in lists moved from `id: \.day` to `\.self`, since a day can now have two.
  - `otherSlots` ids are unique.
- Recap:
  - It counts pre-anchor body days through their entries.
  - The headline and the lines don't repeat the body.
- Core logic:
  - Engine labels for body pause and recovery are right.
  - `needsReconcile` orders am → pm → body.
  - The `Stats.bodyDone` switch is exhaustive.
- Deep links `ritual/body/<day>` resolve through `Slot(rawValue:)`.
