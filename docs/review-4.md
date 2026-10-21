# Review 4: procedures

Status: all 17 items fixed in the commit after `57ff8d3`. Core regression tests cover B1, B2, B3, S1,
S2, S5 and the banner half of S4 (79 core tests). Imports now keep the photo's own date (S3, not
device-verified).

Scope: commit `57ff8d3` ("Procedures"). In the core: Models, Procedures, Mutations, Engine, Reminders
and Presets. In the app: ProcedureViews, Today, Progress, Report, Routine, Derm, Root, DemoPhotos and
PhotoStore. Every item was traced through the code.

- Core findings marked **(probe)** were confirmed with a throwaway test in a copy of the package in WSL.
  The copy was deleted and the repo wasn't touched.
- The 72 existing core tests pass.
- No app code was compiled here. Anything that depends on iOS runtime behaviour is marked
  **(not device-verified)**.

Verdict: the break sync is solid.
- History before today never moves, and re-saving changes nothing.
- Face and back pauses stay apart.
- The reminder cap rework is right.

There are four blockers:
- two before/after pairing bugs
- a break-ending bug that silently drops the clinic's after-procedure break
- the committed Xcode project is missing the two new files

Then six should-fix items, a copy pass against `docs/procedure-facts.md`, and two small polish items.

---

## Blockers

### B1. A photo taken after the appointment on the procedure day becomes the "before" (probe)
- `Packages/BarrierCore/Sources/BarrierCore/Procedures.swift:92`: `beforePhoto` returns the earliest
  photo from the procedure day before it looks at earlier days. A procedure has a date but no time, so
  "earliest that day" can't tell before the appointment from after it.
- The app's own flow leads there:
  1. At 6 PM the evening before, the reminder asks for a before photo, and the user takes one (D-1).
  2. That evening, after the appointment, the user photographs the fresh result. Or it's photo night,
     and the weekly prompt (`PhotoPromptCard`, `RitualView`) asks for a photo.
  3. The evening photo is now the "before". Probe: before = the post-procedure photo, and the real
     before (D-1) gets no label at all.
- Where it shows:
  - Today's card (`ProcedureViews.swift:563`) says "Before photo taken today."
  - Compare pairs the bruised, swollen day with 4 weeks later, so the change looks bigger than it is.
  - The PDF picks it (`ReportView.swift:185`) and labels it "Before Subcision" for the dermatologist.
- Fix: look for the before in this order:
  1. The latest photo of the same area from the 7 days before.
  2. The earliest photo on the day, only when there's none in that week.
  3. Any older photo.

  ```swift
  let latest: (PhotoMeta, PhotoMeta) -> Bool = { $0.day == $1.day ? $0.at < $1.at : $0.day < $1.day }
  let same = s.photos.filter { $0.place == p.place }
  if let week = same.filter({ $0.day < p.day && $0.day.days(to: p.day) <= 7 }).max(by: latest) { return week }
  if let onDay = same.filter({ $0.day == p.day }).min(by: { $0.at < $1.at }) { return onDay }
  return same.filter { $0.day < p.day }.max(by: latest)
  ```

  `testBeforeAndAfterPhotos` pins the current rule, so update it. Add the "evening before plus evening
  of" case.

### B2. Two procedures on the same day: the first one never gets an "after" photo (probe)
- `Procedures.swift:77`: `next(after:)` counts a procedure on the same day, created later, as the next
  session. `afterPhoto` (`:97-103`) then uses that session's before photo. It's the same photo, so it
  returns nil, forever.
- Scenario: subcision and a laser in one visit, logged as two procedures (DermNet notes that subcision
  is often combined with other treatments). There's a photo the day before and one a month after.
  - The laser has a before and an after.
  - The subcision has a before and never an after. Its After slot keeps saying "Take photo", and taking
    one changes nothing.
  - There's no Compare button and no photo icon in the Derm list.
- Fix: in `next(after:)`, count only later days: `$0.day > p.day`. Procedures on the same day then share
  one before and one after.
- Also seen:
  - Today shows "Day N after" only for the procedure created last (`Procedures.swift:158`).
  - The evening before brings two 6 PM notifications (probe).

  Both are fine to leave once B2 is fixed.

