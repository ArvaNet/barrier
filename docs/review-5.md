# Review 5: timeline, change log, skin score, report

Status: open.

Scope: commit `8f22714` and its two build fixes, `0892ad8` and `0f1f217`. In the core: History, Models, Day and Presets. In the app: TimelineStrip, AppModel, Today, Routine, Progress, Derm and Report. Every item was traced through the code.

- Core findings marked **(probe)** were confirmed with throwaway tests in a copy of the package in WSL. The copy was deleted and the repo wasn't touched.
- The 91 existing core tests pass.
- CI is green at `0f1f217`. I didn't download that run's screenshots 22–25, so the new screens haven't been looked at yet.
- Report heights are worked out from font sizes, not measured from a render. They're marked **(estimate)**.
- Anything that depends on iOS runtime behaviour is marked **(not device-verified)**.

Verdict: the change log's bookkeeping is solid.
- There's one entry per day, and a day that undid itself leaves no trace.
- A move between routines is reported once.
- Old saves load.

What the dermatologist sees is another matter. There are five blockers:
- any routine edit wipes the timeline before that day
- re-adding a product, or "Start over", writes nonsense lines that hide the real change
- a strength change isn't logged
- page 1 can overflow and silently drops content
- the committed Xcode project is missing the new file

The sample report hides the first blocker, because its routines were never edited. Then come eleven should-fix items, a section on reading the report in 30 seconds, a copy pass and seven polish items.

---

## Blockers

### B1. Any routine edit wipes the timeline before that day (probe)
- `Mutations.swift:171`: `editPlan` moves the routine's anchor to today. Every Save in the step editor calls it, even a name or note fix (`StepEditorSheet.swift:184`). So do adding a product (`:290`), deleting a step (`RoutineView.swift:136`), the rotation stepper and the ease-in controls.
- Before the anchor, `Engine.timeline` gives instances no steps, and unlogged days come back as `.off` (`Engine.swift:212-223`). `History.swift:243-246` then:
  - draws every done night as "Basics only", because `active` is read from the empty `inst.steps`
  - drops every skipped or unlogged night entirely
- Probe: tretinoin every night, six days logged (done, done, skipped, unlogged, done, done).
  - Before an amount edit, the row reads `A A X X A A`.
  - After it, the row reads `b b · · b b`, which says "no tretinoin, never missed".
- The same root cause shows up three more ways (probe):
  - A routine turned off with its toggle (`RoutineView.swift:105`, `:466`) gets `.off` for every day after the anchor, done or not (`Engine.swift:243`). Its row disappears: the Back row is gone.
  - Turned back on, the routine shows every day it was off as missed. The probe gave 8 days marked missed.
  - Page 1's "How it went" (`ReportView.swift:183-184`, older code) doesn't count unlogged nights before the anchor as due. The probe shows "4 of 5" where the truth is "4 of 6", so adherence is overstated.
- Fix: replay each stretch of days with the plan it had.
  1. Store each routine's `SlotPlan` and the products it uses in `PlanSnapshot`. Make the fields optional, so older snapshots still load. That's about 2 KB per snapshot, 200 at most.
  2. Treat an anchor change or an on/off change as a change in `sameRoutine`, with no lines.
  3. In `TreatmentTimeline.build`, run `Engine.timeline` once for each stretch `[snapshot.day, next.day)`, on a copy of the state that has that snapshot's plan and products. Days before the first snapshot keep today's behaviour.
  4. Compute "How it went" from the same marks (done and due per row), so the numbers match the strip.
  5. Add tests:
     - an edit on day 6 keeps the marks for days 0–5
     - a routine that was turned off keeps its logged days
     - a routine that was turned back on shows nothing for the days it was off

### B2. Removing and re-adding a product, or "Start over", writes nonsense lines and hides the real change (probe)
- `History.swift:73-103` matches products by ID. A product added again gets a new ID. That happens with the quick-add chip and with "Start over from a template" (`Presets.swift:122-127`).
- Probe, tretinoin deleted and re-added the same day: the log reads "Tretinoin: added to evening, every night" and then "Tretinoin: stopped (evening)".
- Probe, "Start over" with "Just the basics" from the retinoid routine:
  - The log gets 11 lines, such as "Moisturizer: added to morning, every morning" next to "Moisturizer: stopped (morning)".
  - The one real change, "Tretinoin: stopped (evening)", is line 10.
  - The report prints only the first 3 lines of a change (`ReportView.swift:397`). The dermatologist reads "cleanser, moisturizer, sunscreen added" and never learns that tretinoin stopped.
