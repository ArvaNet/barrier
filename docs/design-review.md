# Barrier design review (iOS 26, iPhone 17 Pro)

Reviewed: all 39 shots in `design/all/`, `docs/design-spec.md`, the vault brand system, and the SwiftUI source.
Measurements come from the 1206×2622 shots (3 px = 1 pt), with pixel colors sampled directly.

**Read this first: the shots are older than the code.** The working tree has uncommitted design work that already fixes part of what the shots show:
- `Page` margin 20 → 16 (`RootView.swift:106`).
- Card radius 22 and stage radius 28 (`Styles.swift:14,30`).
- Fraunces large titles through the navigation bar (`Palette.swift:115`, `BarrierApp.swift`).
- Today and Progress use real navigation titles, with the gear as a toolbar item (`TodayView.swift:43`, `ProgressScreen.swift:33`).
- Hero title 36 → 30 (`Palette.swift:126`).
- Camera and photos permissions granted in CI (`ios.yml`). Shots 37–39 are hidden behind the camera alert.

Items marked **[in progress]** below are covered by that work. Recapture the shots before judging them done.

**The diagnosis in one line:** Barrier is built as two apps. Today and Progress are custom cards; Routine, Derm, Settings and every sheet are stock `List`/`Form`. They differ in margins, inner text line, surface colors, header style and accent use, so moving between tabs feels "sloppy" even where each screen is fine on its own.

---

## 1. System-level issues (ranked by impact)

### S1. Two surface systems: lists and sheets aren't on the brand palette
**What's wrong (sampled):**
- **Dusk.** Today cards are `#16211E` on `#0E1513`, the green-black dusk. Routine and Derm list sections are system **`#1C1C1E`**, a neutral gray, on that same green page (04, 16, 39). The Settings sheet is **`#1C1C1E` with `#2C2C2E` rows** (08), plain iOS dark gray. Inside the Rotation section, the night chips use `#1E2B27`, so one card mixes the two palettes.
- **Light.** Today cards are `#FAFBFA` with a hairline and a shadow. List rows are flat `#FFFFFF`. Every sheet is the stock bluish **`#F2F2F7`** (18, 26, 27, 31), not mineral `#EDF0ED`.
- **Medium-detent sheets are translucent Liquid Glass.** The clay Start button bleeds through as an orange smear behind the sheet content (28, 29), and the Routine list shows through the Pause sheet (30). It reads as a rendering bug.

**Why it matters:** dusk is supposed to be "designed, not inverted". Right now three of four tabs fall back to stock iOS dark gray, and switching tabs visibly changes the color temperature.

**Fix:**
- Add one modifier in `Styles.swift` and use it on every `List`/`Form`:
  ```swift
  func barrierList() -> some View {
      self.listStyle(.insetGrouped)
          .scrollContentBackground(.hidden)
          .background(Palette.bg.ignoresSafeArea())
  }
  ```
- Put `.listRowBackground(Palette.surface)` on every `Section` (it applies to all rows in the section). Files: `RoutineView.swift`, `DermView.swift`, `SettingsView.swift`, `StepEditorSheet.swift`, `ProcedureViews.swift`, `TodaySheets.swift`, `OnboardingView.swift`.
- Put `.presentationBackground(Palette.bg)` on every sheet. It's easiest inside `barrier(_:)` (`Styles.swift:296`). That ends the clay bleed and gives every sheet the brand page color.
- **One card language that matches the lists:** set `Palette.surface` light to `#FFFFFF` (`Palette.swift:33`, was `#FAFBFA`), and drop the card hairline and shadow (`Styles.swift:15–20`). Today cards then look exactly like the list sections on the other tabs.
- **Card radius.** iOS 26 inset-grouped sections measured about 24–25 pt in shots 10 and 06; cards are 22. Set the card radius to **24** so cards and lists are one shape family; the stage stays 28. Confirm the list radius in the view debugger first.

### S2. No shared content line: five outer margins and four card paddings
**What's wrong (measured):**
- **Outer margins in the shots:** Today 20, Progress 18, lists 16, ritual 22, onboarding 24. **[in progress]** `Page` is now 16.
- **The inner text line still varies.** Today rows sit at 30 pt from the screen edge, the tip card at 32, standard cards at 34, the hero at 36, and list rows at 32. Card padding is 14 (`TodayView.swift:357`, `TodayCards.swift:52,90`), 16 (`:468`), 18 (the `Styles.swift:7` default) or 20 (`TodayView.swift:99`, `Styles.swift:28`).
- In 01, the hero kicker, the procedure kicker and the row icons start on three different lines.