### B3. Ending a break before the procedure also deletes the clinic's break after it (probe)
- `Mutations.swift:109-113`: when `today <= day`, `endPause` sets both `breakBefore` and `breakAfter`
  to nil.
- Reached from:
  - the Today banner's End (`TodayCards.swift:49`)
  - End in the Routine tab's Breaks list (`RoutineView.swift:384`)
- Scenario: a CO2 laser on Friday. The clinic asked for 4 days without actives before and 7 after. On
  Tuesday the user taps End, say because the clinic said retinol is fine until the day before.
  - The toast says "Actives are back on."
  - Probe: Friday night is "Gentle cleanser → Tretinoin → Moisturizer". Tretinoin is due the night of
    the laser and every night after. Nothing warns.
  - The clinic's numbers are gone from the procedure. The sheet shows the break turned off, so the user
    can't see what they entered.
- The banner shows one span ("Actives break until Oct 24"), so End reads as ending the whole thing. But
  the days after the procedure are what clinics most often care about. The only after-procedure timing
  in procedure-facts.md §1 is "four weeks" after laser.
- Fix, only when the break has already started and `today < day`:
  - Keep the after part: set `procedures[j].breakBefore = 0`. Clear both only if `breakAfter == nil`.
  - Toast: "Actives back on until Fri. The break after Fractional CO2 laser stays."
  - Keep today's behaviour for "Remove" on a break that hasn't started, and for End on or after the
    procedure day.
  - Update `testEndingABreakBeforeTheProcedureTurnsItOff`.

### B4. The committed Xcode project doesn't include the two new files
- `Barrier.xcodeproj/project.pbxproj` has no `ProcedureViews.swift` and no `DemoPhotos.swift`. Every
  other Swift file is in it.
- CI regenerates the project with XcodeGen, so CI builds. It only warns that the project is out of date.
- The committed project doesn't compile in Xcode: "Cannot find 'ProceduresSection' in scope". That
  breaks the next Mac install session.