- Fix:
  - In `diff`, before writing "added" or "stopped", pair an added product with a stopped one in the same routine when their names match (case-insensitive, trimmed). Compare the pair as one product: schedule, amount and end date.
  - Pair the same way across routines when looking for "moved".
  - Add both probes as tests.

### B3. A strength change isn't logged, and older lines show the new strength (probe)
- The app keeps the strength in the product's name. `Product.shortName` strips it, and the add sheet says "rename it to the exact product and strength afterwards".
- `sameRoutine` ignores names (`History.swift:39`). Renaming "Tretinoin 0.025% cream" to "Tretinoin 0.05% cream" on a later day records nothing (probe: the history stays at 2 entries).
- `diff` writes every line with today's name (`:58`). Probe: the Oct 8 amount change reads "Tretinoin 0.05% cream: …", a strength that only started on Oct 15.
- A strength change is the change a dermatologist most wants to see.
- Fix:
  - Add the strength (`\d+([.,]\d+)?\s*%` in the name) to the `sameRoutine` key.
  - Write "Tretinoin: 0.025% → 0.05%" when it changes.
  - Write each line with the name from that change's own snapshot (`b`'s item), not the current one. Typo fixes stay ignored, so `testARenameIsNotAChange` still holds.

### B4. Page 1 can overflow, and it drops content without saying so (estimate)
- Space on page 1:
  - The page has 770 pt.
  - The header, the timeline block (about 179 pt with three rows and scores), the footer and the gaps take about 317 pt.
  - That leaves about 453 pt for the two columns.
- The left column can't shrink. Score and break lines use `Paper.small`, which is `fixedSize` (`:286`), and so are the questions (`:350`).
- Ways to overflow:
  - 8 questions of two lines each, plus 4 break lines, is about 40 pt over. The 36 pt margin doesn't absorb it, so the footer is cut off.
  - With break lines that wrap because of a long procedure name, it's about 85 pt over. The footer and the last question are lost.
  - The right column: 8 changes of 3 lines each, plus the notes and "If irritated", is about 100 pt over, even after each change line shrinks to one line.
- Content that's dropped silently, at any size:
  - every line after a change's 3rd (`:397`), which is how B2 hides the tretinoin line
  - every change before the latest 8 (`:387`), though their numbered markers stay on the timeline with nothing to explain them
  - every question after the 8th (`:346`)
- Fix:
  - Draw the footer as a bottom overlay of `ReportPage`, outside the content stack, so nothing can push it off the page.
  - Questions: `lineLimit(3)` without `fixedSize`, at most 6, then "+N more questions".
  - Break lines: `lineLimit(1)`.
  - Changes: at most 12 lines in total on page 1, then "+N more on page 2". Page 2 lists the rest in full, after Treatments.

### B5. The committed Xcode project is missing `TimelineStrip.swift`
- CI is green at `0f1f217`, and it still warns that the project is out of date. `project.pbxproj` has no `TimelineStrip.swift`.
- CI regenerates the project, so CI builds. In Xcode on the Mac, the committed project fails with "Cannot find 'TimelineStrip' in scope". This is the same problem as review 4's B4.
- Fix: run `xcodegen generate` (or take the xcodeproj artifact from that run) and commit it. Then look at screenshots 22–25.

---

## Should fix

### S1. On the iPhone, the report is too small to read and can't be zoomed (not device-verified)
- `ReportView.swift:24-31` shows each page as an image fitted to the screen width. A 595 pt page shows at about 353 pt, which is 59%.
- At that size, the timeline's 7.5 pt labels and legend are about 4.4 pt on screen, and the change lines are about 5.6 pt. There's no pinch zoom.
- The plan is to hand the phone to the dermatologist, so this decides whether the 30 seconds works.
- Fix: show the PDF that `render()` already writes in a `PDFView` (PDFKit, `autoScales = true`), which gives pinch and double-tap zoom. The preview then matches the shared file exactly.

