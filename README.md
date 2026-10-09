# Barrier

The routine your dermatologist gave you, remembered. An iPhone app that tells
you exactly what to put on your skin tonight, reminds you at the right time,
and adjusts when life gets in the way.

- **Tonight, never wrong.** Rotations (every other night, skin cycling, any
  pattern), weekday steps, ease-in schedules for retinoids, course end dates.
- **Survives real life.** Miss a night and the next one picks up where you
  left off. Irritated skin? One tap makes tonight a recovery night. Traveling?
  Pause the plan and it waits.
- **Reminders that stop when you're done.** Local notifications with Done,
  In 30 minutes and Not tonight on the Lock Screen. A gentle nudge if a night
  goes unlogged. No server, no account.
- **The routine itself.** Step by step, with wait timers (on the Lock Screen
  too) so tretinoin goes on dry skin.
- **Proof it's working.** Weekly photos with a ghost of the last one for
  matching framing, before/after compare, growth rings, a skin log.
- **Ready for the follow-up.** Questions to ask, your dermatologist's own
  words, and a one-page PDF report.
- Home and Lock Screen widget with a Done button. Siri: "What's tonight in Barrier".

Everything stays on the phone (and its iCloud backup).

## Run it on your iPhone

You need a Mac with Xcode 16 or newer.

1. Open `Barrier.xcodeproj`.
2. Select the **Barrier** target → Signing & Capabilities → pick your Team
   (your Apple ID works). Do the same for **BarrierWidget**.
3. If Xcode says the bundle id is taken, change `BUNDLE_PREFIX` and
   `APP_GROUP` in `project.yml` (or in the target build settings).
4. Plug in your iPhone, choose it as the run destination, press Run.
   The first time, trust the developer on the phone: Settings → General →
   VPN & Device Management.

With a free Apple ID the app runs for 7 days, then needs another Run from
Xcode. A paid developer account removes that limit and enables TestFlight.

### If the first build complains

- **"…doesn't support the App Groups capability"** (some free Apple IDs):
  on both targets, Signing & Capabilities → remove **App Groups**. The app
  works the same; only the widget can't see your routine.
- **"Failed to register bundle identifier"**: change `BUNDLE_PREFIX` (and
  `APP_GROUP`) in `project.yml` to something unique, e.g.
  `com.yourname.barrier`, then run `xcodegen generate` (or edit the bundle
  identifiers in both targets' build settings).
- **Reminders don't show at night**: if you use a Sleep or Do Not Disturb
  Focus, add Barrier to its allowed apps (Settings → Focus → Sleep → Apps).
- **After adding or removing source files**: run `xcodegen generate`
  (`brew install xcodegen`). CI warns when the committed project is stale.

### First night

1. Pick "My dermatologist's routine" and add exactly what you were given,
   with their words in each step's instructions.
2. Set how often each active goes on (or use Ease in) and your reminder times.
3. Tap Settings → "Send a test reminder", lock the phone, and long-press it.
4. Take your "before" photo.

## Project layout

- `Packages/BarrierCore`: models, the schedule engine, reminder planning and
  guidance text. Pure Swift, tested on Linux and macOS (`swift test`).
- `Barrier/`: the SwiftUI app.
- `BarrierWidget/`: widget and Live Activity.
- `Shared/`: code used by both (App Group storage, intents, palette).
- `project.yml`: XcodeGen spec; `xcodegen generate` rebuilds the project.
- `docs/derm-facts.md`: the fact-check behind every piece of guidance.
- `prototype/web/`: the earlier web prototype (engine + push worker), kept for
  a possible Android/web version. Not used by the iPhone app.

CI (GitHub Actions) runs the core tests on Linux, builds the app for the iOS
Simulator, and takes screenshots of every screen with demo data.

Barrier helps you follow your dermatologist's plan. It doesn't diagnose or
give medical advice.