**Fix:**
- **Card padding 16, everywhere.** Change the `CardModifier` default to 16 and delete the per-call 14 and 18.
- **Hero padding: 16 horizontal, 20 vertical.** In `StageModifier` and `card(padding: 20)`, use `.padding(.horizontal, 16).padding(.vertical, 20)`.
- **Result:** all card and list text sits at **32 pt**, and all page-level text (large title, date kicker, onboarding titles) sits at **16 pt**. Two lines, app-wide.
- **Margins:**
  - 16 for tabs, sheets and all onboarding pages, including the welcome page. Change `OnboardingView.swift:95,131,142,189,234,281` from `padding(24)` to `.padding(.horizontal, 16)` plus vertical padding.
  - Ritual: 24, the one full-bleed exception. Change `RitualView.swift:63` from 22 to 24.
- **List rows that break the 32 line:**
  - Rotation chips: inset 12 → 16 (`RoutineView.swift:220`).
  - "Add a product" and "Add a procedure": the label text sits about 18 pt right of the item names (shots 06, 16). Give the plus a fixed-width frame equal to the leading column (10 pt in Routine, 44 pt in Derm) so the text aligns with the names above.
  - Onboarding page headers sit in list rows inset 4 (`OnboardingView.swift:181,202`). See S4.

### S3. Clay is everywhere because the whole app is tinted clay
**What's wrong:** `.tint(Palette.accent)` at the root (`RootView.swift:18`) and in `barrier()` (`Styles.swift:297`) turns roughly 30 controls clay:
- Every toolbar button (Edit, Done, Cancel, Save, Close, Share).
- Every toggle and menu picker value ("Time of day", "Sunday", "After shower", "Retinoid", "Every night", "Treatment").
- List text buttons: "Turn on reminders", "Export a backup", "Restore…", "Start over…", "Pause the plan…", "Remove", "Add a procedure", "Compare before and after".
- Selected tab, onboarding progress bar, the onboarding option icons and bell, the Not-tonight icons.

Explicit clay text also breaks the spec: the "Tonight" label on the rotation chip (`RoutineView.swift:208`), the procedure kicker when soon (`ProcedureViews.swift:512`), "Edit" on the skin card (`TodayCards.swift:185`), "Compare" (`ProgressScreen.swift:288`), and the PDF kickers, "NOW", bullets and "booked" (`ReportView.swift:388,427,481,586,615`).

**Why it matters:** clay is meant to mean "do this" and "treatment". At 30 uses per session it means nothing, and on 08 it reads as a link-colored settings page.

**Fix:**
- Root tint becomes ink: `.tint(Palette.ink)` in both places.
- Clay stays only on:
  - `PrimaryButtonStyle`, which already sets it explicitly.
  - The sheet confirm button (`.tint(Palette.accent)` on the `.confirmationAction` item).
  - Treatment marks: timeline bars and diamonds, the procedure outline on the calendar and week strip.
- Toggles use sage (`Palette.ok`): set `UISwitch.appearance().onTintColor` in `AppDelegate`, or apply `.tint(Palette.ok)` per `Toggle` if the root tint overrides it. Verify on device.
- **Selection is ink, never clay wash.** Chips, score tiles, onboarding options, photo selection border and the "tonight" rotation chip use an ink 1.5 pt border plus a check or ink text. `Palette.accentSoft` (`Palette.swift:42`) then has no use left; delete it. It is also the source of the beige "cream" fill on 32.
- The PDF uses Paper ink3 for kickers and bullets, ink2 semibold for "booked", and clay only for treatment marks.