### S2. The legend explains 3 of the 8 marks, and irritation looks like any other symptom in grey
- `TimelineLegend` (`TimelineStrip.swift:260-276`) leaves out:
  - the short grey outline (basics missed)
  - the dashed box (today, not done yet)
  - the hollow dot (calm) and the grey dot (symptoms)
  - the score line
- The file header promises the strip reads in grayscale. Irritation (#A4402F) and symptoms (#6B7772) come out as near-identical greys, at about 36% and 45% luminance, and only the size differs slightly.
- Fix:
  - Draw a missed night one way: the full outline. At 4.8 pt per day, the split between "missed with actives" and "missed basics" can't be read.
  - Leave today's dashed mark out of the PDF (`compact`).
  - Give irritation its own shape: a small upward triangle.
  - Write the legend in lane order: "With treatment · Basics only · Skipped or not logged", then "Skin: calm ○ · symptoms ● · irritation ▲", then "Overall: weekly rating, Rough to Great", then "Procedure · Routine change · Photo · Break".

### S3. The strip is mostly empty or mostly blocks, depending on how long it covers (probe)
- Days before the plan:
  - `build` (`History.swift:227-231`) starts at the earliest photo or procedure in the last 98 days.
  - In the sample, 31 of 55 days (56%) are empty rows before the plan starts.
  - In real use, an imported old photo does the same, because imports now keep their capture date.
- A short history:
  - Each day's column is the width divided by the number of days, and the bar fills 68% of it (`:40`, `:94`).
  - With 10 days, the report draws 32 pt-wide blocks.
  - On the first day, the Progress card draws one dashed box about 175 pt wide.
  - The owner's report next week will cover a short history.
- Fix:
  - `from` = the plan's start or the first event, whichever is earlier. Clamp it to at most 14 days before the plan's start, at least 27 days before today, and at most 97 days before today.
  - Tint the days before the plan faintly, with the label "Before Barrier".
  - Cap the bar width at 6 pt.
  - Earlier procedures are already listed on page 3.
  - Update `testDemoHasAStory`.

### S4. A break shades every row, even when it only covers the face or the back (probe)
- `bands` (`:74-84`) spans all rows, and `Band` doesn't carry an area.
- In the sample, the face-only actives break around the subcision (days 45–53) runs across the Back row. That row shows full "with actives" bars inside the band, which reads as treating during the break.
- Fix:
  - Carry `area` on `Band`.
  - Draw the band over the rows it applies to, plus the Skin and Events lanes.
  - When there's a body routine, label it "Actives break (face)".

### S5. Routine-change markers cover photos and each other (probe)
- Photos and change markers share one lane, `eventY` (`:165`, `:189`). A 10 pt marker covers about 2 days at 4.8 pt per day.
- In the sample, change 1 and the first back photo are both on day 9, so the photo is hidden.
- Changes on consecutive days overlap, and their numbers can't be read.
- Fix:
  - Move photos into the procedure lane (`procY`).
  - When two markers are closer than their width, draw the second one 11 pt lower.

### S6. Oral medication shows as "Basics only"
- `History.swift:243` uses `DueStep.active`, which is `kind.isActive` and leaves out `.oral`. A morning with doxycycline or isotretinoin is drawn as a short, pale bar.
- Fix: `let active = inst.steps.contains { $0.product.kind.isActive || $0.product.kind == .oral }`, and name the mark "With treatment".

### S7. The sample report contradicts its own change log (probe)
- The Morning row shows "with actives" from day 0 (`AXAAXAAX…`). Change 2 says azelaic acid was added on day 12. The cause is that `Presets.swift:172` gives it `from: start`.
- B1's replay fixes this, because the day-0 snapshot has no azelaic acid. Without B1, set `aze.from = start.adding(12)`.
- One in three mornings is missed (`Presets.swift:228`, `i % 3 != 1`). For a sample meant to impress, miss 2–3 in total.

### S8. The score card can save a back score as a face score
- `TodayCards.swift:122` shows the area name only when two areas are on the card.
- Once the face has its score for the week, a back that's still due gets a single row with no label, under "Your skin this week, overall". The tap is saved as the back's (`.body`).
- Fix: label the rows whenever `Scores.areas(s).count > 1`.

### S9. A future start date isn't in the change log (probe)
- `SnapshotItem` has no `from`. Probe: azelaic acid added on Oct 8 with "Started on" set to Oct 25.
  - The line reads "added to morning, mon, wed, fri" under Oct 8.
  - The marker sits on Oct 8.
  - Moving the start date later records nothing.
- Fix: add `from` to `SnapshotItem` and to the key.
  - When the start is after the day of the change, write "…, from Oct 25".
  - When the start date changes, write "Azelaic acid 15%: start moved to Oct 25".

### S10. A clock set ahead once freezes the change log (probe)
- `History.swift:124`: once a snapshot is dated in the future (a wrong date on the phone, or flying east), every later `recordPlan` returns early until that date comes.
- Probe: one snapshot dated a year ahead. Edits on the next two days are never recorded, and the timeline shows 0 changes.
- Fix: when `last.day > today`, treat that snapshot as today's. Set its day to today, merge it into the snapshot before it if that one is also today's, and then apply the usual same-day rules.

### S11. A back check-in shows on the face's Skin row (probe)
- `History.swift:256-260` merges face and back check-ins into one Skin row. Probe: a red back on day 1 becomes a red dot on "Skin", which the dermatologist reads as the face.
- Fix: add a second row, "Back skin", when there's a body routine or a back check-in in range.

---

## Reading it in 30 seconds

These are for page 1, and the Progress card where they apply. They come on top of S1–S5.

1. Add a "Now" line under the title: the current treatments and medication with their schedules, taken from the current plan. For example: "Now: Tretinoin every other night · Azelaic acid 15% every morning · Clindamycin lotion daily (back)". It's the dermatologist's first question, and today the answer is only on page 2.
2. Write "How it went" in the same terms as the rows, from the same marks (B1): "Evening 19 of 23 · Morning 15 of 23 · Back 12 of 14, since Sep 28". It replaces "8 mornings logged", which gives no total to compare with.
3. In the block title, add "one column per day": "Timeline, since Sep 28 · one column per day".
4. Rename the score lane "Overall 1–5". Name procedures on the strip with their session ("Subcision 1/3"), as on page 3.

---

## Copy

### C1. How the change lines read
- Problems:
  - "added to morning, every morning" names the routine twice.
  - Weekdays come out lowercase ("mon, wed, fri"), from `.lowercased()` at `History.swift:78`, `:80` and `:84`.
  - A body routine the user named, such as "KP arms", becomes "kp arms".
  - "amount Pea-size" reads like a raw field.
- Rewrite, product first so the list can be scanned:
  - Added, when the schedule already names the routine: "Azelaic acid 15%: started, every morning".
  - Added, when it doesn't (weekdays, or the body routine's "every day"): "Azelaic acid 15%: started in the morning, Mon, Wed, Fri".
  - Schedules: lowercase only a leading "Every" or "Not". Keep weekday names and routine names as written.
  - Amount: "Tretinoin: amount set to pea-size". A removed amount is silent today (probe). Write "Tretinoin: amount removed".
  - Body routine: "Back routine started: Clindamycin lotion, every day".
  - Ease-in: "Evening: easing in, full routine from Nov 2". The end date is already in the snapshot.

