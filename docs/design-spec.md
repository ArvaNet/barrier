# Barrier design spec (native iOS)

The app version of the Barrier design system (vault: Projects/Barrier-DESIGN.md), held to
Apple's Human Interface Guidelines. Native first; the brand lives in a few deliberate places.

**The memorable thing:** calm certainty. Someone finally tells you what to do tonight.
**Never:** cream page backgrounds, italic accent words, 01/02/03 labels, monospace styling,
pill-shaped buttons, gradients or blobs as decoration.

## Where the brand lives
- Fraunces (display serif) for titles and the one big number or word on a card.
- Clay (#A6512E light, #C2673F dusk) for the one action per view that matters, and for treatment.
- The dusk stage (#131D1A) for the night: the Tonight card and the guided routine.
- Cycle hues mean their night, never decoration.
Everything else is plain iOS: SF for UI text, system navigation, lists, sheets, materials, SF Symbols.

## Layout
- **Side margin: 16 pt**, the same as an inset-grouped list on iPhone, so every tab's
  content starts on the same line.
- Spacing scale: 4, 8, 12, 16, 24, 32. Between cards 12. Before a section header 24.
- Card padding 16. Hero card (Tonight / This morning) 20.
- Touch targets at least 44x44 pt.
- One column. Text never runs edge to edge under the 16 pt margin.

## Navigation and page headers
- Every tab root uses the system large title, set in Fraunces (34 pt, Dynamic Type),
  collapsing to the system inline title on scroll. Toolbar buttons (Settings, Edit) are
  standard toolbar items in the top right.
- Today's large title is the greeting; the date sits above the first card as a kicker.
- Sheets use inline titles, Cancel left, the confirming action right (Save, Done).

## Type
| Role | Font | Size | Notes |
|---|---|---|---|
| Large title | Fraunces 430 | 34 | tab roots, via the navigation bar |
| Display | Fraunces 430 | 30 | hero card title (fits "Recovery night" on one line) |
| Title 2 | Fraunces 480 | 22 | card titles |
| Title 3 | Fraunces 500 | 19 | small card titles |
| Body | SF | 17 | |
| Subheadline | SF | 15 | secondary lines |
| Footnote | SF | 13 | captions, card notes |
| Kicker | SF semibold, tracked 1.1, uppercase | 12 | context above a title only |
All sizes scale with Dynamic Type. Numbers that change use monospaced digits (not a monospace font).

## Color (tokens in Shared/Palette.swift)
- Page background: mineral porcelain #EDF0ED / dusk #0E1513. Surfaces one step lighter.
- Text: ink, ink2 (secondary), ink3 (tertiary, at least 4.5:1 for text under 18 pt).
- Clay is for the primary action and for treatment marks. Never for decoration or text links
  other than an action.
- Danger red only for destructive actions and logged irritation.
- Dusk mode is designed, not inverted: the same hues on redesigned surfaces.

## Components
- **Card:** surface fill, 22 pt continuous corners, 1 pt hairline in light mode, a very soft
  shadow. Tinted card (surface2, no border) for secondary information (week strip, banners).
- **Stage:** the dusk card, 28 pt corners.
- **Buttons:** Primary (clay fill, white label, 52 tall, 14 pt corners). Secondary (surface2
  fill, ink label). Compact (40 tall, 12 pt corners). Tertiary: text only, subheadline
  medium, ink3, for "Not now", "Undo", "Skip". Rounded rectangles, never capsules.
- **Section header on scroll pages:** kicker style, 24 pt above, 8 pt below, aligned to the
  16 pt margin.
- **Rows:** 44 pt minimum, leading icon in a 36 pt circle tinted with its hue at 25%.
- **Empty states:** one sentence that says what will appear and how, in footnote ink3,
  never a blank card.

## Motion
- Nothing bounces. Springs only for toasts and sheet content (response 0.35, damping 0.9).
- The orbit turns slowly where it is decorative (onboarding); never under Reduce Motion.
- Content changes cross-fade; numbers use the numeric text transition.

## Accessibility
- Dynamic Type everywhere; layouts reflow, nothing truncates important text at AX sizes.
- Every icon-only button has a label. Charts have a spoken summary.
- Color is never the only signal (shapes, labels, or text carry meaning too).