### S4. Visible defects: the things that read as "sloppy" (all cheap)
1. **Onboarding text clipped:** the first letter of "report smarter." is cut off (34). The header sits inside a list row with a clear background, and the section's rounded-corner mask clips its bottom-left. Move page headers out of list rows: use a custom `Section { } header: { PageHeader(...) }` with `.textCase(nil)`, or put the header in `.safeAreaInset(edge: .top)`. Files: `OnboardingView.swift:174–182, 196–203`.
2. **Timeline label overprinted:** a photo marker sits inside the "Subcision" label, so it reads "Subcisi▢n" (05). Photos share the procedure lane (`TimelineStrip.swift:226–227`). Move any photo marker that falls inside a procedure label's span down to the change lane (`eventY`), or give labels a 2 pt `colors.surface` knockout background.
3. **Ritual progress doesn't show the current step:** on step 1 of 2, both dashes are `#4C5551` (03). `RitualView.swift:105` lights only finished steps. Light the current one too (`i <= p.index`), with finished steps at 50% opacity. Hide the dashes when there is only one step (17).
4. **Rotation chips have different heights:** "Tonight" adds a third line, so Night 1 floats in the middle of Night 2 (04, 10, 33). Give every chip a fixed `minHeight: 64` and top alignment, and show "Tonight" as an ink border plus ink2 caption rather than an extra clay line. `RoutineView.swift:198–213`.
5. **Onboarding list hard-cut:** the routine list stops dead at the Continue button, mid-row (33). Put the button in `.safeAreaInset(edge: .bottom)` with `.background(.bar)`; on iOS 26 use `.scrollEdgeEffectStyle(.soft, for: .bottom)`. `OnboardingView.swift:172–190`, same for `:194–235`.
6. **Developer copy shipped to users:** the Settings footer says "...until the App Group is set up in Xcode (see the README)" (08). Delete that branch (`SettingsView.swift:137`).
7. **Hourglass gap:** "⌛      20m" in Routine rows has a 29 pt gap (04, 10). `Label` inside a `List` gets the list's icon column. Replace it with `HStack(spacing: 3) { Image(systemName: "hourglass"); Text("20 min") }` (`RoutineView.swift:262`).
8. **Truncation:** "Cheeks and forehead ·…" on Derm (06). Allow 2 lines on the detail text (`ProcedureViews.swift:111`), and move the photo glyph under the date tile, or drop it.
9. **"Not great" crammed** into a 60 pt tile with `minimumScaleFactor` (22). See the Today section for the replacement.
10. **Mismatched hero buttons:** "…" uses a different fill (`primary.opacity(0.08)`) and a 48×52 size next to "Done" (`TodayView.swift:270–273`). Use `SecondaryButtonStyle` at a 52×52 square.
11. **Derm separators** start under the "NOV" text of the date tile, about 41 pt in, which is neither the tile nor the title (06). Add `.alignmentGuide(.listRowSeparatorLeading) { $0[.leading] + 56 }` on the row's HStack (`ProcedureViews.swift:107`). Same issue under the chips row on 31.
12. **Touch targets under 44 pt:** card dismiss buttons are 28×28 and 30×24 (`TodayCards.swift:279`, `ProcedureViews.swift:519`); calendar chevrons are 40×36 (`ProgressScreen.swift:167–170`). Keep the glyph size and set the frame to 44×44.

### S5. Cards have four anatomies
**What's wrong:**
- Kicker + Fraunces title (procedure, follow-up, journey).
- Title only (skin check, score).
- A 30 pt icon column with indented text (Photo night, Milestone, follow-up hint). This pushes the text to 66 pt and breaks the left line (11, 21, 22).
- Rows (compact routines).
- Card titles are 22 on some cards (follow-up, recap, procedure, reconcile) and 19 on siblings (journey, photo, milestone, skin), stacked one after another (11: "Week 4: the slow part" sits under "Follow-up in 19 days").

**Fix:** one card template.
- `Kicker` row, with an optional trailing 44 pt dismiss.
- Fraunces **22** title (`barrierH2`) on every card.
- Subheadline ink2 body.
- Content.
- Action row: `SecondaryButtonStyle(compact: true)` plus a tertiary text button. Spacing 8 between kicker and title, 12 between blocks.
- **No leading icon column on cards.** Move the icon into the kicker as a 12 pt glyph, or drop it. Only *rows* (compact routines, list rows) carry the 36 pt tinted circle.
- Shorten titles that crowd the line: "How's your skin this week, overall?" becomes kicker "Weekly check" plus title "Your skin overall?".

### S6. Type scale: too many display sizes
**What's wrong:**
- Fraunces is used at 19, 22, 30, 32, 34, 38, 40, 56 and 64 (`Typeface.display` calls in `RitualView.swift:130,301`, `OnboardingView.swift:79`, `ProgressScreen.swift:60`, `Visuals.swift:146`).
- Text smaller than 11 pt: the orbit's "/2" is 8.8 pt (`Visuals.swift:63`), the `DateTile` month is 10 pt (`ProcedureViews.swift:58`).

