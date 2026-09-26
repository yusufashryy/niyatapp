# Contributing to Niyat

JazakAllahu khayran for helping! Niyat is free and always will be.

1. Fork the repo and create a branch.
2. Follow **Running it** in the README to build (`make`, or `make full` with a paid Apple account).
3. Keep changes focused. Match the style around you: SwiftUI, the `Palette` colours, `glassPanel` for floating elements and `surface` for content.
4. Push. GitHub Actions builds both variants, runs the tests and records a demo tour of the app. Check the screenshots of the screens you touched.
5. Open a pull request.

Rules that matter:
- **Never edit the Quran text or translation JSON files.** Their licences only allow verbatim copies. New translations must have a licence that allows redistribution (see `docs/CREDITS.md`).
- Code in `Shared/` runs inside the widgets and extensions too, so no app-only APIs there.
- Prayer Lock (Screen Time) code goes in `PrayerLock/` and app code using it goes inside `#if SCREEN_TIME`.