### C2. "No changes since …" can mislead or be false
- The owner's case: a save from before this build, or a restored backup, starts its log on the day this build is installed (`AppModel.swift:76`). "No changes since Oct 21" then reads as "unchanged since Oct 21".
- `ReportView.swift:390` uses the first snapshot's date even when there were changes, just older than the 14 weeks shown. That makes it false.
- Use:
  - in the report: "No changes in these 14 weeks (last: Jun 2)"
  - when there are no changes at all: "Changes noted from Oct 21. None since."
  - the same in the Routine tab (`RoutineView.swift:451`)

### C3. "A few months of made-up data"
- `DermView.swift:32`, and the comment at `ReportView.swift:11`. The sample has 23 days of routine.
- Use "The sample uses made-up data."

### C4. "Missed" and "Irritated skin" claim more than the app knows
- A night that wasn't logged may still have been done. "Irritated" means the user tapped tight, red or stinging.
- In the legend, use "Skipped or not logged" and "Irritation logged".

### C5. The sample names a doctor
- The sample says "For the visit on … with Dr. Petrauskienė", and page 3 gives the same name as the clinic (`Presets.swift:178`, `:189`). It's a plausible real name, shown to a real Lithuanian dermatologist.
- In `ReportView(sample: true)`, clear `followUp.with` and each procedure's `clinic` on the sample's copy. The screenshots can keep them.