**Fix (five steps, as `Font` tokens in `Palette.swift`):**

| Token | Fraunces | Use |
|---|---|---|
| `barrierNumeral` | 56 / 380 | big numbers only: timer, Progress count |
| `barrierLargeTitle` | 34 / 430 | nav large titles, onboarding page titles (30 → 34), welcome headline (38 → 34), ritual step name (40 → 34), finish title (32 → 34) |
| `barrierDisplay` | 30 / 430 | the Tonight hero title only **[in progress]** |
| `barrierH2` | 22 / 480 | every card title, wait-screen line |
| `barrierH3` | 19 / 500 | calendar month, date-tile numerals only |

- Floor of 11 pt anywhere in the app UI. The PDF has its own scale.
- Remove the orbit count in the hero. The subtitle already says "Night 2 of 2", and the count is the only text below 9 pt.
- At 34 pt, the welcome headline breaks as "Your dermatologist's / routine, remembered." instead of four ragged lines with "Your" alone on the first (09).

### S7. Today is a feed, not "calm certainty"
**What's wrong:** Today can stack up to 14 cards (`TodayView.swift:14–41`). The shots show 12: hero, 2 routine rows, procedure, week, milestone, skin check, weekly score, journey, photo night, follow-up, tip. An anxious first-week user scrolls three screens to see everything.

**Fix (cap at 6, in this order):**
1. Reconcile or pause banner, if any.
2. **Hero.**
3. **"Also today"**: one card holding the other routines as 56 pt rows with an inset divider, instead of one card per routine (01, 02).
4. Procedure aftercare, while active.
5. Week strip.
6. **Check-in**: skin today, merged with the weekly score on its day.
7. **One** "for you" card, picked by priority: follow-up within 3 days, then photo night, then milestone, then journey, then tip.

Everything else lives on Derm or Progress.

### S8. Dusk mode quality
- **Dusk clay fails contrast:** the white label on `#C2673F` is **3.90:1**, below AA for 17 pt semibold. Set dusk accent and `stageAccent` to **`#B35B36`**: 4.63:1 for the label, still 3.7:1 against the stage (`Palette.swift:41,54`).
- **The hero recedes in dusk:** the stage `#131D1A` is *darker* than the other cards (`#16211E`), so Tonight looks like the least important card (01). Make the card stage dynamic: light `#131D1A`, dark `#1B2824` (`Palette.stage2` already exists). Keep `#131D1A` as the ritual full-screen background.
- **Low-contrast tertiary text:** `.tertiary` on the ritual is about **2.45:1** ("You can lock your phone…", 13). Use `Palette.stageInk2` (7.9:1) (`RitualView.swift:188`).
- **Light `ink3` on `surface2`** is 4.17:1, which fails AA for small text in tinted cards. Set `ink3` light to `#56635E`: 5.1:1 on surface2 (`Palette.swift:38`).
- Covered in S1: gray lists and sheets in dusk.

### S9. Blur glows are the decoration the brand bans
**What's wrong:** blurred hue circles behind:
- The morning sun (`TodayView.swift:174`). In 02 it reads as a peach smudge.
- The current orbit node (`Visuals.swift:38–43`).
- The whole ritual screen (`RitualView.swift:37–46`).
- The finish check (`RitualView.swift:292`).

They're the "AI glow" look and the "blobs as decoration" the brand rules out.

**Fix:**
- Replace each with a **crisp halo**: `Circle().stroke(hue.opacity(0.35), lineWidth: 1.5)` at 1.7× the node diameter. Keep the existing slow breathe on the node, not the halo.
- Delete the ritual ambient glow. The flat `#131D1A` stage is calmer.
- Morning hero: a crisp 44 pt circle (hue at 25% plus a `sun.max.fill` symbol in `hueInk`), the same language as the 36 pt row circles.

### S10. Buttons, chips and the "skip" slot
- **Radius tokens: 14 / 12 / 10.**
  - 14: 52 pt buttons.
  - 12: 40 pt compact buttons, which are 11 now (`Styles.swift:105`, spec says 12), and chips, also 11 now (`Styles.swift:143–144`).
  - 10: tiles inside cards (date tiles, photo thumbs, calendar today, score tiles).
