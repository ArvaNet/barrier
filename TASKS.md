# Barrier v1 (native iPhone app): build checklist

Finish line: Barrier compiles, passes tests, and every screen has been
screenshot-checked on the iOS Simulator in CI, ready for the founder to run on
their iPhone from Xcode.

- [x] Fact-check the guidance (docs/derm-facts.md)
- [x] Core package: models, schedule engine, reminders, guidance, milestones, recap (37 tests, Linux + macOS)
- [x] App: model, storage (App Group), notifications with actions, background refresh
- [x] Screens: onboarding, Today, ritual, routine editor, progress, camera, compare, derm, report PDF, settings
- [x] Widget (home + Lock Screen, Done button), Live Activity timer, Siri intents
- [x] App icon, asset catalog, privacy manifest
- [x] CI: core tests, simulator build, 15 screenshots with demo data, hang sampler
- [x] Green CI build, zero warnings
- [x] Screenshot review + polish (Progress hang, finish layout, tints, status bar, copy)
- [x] Review 1 (docs/review-1.md): 9 blockers + 6 should-fix, all fixed with regression tests
- [x] Review 2 on the fixes (docs/review-2.md): 4 blockers + 6 should-fix, all fixed
- [x] Generated Barrier.xcodeproj committed; CI warns when stale
- [x] Vault status + decision log updated

## On the founder's Mac (not doable from Windows)
- [ ] Set Team on both targets, run on iPhone (README → Run it on your iPhone)
- [ ] Enter the real dermatologist routine; send a test reminder; take the "before" photo
- [ ] Check once with 2+ photos that the report's photo page renders
