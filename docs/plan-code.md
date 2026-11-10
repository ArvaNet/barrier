# Routine codes, version 1

A clinic can hand over a routine as a QR code. The patient scans it in Tendwell, checks it against the paper sheet, and uses it.

The code carries the routine and nothing else. No patient name, no dates, no clinic records. Nothing is stored on a server: the whole routine is inside the code.

The app's side lives in `Packages/BarrierCore/Sources/BarrierCore/PlanCode.swift`. The clinic pilot page lives in `tools/codes/`.

## Two promises

1. **Printed codes keep working.** A sheet can sit on a fridge for years. Version 1 never changes meaning. Any change to the format, however small, gets a new version number, and the app keeps reading version 1.
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
| `body` | routine | | The body routine (back, chest). Optional. |
| `i` | text, line breaks allowed | 280 | What to do if the skin gets irritated, in the prescriber's words. Optional. |

At least one of `am`, `pm` and `body` is required.

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
| `e` | list of `[days, extra recovery nights]` | 1 to 6 phases | Ease-in from day 1. Evening only. |
| `n` | text | 24 | Name of the body routine, such as "Back". Body only, required there. |
| `q` | text | 40 | A moment for the body routine, such as "After shower". Body only. |

### Step

| Key | Type | Limit | Meaning |
|---|---|---|---|
| `p` | whole number | | The product, by its place in `p`, counting from 0. Required. |
| `a` | text | 120 | Amount, such as "Pea-size for the whole face". |
| `h` | text, line breaks allowed | 200 | How to apply it. |
| `w` | whole number | 1 to 120 | Minutes to wait after this step. |
| `n` | list of whole numbers | positions 0 to `l` - 1 | On these days of the rotation only. |
| `d` | list of whole numbers | 0 to 6, Sunday is 0 | On these weekdays only. |

A step with neither `n` nor `d` happens every time.

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
- Only the evening eases in, and only when it has a retinoid, exfoliant or treatment that is not on set weekdays.
- An ease-in has 1 to 6 phases. Each phase is 1 to 8 whole weeks (7 to 56 days) with 0 to 6 extra recovery nights.
- Only the body routine has a name or a cue, and it needs a name.
- Every product is used by at least one step.
- A product is used in the face routines or in the body routine, never both.
- The payload fits in 2,600 characters.

The app also simplifies what means the same thing. Text is trimmed. A step on every rotation position happens every time. A rotation no step uses becomes a length of 1. Positions and weekdays are sorted. Two codes that mean the same thing load the same.

## What loading does on the phone

The patient first sees the whole routine in words, with "If anything differs from the sheet your clinic gave you, follow the sheet." Nothing changes until they choose to use it.

- Only the routines in the code are replaced. A code with only the evening leaves the morning and the body routine as they were.
- Day 1 is the day the code is loaded. If that routine is already logged for today, day 1 is tomorrow, so no step of the new routine is skipped.
- An ease-in and a course both count from day 1.
- A product the patient already has keeps its first day of use, so progress photos and history still line up. Face and body products are never mixed.
- The log, photos, check-ins, reminder times and settings all stay.
- The irritation note replaces the old one only when the code has one.
- Loading the same code twice changes nothing.

## Example

Starting tretinoin: a wait after cleansing, an ease-in over four weeks, and a plain morning.

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
      {"p": 1, "a": "Pea-size for the whole face", "h": "On completely dry skin"},
      {"p": 2}
    ],
    "e": [[14, 2], [14, 1]]
  }
}
```

The app reads it as:

- Morning: Gentle cleanser, every morning. Moisturizer, every morning. Sunscreen SPF 30+, every morning, last step of the morning.
- Evening: Gentle cleanser, every night, then wait 20 minutes. Tretinoin, every night, pea-size for the whole face, on completely dry skin. Moisturizer, every night.
- Easing in: weeks 1 to 2, actives every 3rd night. Weeks 3 to 4, actives every other night. From week 5, the full routine.

The link is 510 bytes. `PlanCodeToolTests.swift` holds it and checks that the app reads it.

This is an example of the format, not medical advice.