- **Ritual skip actions live in three places:** a right-aligned tertiary (03, 17), a centered secondary button (13), and "Back" bottom-left. Use one bottom slot of fixed height: primary (52) + 10 + a tertiary row (44) with Back on the left (only from step 2) and Skip on the right. On the wait screen the primary slot shows the timer's "Skip the wait" as **tertiary** in the same row, so nothing jumps between steps.
- **Copy:** "Done, finish" → "Done"; "Skip and finish" → "Skip".

### S11. Native chrome on iOS 26
- **Onboarding** uses a custom chevron and progress bar inset 12 (`OnboardingView.swift:20–33`), so the glyph sits around 29 pt, off every line. Wrap onboarding in a `NavigationStack`, use the system back button (Liquid Glass) and `ToolbarItem(placement: .principal) { ProgressView(...).tint(Palette.ink).frame(width: 180) }`.
- **Ritual close:** the X glyph sits at about 37 pt, while content starts at 22 (03). Make it a 44 pt circular button whose circle edge sits on the 24 pt line. On iOS 26 use `.buttonStyle(.glass)`; earlier versions use an `.ultraThinMaterial` circle.
- **Routine's segmented control** sits in its own section with about 45 pt of dead space before the first card (04, 10). Add `.listSectionSpacing(.compact)` (iOS 17).
- **Sheets:** top gap of about 44 pt before the first section (29). Add `.contentMargins(.top, 8, for: .scrollContent)`.
- **Nice native touch:** on iOS 26, `.tabBarMinimizeBehavior(.onScrollDown)` for Today and Progress, inside `#available`.
- Leave the system glass capsules (toolbar, tab bar) alone. They are OS chrome, not brand buttons, so the no-pill rule doesn't apply to them.

### S12. Icons
- **Progress tab:** `circle.circle` reads as a record button or target (`RootView.swift:83`). Use `chart.line.uptrend.xyaxis`.
- **Milestones:** gold `sparkles` (21) is the generic AI glyph. Use no icon, with a 44 pt mini `RingsView` trailing instead (see impress item 2).
- **Body routine:** `figure.stand` (a stick person) for "Back" (`Styles.swift:309,318`). When the cue mentions a shower, use `shower`; otherwise use `drop.halffull`.
- **Clay-tinted icons** in onboarding options, Not-tonight rows and the reminders bell become ink2. A selected onboarding option shows an ink check, and its icon stays ink2.
- **Source links:** underlined web-style links (11, 22, 24) become footnote ink3 text with a trailing `arrow.up.right` at 9 pt and no underline (`Styles.swift:215–218`).
- **Hues:** add the extra hues to the spec so they stop looking accidental. lilac = body routine, rose = treatment products, dawn = morning (`Palette.swift:62–64`).

---

## 2. Screen by screen

### Today, Tonight hero (01, 02, 15)
- **Good:** the dusk stage as the night's hero; kicker plus Fraunces title; numbered steps with treatment dots; one clay Start. Keep.
- **Title and orbit fight for width:** "Recovery night" and "Morning routine" wrap in the shots. **[in progress]** The 30 pt display fixes the default size.
- **Subtitle wraps:** it sits in the column next to the orbit, giving "Night 2 of 2 · easing in, / week 4". Move the subtitle *below* the HStack so it spans the full width (`TodayView.swift:111–124`).
- **Orbit:** 104 → 88 pt, `showCount: false`, crisp halo (S9), top aligned with the kicker.
- **Treatment dot misaligns text:** "Azelaic acid 15%" is indented by its dot (02). Give every step a fixed 10 pt dot column, empty for basics (`TodayView.swift:203–205`).
- **Button row:** Start (flexible) + Done (secondary, fixed width 92) + "…" (secondary, 52×52 square), all 52 tall.
- **Hero padding:** 16 horizontal, 20 vertical (S2).

