# Routine codes, version 1

A clinic can hand over a routine as a QR code. The patient scans it in Tendwell, checks it against the paper sheet, and uses it.

The code carries the routine and nothing else. No patient name, no dates, no clinic records. Nothing is stored on a server: the whole routine is inside the code.

The app's side lives in `Packages/BarrierCore/Sources/BarrierCore/PlanCode.swift`. The clinic pilot page lives in `tools/codes/`.

## Two promises

1. **Printed codes keep working.** A sheet can sit on a fridge for years. Version 1 never changes meaning. Any change to the format, however small, gets a new version number, and the app keeps reading version 1. (Before any code was printed, version 1 was settled once more: starting slowly moved from the routine to each product, the step key `b` in place of the routine key `e`, and `body2` was added.)
2. **A code never carries anything about a patient.** No name, no birth date, no visit date, no record number. The format has no field for them, and an unknown field makes the whole code invalid.

## Who can make a code

Anyone. A code is not signed, and the clinic name inside it is plain text. That is why the app never loads a code silently: the patient always sees the routine in words first and checks it against the paper sheet. If they differ, the sheet is right.

## The link

```
barrier://plan/<payload>
```

- The payload is the routine as compact JSON, encoded as UTF-8, then base64url without padding (`-` and `_` in place of `+` and `/`, no `=`).
- The prefix is read without regard to case, and spaces or line breaks around the text are ignored.
- A web link can carry the same payload after `#plan/`, for example `https://example.com/c#plan/<payload>`. The part after `#` never reaches a server.
- The payload is at most 2,600 characters. A QR code holds 2,953 bytes at most.
- Writers sort keys and leave out empty values, so the same routine always gives the same link.

Printing: the pilot page uses error correction M and byte mode. Up to about 1,000 bytes, a code printed 5 cm wide scans comfortably. Print a longer one larger.

## Keys

All keys are short to keep the code small. Text is trimmed. Empty text counts as absent. Limits count characters as a reader sees them.

### Top level

| Key | Type | Limit | Meaning |
|---|---|---|---|
| `v` | whole number | must be 1 | Format version. Required. |
| `c` | text | 60 | Clinic name, shown as "From …". Optional. |
| `p` | list of products | 1 to 24 | Every product the routines use. Required. |
| `am` | routine | | The morning routine. Optional. |
| `pm` | routine | | The evening routine. Optional. |
| `body` | routine | | A body routine (back, chest). Optional. |
| `body2` | routine | | A second body routine at another moment, same shape and rules as `body`. Optional. |
| `i` | text, line breaks allowed | 280 | What to do if the skin gets irritated, in the prescriber's words. Optional. |

At least one of `pm`, `am`, `body` and `body2` is required. The app shows them evening first: `pm`, `am`, `body`, `body2`.

### Product

| Key | Type | Limit | Meaning |
|---|---|---|---|
| `n` | text | 80 | Name, as on the label. Required. |
| `k` | text | one of the kinds below | Kind. Required. |
| `o` | text, line breaks allowed | 280 | The prescriber's note about this product. Optional. |
| `d` | whole number | 1 to 730 | A course: this many days from day 1, then it stops. Optional. |

Kinds: `cleanser`, `retinoid`, `exfoliant`, `treatment`, `serum`, `moisturizer`, `spf`, `oral`, `other`. Retinoid, exfoliant and treatment are the actives.

### Routine

| Key | Type | Limit | Meaning |
|---|---|---|---|
| `l` | whole number | 1 to 12 | Rotation length: the routine repeats every this many days. Leave it out for 1. |
| `s` | list of steps | 1 to 16 | The steps, in the order they are done. Required. |
| `n` | text | 24 | Name of a body routine, such as "Back". `body` and `body2` only, required there. |
| `q` | text | 40 | A moment for a body routine, such as "After shower". `body` and `body2` only. |

### Step

| Key | Type | Limit | Meaning |
|---|---|---|---|
| `p` | whole number | | The product, by its place in `p`, counting from 0. Required. |
| `a` | text | 120 | Amount, such as "Pea-size for the whole face". |
| `h` | text, line breaks allowed | 200 | How to apply it. |
| `w` | whole number | 1 to 120 | Minutes to wait after this step. |
| `n` | list of whole numbers | positions 0 to `l` - 1 | On these days of the rotation only. |
| `d` | list of whole numbers | 0 to 6, Sunday is 0 | On these weekdays only. |
| `b` | list of `[every, days]` | 1 to 4 stages | Start slowly: the stages before the step's own schedule, slowest first. See below. |

A step with neither `n` nor `d` happens every time.

### Starting slowly

`b` starts one product slowly, the way the app's step editor does ("Start slowly"). Each stage is `[every, days]`: `[3, 14]` is every 3rd time for two weeks. The step's own schedule (every time, or every Nth time through `n`) is the goal it builds up to. For example `{"p": 1, "b": [[3, 14], [2, 14]]}` is every 3rd night for two weeks, then every other night for two weeks, then every night.

Stage 1 starts on day 1. Tendwell asks the patient before each move up, when a stage's weeks are up, and never moves on its own.

The limits are exactly what the step editor lets a person set, so a loaded routine can always be opened and edited in the app:

| Limit | Where it comes from |
|---|---|
| Only a retinoid, exfoliant or treatment starts slowly. | `canBuildUp`: `product.kind.isActive` (`Barrier/Screens/Routine/StepEditorSheet.swift:187`) |
| The goal is every time or every Nth time (`n` evenly spaced), never weekdays or picked days. | `canBuildUp` needs an "every" schedule (`StepEditorSheet.swift:186`, read at `:167`); the goal is `Engine.every(of:)` as `startBuildUp` reads it (`Packages/BarrierCore/Sources/BarrierCore/BuildUp.swift:207`) |
| A stage is every 2nd, 3rd or 4th time, and less often than the goal. | The stage menu offers `[4, 3, 2].filter { $0 > goal }` (`StepEditorSheet.swift:431`); saving keeps only stages slower than the goal (`:266`) |
| A stage lasts 1 to 8 whole weeks: `days` is 7, 14, … 56. | The length menu offers 1 to 8 weeks (`StepEditorSheet.swift:448`) and stores weeks × 7 days (`:446`) |
| 1 to 4 stages. | "Add a slower stage" shows while there are fewer than 4 (`StepEditorSheet.swift:371`); a build-up with no stage isn't saved (`:234`) |
| Slowest first: no stage is more often than the one after it. | `BuildUp.stages` is "slowest first" (`BuildUp.swift:25`); "Add a slower stage" puts the new one first (`StepEditorSheet.swift:374`). The editor's menus would allow another order; the format doesn't. |
| Any routine: evening, morning and both body routines. | The step editor offers it on every routine (`StepEditorSheet.swift:104`, `BuildUpSection(slot: target.slot)`) |
| The two body routines may share a product; face and body never do. | The add sheet offers the other body routine's products (`StepEditorSheet.swift:479`) |
| The first stage fits the rotation (at most 12). | `startBuildUp` places it with `lineUp` and `Engine.setEvery`, which refuses a rotation over `Engine.maxRotation` (`BuildUp.swift:177`, `Engine.swift:417`, `:434`) |

## Rules

The app refuses a code that breaks any rule, whole. Half a routine is worse than none.

- The version is 1. A higher version asks the patient to update the app.
- No key outside the lists above, at any level. An unknown key could be an instruction this version would silently drop.
- Every value has the type above. Text is text, numbers are whole numbers.
- The kind is one of the nine kinds.
- No text has control characters or characters that change reading direction. Only the notes, the how-to and the irritation note may have line breaks.
- No text is longer than its limit.
- Every product has a name.
- There are 1 to 24 products.
- There is at least one routine.
- Each routine has 1 to 16 steps and a rotation of 1 to 12.
- Each step names a product that exists.
- A product appears at most once in a routine.
- Rotation positions are not empty, not repeated, and each is below the rotation length.
- Weekdays are not empty, not repeated, and each is 0 to 6.
- A step has rotation positions or weekdays, never both.
- A wait is 1 to 120 minutes.
- A course is 1 to 730 days.
- Starting slowly follows the limits in the table above. A stage is a pair `[every, days]`, and `b` is never empty.
- Every build-up fits its rotation. The app proves it by placing each one, in step order, the way loading does. If one doesn't fit, the whole code is refused, so a code never loads halfway.
- Only `body` and `body2` have a name or a cue, and each needs a name.
- Every product is used by at least one step.
- A product is used in the face routines or in the body routines, never both. The two body routines may share one.
- The payload fits in 2,600 characters.

The app also simplifies what means the same thing. Text is trimmed. A step on every rotation position happens every time. A rotation no step uses becomes a length of 1. Positions and weekdays are sorted. Two codes that mean the same thing load the same.

## What loading does on the phone

The patient first sees the whole routine in words, with "If anything differs from the sheet your clinic gave you, follow the sheet." Nothing changes until they choose to use it.

- Only the routines in the code are replaced. A code with only the evening leaves the morning and the body routines as they were.
- Day 1 is the day the code is loaded. If that routine is already logged for today, day 1 is tomorrow, so no step of the new routine is skipped.
- A course counts from day 1.
- A build-up starts on day 1 with no moves: the first stage's schedule from then on. In a fresh app the product is due on day 1. When the patient's own log shows that routine with a treatment recently (the same product's step, or an evening logged with a treatment colour before the new routine starts), the first application is spaced from that night, as the app spaces any build-up it starts (`waitFor`): every 3rd night after one last night means the first is two nights after day 1. Nothing ever moves up by itself.
- A recovery night chosen for tonight stays one: night 1 is tomorrow.
- A product the patient already has keeps its first day of use, so progress photos and history still line up. Face and body products are never mixed.
- The log, photos, check-ins, reminder times and settings all stay.
- The irritation note replaces the old one only when the code has one.
- Loading the same code twice changes nothing.

## Example

Starting tretinoin: a wait after cleansing, tretinoin starting slowly over four weeks, and a plain morning.

```json
{
  "v": 1,
  "p": [
    {"n": "Gentle cleanser", "k": "cleanser"},
    {"n": "Tretinoin", "k": "retinoid"},
    {"n": "Moisturizer", "k": "moisturizer"},
    {"n": "Sunscreen SPF 30+", "k": "spf"}
  ],
  "am": {"s": [{"p": 0}, {"p": 2}, {"p": 3, "h": "Last step of the morning. Broad-spectrum."}]},
  "pm": {
    "s": [
      {"p": 0, "w": 20},
      {"p": 1, "a": "Pea-size for the whole face", "h": "On completely dry skin", "b": [[3, 14], [2, 14]]},
      {"p": 2}
    ]
  }
}
```

The app reads it as:

- Evening: Gentle cleanser, every night, then wait 20 minutes. Tretinoin, every 3rd night, building up to every night, pea-size for the whole face: every 3rd night for 2 weeks, then every other night for 2 weeks; Tendwell asks how your skin is before each move up; on completely dry skin. Moisturizer, every night.
- Morning: Gentle cleanser, every morning. Moisturizer, every morning. Sunscreen SPF 30+, every morning, last step of the morning.

The link is 510 bytes. `PlanCodeToolTests.swift` holds it and checks that the app reads it.

This is an example of the format, not medical advice.
