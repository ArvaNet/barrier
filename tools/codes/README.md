# Routine codes (clinic pilot)

A small page that turns a routine into a Tendwell QR code and prints it on a sheet with the routine in words. Format: `docs/plan-code.md`.

- Open: double-click `index.html`. It needs internet for two libraries (QR writer from cdnjs, QR reader from jsDelivr).
- Pick an example or edit the JSON. Problems show in plain words; a good routine shows the code and "Reads back correctly".
- Print: "Print sheet", A4 portrait. Only the sheet prints: the code 5 cm wide, the words beside it.
- Privacy: a code carries the routine only. Never put a patient's name, dates or record numbers in it. The page sends and stores nothing.
- `plancode.js` is the format's rules and encoder; `PlanCodeToolTests.swift` checks it against the app.