### Today, the rest (11, 21, 22)
- **Good:** the week strip (21). Hue outlines for planned nights, hue-filled checks for done ones, the today tile and "Tomorrow: retinoid night" are clear and on brand. Keep it, and change the tinted padding 14 → 16.
- **Compact routine rows** become one "Also today" card (S7). The rows already have the right icon circle; keep that.
- **Procedure card (21):** good content. The clinic note bar is a muted clay (treatment), which is correct. "Details" alone on a row looks orphaned; make it a tertiary "Details ›" in the kicker row and remove the button row when it has nothing else in it.
- **Weekly score (22):** replace the five word-chips with five equal tiles showing Fraunces 19 numerals 1–5, and one caption row under them reading "Rough" on the left and "Great" on the right (caption, ink3). The selected tile gets an ink fill with surface text, and the chosen word appears in the subtitle ("Logged: Good"). This holds at every Dynamic Type size (`TodayCards.swift:140–162`).
- **Skin today:** selected chip = ink border plus ink text, not a clay wash. "Edit" becomes ink.
- **Photo night, Milestone, follow-up hint:** remove the icon column (S5).
- **Tip card:** source link style per S12.

### Ritual (03, 13, 14, 17)
- **Good:**
  - Fraunces step name, the "Your dermatologist" quote with a hue bar (17), the timer typography with `monospacedDigit` and the numeric transition (13).
  - Haptics, Live Activity, and the "lock your phone" promise.
  - The finish copy ("22 nights so far.").
- **Step layout (03):** content is vertically centered, leaving about 250 pt of void above it and the eye sitting low. Anchor it: top spacer 1, bottom spacer 2 (`Spacer().frame(maxHeight: .infinity)` weighted with `layoutPriority`, or a `GeometryReader` offset at 30% of the height). Add a quiet line above the bottom slot: "Next: Moisturizer" (footnote, stageInk2).
- **Redundant line (17):** "Thin layer on affected areas" and the dermatologist note say the same thing. When `product.note` exists, hide `step.amount`.
- **One step (17):** hide the progress dashes, and make the kicker "BACK" rather than "BACK · STEP 1 OF 1".
- **Wait (13):**
  - Ring track `primary.opacity(0.12)` is barely visible at 4 pt; raise it to 0.18.
  - "Skip the wait" becomes tertiary in the fixed bottom slot (S10).
  - Hint text color per S8.
- **Finish (14):**
  - With only two nodes, the orbit is a near-empty circle. Show the node labels as caption text beside each node ("Retinoid", "Recovery").
  - Fill the finished node with a checkmark as the ring turns.
  - Add a "Tomorrow" row (hue dot + "Retinoid night · 9:30 PM") above the button.
  - Delete the glow (S9).

### Routine (04, 10, 16, 24, 39)
- **Good:** native inset list, the segmented Evening/Morning/Back control, the History section (great for the report), and the Breaks section with plain-language footers.
- **Surfaces in dusk:** S1. This is the biggest visual fix on this tab.
- **Rotation row:** the explanation wraps beside the stepper, which is cramped. Keep only "Every night, easing in" plus the stepper in the row, and move "Recovery nights are added… Tap a night to make it tonight." to the section **footer**.
- **Chips:** equal height, inset 16, ink "Tonight" (S4, S3).
- **Step rows:** the hollow circle for basic steps reads as an unticked checkbox that invites a tap (`RoutineView.swift:254`). Leave the 10 pt column empty for basics.
- **"Add a product":** the clay `plus.circle.fill` becomes an ink `plus` in the 10 pt column (S2), so the text aligns with the step names.
- **"Remove" on a break (24):** clay text becomes `role: .destructive` (red), or swipe-to-delete with the trailing button dropped. "Start over from a template…" becomes ink, because it is destructive-adjacent and not a primary action.
- **Footer links (24):** three underlined links wrapping to two lines. Apply S12.
- **Body section (16):** "For: Back" is a text field that looks like a static value. Add a `pencil` glyph in ink3, or move the name into the toggle row ("Back routine" with a rename option in a menu).

### Progress (05, 12, 37)
- **Good:** the skin log (12) is clean, scannable, and red only for irritation, exactly per spec. Photo grid, before/after pairing and the timeline idea are dermatologist-grade.
- **Summary card:** "21 nights done" plus a right-aligned stack repeating "21 of 23…" is redundant and leaves the card's center empty. Replace it with the rings hero (impress item 2), or at least a left-aligned row of three stats: value in title3 semibold with monospaced digits, label in footnote ink3, 1 pt dividers between.
- **Timeline legend:** 11 items over 4 wrapped rows at 11 pt. In the app, replace it with an `info.circle` "How to read" button in the card header that opens a `.medium` sheet. Keep the full legend in the PDF.
- **Label collision:** S4.2.
- **Numbered change markers:** black 13 pt circles with 8 pt digits. Fine as a chart key, but the digits are under the floor: use 15 pt markers with 10 pt digits (`ProgressScreen.swift:111–115`).
- **"By night":** fixed widths of 150 for the label and 120 for the bar (`ProgressScreen.swift:433,436`), and it repeats the rings data. Remove it from the app; the report already prints it.
- **Card order:**
  1. Rings/summary
  2. Photos (the most emotional content)
  3. Timeline
  4. Calendar
  5. Skin log