### C6. The score card's title
- "Your skin this week, overall" (`TodayCards.swift:116`) is a statement sitting above five buttons.
- Use "How’s your skin this week, overall?"

---

## Polish

### P1. Score labels collide
- The first label runs 80 pt to the right of the first point, and the last label runs 80 pt to the left of the last point (`TimelineStrip.swift:153-156`). In a 14-week strip, two scores a week apart are 34 pt apart, so the labels overlap.
- Skip the first label when `x(last) - x(first) < 90`.

### P2. Change lines used as `ForEach` ids
- `ForEach(c.lines, id: \.self)` at `RoutineView.swift:434` and `ReportView.swift:397`. Two products with the same name give identical lines, so the ids repeat.
- Use offsets.

### P3. Change numbers differ between Progress and the report
- Progress numbers changes from 1 within its 8 weeks, and the report within its 14. The same change can be 1 in one and 3 in the other.
- Number from the start of the log, then filter.

### P4. Moving a product into a new body routine loses the evening line (probe)
- The log reads only "Back routine started: Tretinoin". Nothing says tretinoin left the evening.
- In the "routine started" branch, still report products that left another routine: "Tretinoin: moved from evening".

### P5. The weekly score card can't be put off
- It shows every day until it's answered. Add "Not now", which hides it until tomorrow.

### P6. The sample's first open blocks the main thread (not device-verified)
- `render()` runs on the main actor. On the first open it draws 5 demo photos at 900×1200, then renders 3 pages twice. The spinner freezes meanwhile.
- Draw the photos in a detached task first. They're cached after that.
- `DemoPhotos.swift` still says the photos are "never shown outside `-demo`", which is no longer true.

### P7. Starting the log for an old save
- On the day an old save first opens with this build, the baseline is recorded at launch (`AppModel.swift:76`). Edits later that day replace it, so they're never logged.
- After a failed first load, `retryLoadIfNeeded` (`:111`) records no baseline. The first `update` records it after its own change, so a first change that edits the routine is swallowed into the baseline.
- Record the baseline in `retryLoadIfNeeded` too.

---

## Checked and fine
- Old saves:
  - `scores` and `history` are in `CodingKeys` and decode as lossy arrays.
  - One bad snapshot costs only itself.
  - Saves without either field load (tested).
- Combining a day's edits:
  - One entry per day. A day that undid itself leaves none, including after an earlier day's change.
  - Renaming a product and reordering steps aren't changes.
  - Typing the body routine's name replaces only today's snapshot.
  - The 200-snapshot and 600-score caps work.
- Change lines:
  - A move between morning and evening is reported once, in both directions.
  - Course ends and ease-in on/off are logged (tested).
  - A routine becoming several lines on resize is accurate ("every other night → 2 of every 3 nights").
- Ways the state gets replaced:
  - Restore: `update { $0 = s }` records against the backup's own history.
  - Erase: the blank state isn't onboarded, so nothing is recorded.
  - Onboarding: the baseline is recorded when it finishes.
  - Demo: never saved.
- Performance:
  - `recordPlan` runs on every update, and its cost grows only with the number of steps.
  - `PlanHistory.changes` is at most 200 diffs. It runs only in the Routine tab and the timeline.
  - `TreatmentTimeline.build` runs only in the Progress card and the report, never on Today.
  - Nothing heavy runs per keystroke.
- Timeline rules that hold:
  - Paused days show basics under a band.
  - Recovery nights show basics.
  - A body routine started later is blank before it starts: the anchor moves with its first product, and actives get a `from` date.
  - Days before the plan are blank.
  - Off days of a weekday routine are blank.
- The PDF path:
  - It uses plain `Shape`s and `Text`, with no `GeometryReader`.
  - The legend's `FlowLayout` gets a fixed width.
  - It uses fixed paper colours in light mode.
- Compiling, checked by reading:
  - `TimelineStrip`'s memberwise init stays internal alongside `private let rowH` (checked with `swiftc`).
  - Tuple key paths work in `ForEach(id: \.number)`.
  - `PlanChange` is `Identifiable`, and `Area` is `Identifiable` for `ForEach(areas)`.
  - `.accessibilityAddTraits(cond ? .isSelected : [])` type-checks.
  - The init order in `ReportData.init` after the `span` rename compiles; a reproducer was checked with `swiftc`.
