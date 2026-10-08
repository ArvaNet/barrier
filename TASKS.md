# Barrier v1 (native iPhone app): build checklist

Finish line: Barrier compiles, passes tests, and every screen has been
screenshot-checked on the iOS Simulator in CI, ready for the founder to run on
their iPhone from Xcode.

- [x] Fact-check the guidance (docs/derm-facts.md)
- [x] Core package: models, schedule engine, reminders, guidance, milestones (27 tests, Linux)
- [x] App: model, storage (App Group), notifications with actions, background refresh
- [x] Screens: onboarding, Today, ritual, routine editor, progress, camera, compare, derm, report PDF, settings
- [x] Widget (home + Lock Screen, Done button), Live Activity timer, Siri intents
- [x] App icon, asset catalog, privacy manifest
- [x] CI: core tests (Linux + macOS), simulator build, screenshots
- [ ] First green CI build (fix compiler findings)
- [ ] Review screenshots, polish what looks off
- [ ] Review pass (merge-blocking only) + fixes
- [ ] Commit generated Barrier.xcodeproj so the Mac only needs Xcode
- [ ] Vault update note for the founder