- **Card spacing:** `Page(spacing: 16)` vs Today's 12. Use **16 on both.** 12 pt gaps between 24 pt-radius cards look crowded.
- **37:** recapture. The alert hides it.

### Derm (06, 38)
- **Good:** the date tiles (Fraunces numeral, month kicker), the questions list with tick-off, "Your dermatologist's words".
- **Title:** **[in progress]** Fraunces large title. The system SF Bold "Dermatologist" in 06 is the only tab with that look today.
- **Hierarchy:** the report, the thing that impresses the dermatologist, is a list row below questions and notes. Make it the tab's hero (impress item 1).
- **Next visit:** the "In 19 days…" note sits as a row with a separator above it. Move it to the section footer.
- **Procedure rows:** separators (S4.11) and truncation (S4.8). The upcoming tile's clay wash looks muddy in dusk (38). Keep the tile on `surface2` and keep the month in clay; a procedure is a treatment mark, so clay is allowed there.
- **"Add a procedure"** text alignment (S2).

### Report (07, 20, 23, 25)
- **Good:** this is the strongest asset.
  - The two-column layout and the dated timeline with legend.
  - "Overall skin, rated weekly by the patient", the routine change log, procedures plus photos with "4 weeks after Chemical peel".
  - The "Not a medical record" footer.
  - Keep the structure.
- **Preview frame:** pages sit about 2 pt from the screen edge. Render them as paper: 16 pt margins, 4 pt corner radius, `shadow(color: .black.opacity(0.08), radius: 8, y: 2)` on a `surface2` backdrop, and 16 pt between pages. Add "Page 1 of 3" to each page footer.
- **Caption:** the bottom caption repeats the footer and covers page content (07, 23). Drop "Not a medical record" (already printed on every page) and keep "Pinch to zoom" for the first 3 seconds only.
- **Clay in the PDF:** S3.
- **Readability:** the timeline at 7.5 pt is the smallest text on paper. Use 8.5 pt and let the chart take the spare height. Page 1 has about 25% blank space at the bottom (07).

### Settings (08)
- **Fix:** surfaces (S1), tint (S3), dev copy (S4.6).
- **Section rhythm:** spacing looks uneven because some sections have footers and some don't. Give "Appearance" a footer ("Time of day switches to dusk at 6 PM.") so every section has one and the rhythm evens out.

### Onboarding (09, 32, 33, 34, 35)
- **Good:** the welcome promise and copy; "Everything stays on your iPhone."; the reminders page explains long-press actions.
- **Welcome (09):**
  - Headline 34 (S6).
  - The stage is a dark box with a small orbit; impress item 7 fixes it.
  - Stage radius 30 → 28 (`OnboardingView.swift:76`).
- **Options (32):** the selected card is a beige clay wash, which breaks the no-cream rule. Use a surface fill + 1.5 pt ink border + ink `checkmark.circle.fill`. Unselected cards get no border. Icons ink2.
- **33 / 34:** header clipping (S4.1), list hard-cut (S4.5). Title positions are 21 pt here vs 24 pt on 32 and 35. S2 makes them all 16.
- **34:** the long gray section header "If your skin gets irritated, your dermatologist said…" becomes header "If your skin gets irritated" with placeholder "What your dermatologist said, e.g. skip tretinoin for 2 nights".
- **35:** content is vertically centered under about 400 pt of empty top space. Top-align it under the nav bar with 24 pt spacing. Bell icon ink2, not clay.

### Sheets
- **Step editor (26):** fine and native once on brand surfaces.
  - Move "Your dermatologist's instructions" directly under Product. It is the field that makes Barrier trustworthy, and today it is the third section.
  - "Started on" toggle sage.