- Fix: run `xcodegen generate` (or take this run's xcodeproj artifact) and commit it.

---

## Should fix

### S1. A second photo on the procedure day is labelled with the previous procedure (probe)
- `Procedures.swift:131`: `same.filter { $0.day < photo.day }` leaves out procedures on the photo's own
  day.
- Probe: a peel 10 weeks ago and a subcision today.
  - The morning photo reads "Before Subcision".
  - The evening photo reads "10 weeks after Chemical peel", in PhotoDetail and on the PDF.
  - Without the earlier peel, the evening photo has no label at all.
- `since(0)` ("Day of") can never be reached.
- Fix: use `$0.day <= photo.day` in that branch, so the evening photo reads "Day of Subcision". After
  B1, that's the usual label for a photo taken on the day.

### S2. The 4-, 12- and 26-week photo reminders fire after the photo is already taken (probe)
- `Reminders.swift:237` doesn't check for a photo. Today's card does (`Procedures.swift:171`).
- Scenario: the 4-week mark falls on photo day. The user takes the weekly photo at 8 AM. At noon they
  still get "4 weeks since Microneedling", while Today shows no card.
- Fix: also `continue` when `state.photos.contains { $0.place == area && $0.day >= day }`. The plan is
  rebuilt on every change, so the pending reminder gets removed.

### S3. Imported photos are dated today, so pairing by date goes wrong
- `ProgressScreen.swift:328` and `CameraScreen.swift:256` save imports with
  `PhotoMeta(day: model.today, …)`. This is older than the feature, but pairing now depends on the
  photo's day.
- Scenario: the before photo is taken with the iPhone Camera app on the morning of the procedure. It's
  imported that evening or a week later.
  - It's filed after the procedure, so it counts as an after.
  - Imported on the day itself, B1 makes it the before or the after, whichever way the guess falls.
- Fix: read the capture date from the image data (`CGImageSourceCopyPropertiesAtIndex`, EXIF
  `DateTimeOriginal`).
  - If it's in the past, use `Day.routineDay(thatDate)` for the day and that time for `at`.
  - Otherwise, use today.

  **(not device-verified: that the picker's `Data` keeps the EXIF dates)**

### S4. A back procedure with a break, but no back routine: Today mentions a routine that doesn't exist (probe)
- The break toggle is offered for body procedures even without a body routine. The pause is saved with
  `area: .body` (probe), and `TodayView.swift:19` shows any pause.
- Result:
  - A banner reads "Actives break until Oct 9 · For Cortisone injection, as your clinic asked. Back
    routine: basics only." Its End button changes nothing.
  - The Breaks list says the same, and so does the sheet's summary ("come out of your back routine").
- The area's name also doesn't match:
  - The sheet's picker says "Body" when there's no body routine (`ProcedureViews.swift:317`).
  - The Derm row, the Today card and the banner use `plan.body.displayName`, which defaults to "Back"
    (`:125`, `:547`, `TodayCards.swift:60`).
  - The PDF says "Body".
- Fix:
  - Hide `breakSection` (`ProcedureViews.swift:385`) when `p.place == .body && !model.hasBodyRoutine`.
  - Banner: `model.state.plan.activeSlots.lazy.compactMap { Engine.activePause(model.state, today, slot: $0) }.first`.
  - Add one `areaName` helper (`hasBodyRoutine ? displayName : "Body"`) and use it in all four places.

### S5. A travel pause hides a procedure break on the same days (probe)
- `Procedures.swift:139`: `breakFor` reads only the first pause that covers the day. If that's the travel
  pause:
  - the hero card and the reminders say "Plan paused" instead of "Actives break (Chemical peel)"
  - the banner shows "Traveling until …"
- Which pause wins depends on the order they were saved, because `syncBreak` moves procedure pauses to
  the end of the list.
- Fix:
  - `breakFor` looks first for a covering pause that has a `procedureID`.
  - The banner shows the procedure break when both cover today. Ending the travel pause then leaves the
    break in view.

### S6. On the procedure day, Today has no aftercare and keeps asking for a before photo
- On the day itself the card is `.upcoming(inDays: 0)`. It never shows `p.note`, which first appears the
  next day (`ProcedureViews.swift:570`). The evening after the appointment is when "no makeup today" or
  "cold packs" matters.
- The "Before photo" button and "If you can, take a before photo" stay all day, after the appointment
  too, which invites the B1 photo.
- Fix: when `inDays == 0`:
  - Show the note, styled like `.after`.
  - Word the line "Before your appointment, take a before photo if you can."

---

## Copy (docs/procedure-facts.md)

### C1. Sun advice shows for subcision; "Scar treatments" shows for treatments that aren't for scars
- `Procedures.swift:50`: `sunCare` includes `subcision`, `ipl` and `dermabrasion`. Rule 8 says no
  subcision aftercare, and §2 has sources for laser, peels and needling only.
- On a subcision:
  - the sheet shows "Sun after a procedure" (`ProcedureViews.swift:172`)
  - the Today card says "Sun protection matters on treated skin" (`:578`)
- The same check shows "Scar treatments usually work gradually…" (`:253`, `:585`). So it also appears for
  "Vascular laser", "IPL" and "Pico laser", which aren't scar treatments.
- Fix:
  - `sunCare` keeps laser, peel, needling, tca and resurfacing.
  - Add `scarTreatment` for the gradual line: subcision, needling, CO2/erbium/fractional/resurfacing,
    peel, tca.

### C2. "makes the change easy to see" promises a change
- `ProcedureViews.swift:583` and `Reminders.swift:245`. Rule 7 forbids result promises.
- Use "…makes any change easier to see."

### C3. Healing and timing claims in the demo and in the placeholder
- `Presets.swift:193`: the demo subcision note is "Bruising is normal. No makeup for 24 hours. Cold packs
  if it’s sore."
  - It's on Today in screenshot 21 and in the report shot.
  - Store screenshots read as the app's own claims, and rules 3 and 8 cover subcision downtime.
- `ProcedureViews.swift:430`: the placeholder is "e.g. no makeup for 24 hours".
- Fix:
  - Demo note: "Gentle cleanser and moisturizer only. Call the clinic with any questions."
  - Placeholder: "In their words, e.g. gentle cleanser only".

### C4. Lines that read awkwardly
- `ProcedureViews.swift:579`: "Follow your clinic on how long." Use "Follow your clinic’s advice on how
  long."
- `:46`: "Before, and 5 weeks after Subcision. Drag to compare." The title already names the procedure,
  so use "Before and 5 weeks after. Drag to compare."
- `:234`: "Before session 1 (Oct 3), and Oct 20." Use "Before session 1 (Oct 3) and now (Oct 20). Drag to
  compare."
- `:532`: the kicker "4 weeks since" hangs above "Time for an after photo".
  - Use "4 weeks after".
  - Use "6 months after" in place of "26 weeks". Change the reminder title too (`Reminders.swift:244`).

### C5. The photo footer promises things the app doesn't do
- `ProcedureViews.swift:251` says "Barrier asks again at 4, 12 and 26 weeks." Two problems:
  - Only the latest procedure on an area gets these reminders (`Reminders.swift:234`,
    `Procedures.swift:158`), so the line is false for session 1 of a series.
  - "In the same light as the before one" makes no sense when there's no before photo.
- `:253`: "the latest since" is wrong once a next session exists. The after is then that session's
  before.
- Fix:
  - `:251`, for the latest procedure on that area: "Take an after photo in the same light. Barrier
    reminds you at 4, 12 and 26 weeks."
  - `:251`, for an earlier session: "Take an after photo in the same light."
  - `:253`: "The last photo before, and the latest one since (or the one before your next session)."

---

## Polish

### P1. The after-photo card has two ways to hide it
- The `.photo` card has the xmark (`ProcedureViews.swift:502`) and "Not now" (`:607`). Both do the same
  thing.
- Drop the xmark for `.photo`.

### P2. Break steppers: 28 taps for "4 weeks before laser"
- `ProcedureViews.swift:398-401`, ranges `0...60` and `0...90`. Clinics often give the break in weeks.
- Step by 1 up to 14, then by 7 (with a custom binding, since `step:` is fixed).

---

## Checked and fine
- Old saves:
  - `Pause.area`, `Pause.procedureID` and `AppState.procedures` are optional or lossy.
  - The synthesized `encode` includes `procedures`.
  - One bad procedure costs only itself (tested).
- History rule in `syncBreak`, traced and probed:
  - Every day before today keeps its pause. Pauses are trimmed to yesterday and never extended
    backwards.
  - Moving a procedure into the past pauses only from today.
  - Saving again with no changes changes nothing (same pause id).
  - Deleting a procedure keeps its past days and unlinks them.
  - Switching face → body mid-break keeps the face days and starts the back pause today.
  - The old and new pauses are merged only when the new part starts today.
- Ending a break after the procedure day shortens `breakAfter`, and later edits keep it that way.
- Two procedure breaks on the same day are independent.
- Scoping:
  - Every `Engine.timeline` call passes its slot. A face break leaves the back routine alone in the
    engine, reminders, widget and Siri, and the other way round.
  - The only call without a slot is the Today banner (S4).
  - `needsReconcile` never asks about paused days.
- Reminders:
  - One-offs (up to 4 procedure reminders plus the follow-up) always fit. Routine reminders fill up to
    57.
  - The keep-alive moves to the day before the last routine reminder that's kept.
  - Ids include the procedure's day, so when a procedure moves, `applyPlan` removes the old reminder.
  - Procedure reminders have no actions and no category.
  - Break nights say "Simple night" and name the procedure.
- Compiling, checked by reading:
  - Every symbol the new views use exists with that signature: `Day(date:)`, `short`, `relative`,
    `weekdayShort`, `CameraScreen(initialArea:)`, `Chip`, `FlowLayout`, `SourcesView`, `PhotoThumb`,
    `PhotoDetail`, `PhotoStore(demo:)`, `hasBodyRoutine`.
  - `Area` is `Identifiable`, as `fullScreenCover(item:)` needs.
  - Every `switch` in the view builders is exhaustive.
  - `ProcedureMoment` is `Hashable`, as `ForEach(id: \.element)` needs.
- PDF page 2, worst case: 5 procedures, each with details and aftercare, and 6 photos with context
  lines. That's about 760 of the 770 pt available, so it fits, barely (an estimate, not rendered).