- **Add product (27):** the disabled "Add" row looks like placeholder text. Hide it until a name is typed, then show `Label("Add \(name)", systemImage: "plus")` as an ink row. The treatment dots on the common chips are rose; add rose to the spec as "treatment".
- **Day detail (28):** clay bleed (S1). Steps show no done state: tick the logged steps with an ink `checkmark` trailing. "Clear what was logged" stays red.
- **Not tonight (29):** bleed (S1), top gap (S11), clay icons become ink2. "Your dermatologist said" is good; keep it.
- **Pause (30):**
  - The explanation is a gray "card" made from a section of text rows. Make it a real section footer.
  - "Why" picker in ink matches once the tint is ink.
- **Procedure (18, 31):**
  - Photos section is good.
  - The list icon on the name row (clay) is an unclear affordance. Remove it on existing procedures and keep the chips for new ones.
  - Separator under the chips (S4.11).
- **Compare (19):** good, native. The lower 45% of the sheet is empty. Add a strip of the area's other photos underneath (60 pt thumbs, horizontal scroll) to swap the "after" photo.
- **Camera (36):** permission alert only. The ghost overlay with an opacity slider already exists (`CameraScreen.swift:46`), which is the right call. Recapture.

---

## 3. "Impress" upgrades (max 8, ranked)

1. **Derm hero: "Report ready".**
   - First card on Derm: kicker "For Nov 9 · Dr. Petrauskienė", title Fraunces 22 "Your visit report".
   - A live thumbnail of page 1 (the timeline). It is already a SwiftUI view: render `ReportSummaryPage` (`ReportView.swift:416`) at 0.42 scale, clipped to 16:10, in a 10 pt-radius frame.
   - Primary clay "Share report" plus tertiary "Preview".
   - When no visit is booked, the same card says "Book a follow-up and Barrier prepares this for it."
   - It shows the dermatologist-facing value in one look.
2. **Progress hero = the growth rings.**
   - `RingsView` at 220 pt, centered, with "21" in Fraunces 56 inside the inner circle and "nights" (footnote ink3) under it.
   - The three stats row beneath.
   - On appear, rings draw outward one by one (`trim` 0→1, 0.25 s stagger, off under Reduce Motion).
   - It turns the signature visual into the face of the tab.
3. **Tonight card as an object.**
   - Hero layout fixes (Section 2).
   - When the routine is marked done, the card cross-fades to its done state: the current orbit node fills, a check draws in (`.symbolEffect(.bounce)` is too playful; use `.contentTransition(.symbolEffect(.replace))`), and the orbit turns one step with the existing spring.
   - One success haptic.
   - It makes "done" feel done without leaving Today.
4. **Ritual focus layout.** The anchored step layout, "Next:" line, one bottom slot and a lit progress current step (S4.3, S10, Section 2). Add a 0.3 s `matchedGeometryEffect` on the active dash between steps. Calm, precise, and it never jumps.
5. **Bedtime dim on the wait screen.**
   - After 8 s without a touch, overlay `Color.black.opacity(0.55)` with a 1.2 s ease. The ring and numerals stay readable, and the screen stops lighting the bathroom at 10 pm.
   - Any tap restores it.
   - `isIdleTimerDisabled` is already set, so this also saves battery.
6. **Finish moment with tomorrow.**
   - The ring turns (exists) and the done node gets a check.
   - Below the title, one row: hue dot + "Tomorrow · Retinoid night · 9:30 PM".
   - "Calm certainty" made literal: you leave knowing exactly what's next.
7. **Welcome orbit with meaning.**
   - The stage fills the top half (radius 28, 16 pt margins).
   - The orbit at 200 pt with caption labels by each node ("Retinoid", "Recovery", "Recovery").
   - The brand's 700 ms first-load settle: the ring advances one node and locks "Tonight" at the top. Then the 60 s ambient rotation, with nodes counter-rotating to stay upright. Static under Reduce Motion.
   - This is the signature from the brand doc that the app hasn't built yet.
8. **Day-one states that look intentional.**
   - Today hero: "Night 1" with the orbit at its first node.
   - Progress: a single dashed ring with "Your first ring starts tonight" *inside* it, instead of a line of text.
   - Photos: one 3:4 dashed tile labeled "Your before" with a camera glyph, which opens the camera.
   - Week strip: future nights already hue-outlined.
   - No screen ever opens to an empty card.

---

**Before you build:** recapture `design/all/` from the current working tree. A third of what the shots show is already addressed there, and 37–39 need the camera alert gone.
