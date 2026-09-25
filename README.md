<p align="center">
  <img src="Niyat/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon.png" width="120" alt="Niyat app icon">
</p>

<h1 align="center">Niyat · نيّة</h1>

<p align="center">
  <b>A free, open-source iOS companion for your deen.</b><br>
  Prayer times, adhan alerts, Quran, Qibla, widgets and Prayer Lock.<br>
  No ads. No subscriptions. No accounts. No tracking.
</p>

<p align="center">
  <a href="https://github.com/yusufashryy/niyatapp/actions/workflows/build.yml"><img src="https://github.com/yusufashryy/niyatapp/actions/workflows/build.yml/badge.svg" alt="Build"></a>
  <img src="https://img.shields.io/badge/iOS-26%2B-black?logo=apple" alt="iOS 26+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?logo=swift&logoColor=white" alt="SwiftUI">
  <img src="https://img.shields.io/badge/license-MIT-3ae0a3" alt="MIT">
</p>

<p align="center">
  <img src="docs/screenshots/today.png" width="200" alt="Today">
  <img src="docs/screenshots/quran.png" width="200" alt="Quran">
  <img src="docs/screenshots/qibla.png" width="200" alt="Qibla">
  <img src="docs/screenshots/tasbih.png" width="200" alt="Tasbih">
</p>

*Niyat* (نيّة) means intention. Actions are judged by their intentions.

Built with Apple's **Liquid Glass** design on iOS 26 and 27: a dark, high-contrast interface with glass controls floating over a deep emerald glow.

## Features

| | |
|---|---|
| 🕌 **Prayer times** | Calculated on-device for anywhere in the world (works offline). 12 calculation methods, Hanafi/Standard Asr, high-latitude rules, per-prayer minute adjustments. Picks a sensible method for your country automatically. |
| 🔔 **Adhan notifications** | Per-prayer on/off, optional "X minutes before" reminder, *Jumu'ah* on Fridays. |
| 📖 **Quran** | Full Arabic text (Uthmani script, Amiri Quran font) with English translation, fully offline. Search, bookmarks, "continue reading", adjustable text size. |
| 🧭 **Qibla compass** | Live compass with haptic feedback when you're facing the Qibla, plus distance to Makkah. |
| 📱 **Widgets** | Next Prayer (Home Screen and all three Lock Screen styles), Prayer Times (medium/large), Verse of the Day, and an interactive Tasbih counter you can tap right on the Home Screen. |
| 🔒 **Prayer Lock** | Blocks the apps you choose (Instagram, TikTok, games…) at each adhan until you've had time to pray, with an "I've prayed" button to unlock early. Also does on-demand focus sessions. *Needs a paid Apple Developer account, see below.* |
| ✅ **Prayer tracker** | Tick off each prayer and build a streak. |
| 📿 **Tasbih** | Dhikr counter with targets (33/99/100…) and haptics. |
| 🌙 **Hijri date** | With ±2 day adjustment to match local moon sighting. |

## Running it on your iPhone

iOS apps can only be built on a **Mac** with **Xcode** installed. There's no way around this (Apple's rule). If you don't have a Mac, a friend's Mac or a cloud Mac such as MacinCloud works too.

### 1. One-time setup

1. Install **Xcode 26 or newer** (Xcode 27 recommended) from the Mac App Store. It's free and large, so give it a while.
2. Open Xcode once, accept the licence, and let it install the iOS components.
3. Install [Homebrew](https://brew.sh) if you don't have it, then in Terminal run:
   ```sh
   brew install xcodegen
   ```
   XcodeGen builds the Xcode project from `project.yml`, so the repo never has to store Xcode's messy project files.
4. In Xcode › Settings › Accounts, sign in with your Apple ID.

### 2. Get the code and set up signing

```sh
git clone https://github.com/yusufashryy/niyatapp.git
cd niyatapp
cp Config/Local.xcconfig.example Config/Local.xcconfig
open -e Config/Local.xcconfig
```

In `Local.xcconfig` set:
- `DEVELOPMENT_TEAM`: your team ID. In Xcode › Settings › Accounts, select your Apple ID. The team ID is the 10-character code shown for your team (for a free account, "(Personal Team)").
- `BUNDLE_ID_PREFIX`: something unique to you, e.g. `com.yourname`. App IDs are global across all Apple accounts, so the default one will already be taken.

### 3. Build

```sh
make          # free Apple ID: everything except Prayer Lock
# or
make full     # paid developer account: adds Prayer Lock + Time Sensitive alerts
make open
```

In Xcode, plug in your iPhone (or pick it from the device list at the top), then press **▶ Run**. The first time, your iPhone will ask you to:
- turn on **Developer Mode** (Settings › Privacy & Security › Developer Mode), and
- trust your developer certificate (Settings › General › VPN & Device Management).

> **Free vs paid Apple account**
> - **Free Apple ID**: everything except Prayer Lock works. Apple makes free-account apps expire after **7 days**, so you'll need to press Run again from Xcode once a week.
> - **Paid Apple Developer Program ($99/year)**: apps last a year, you get Prayer Lock (Apple only gives the Screen Time permission to paid accounts), and you could publish to the App Store for everyone.

Whenever you pull new changes or edit `project.yml`, run `make` (or `make full`) again.

## How it's built

- **Swift + SwiftUI**, iOS 26+ (runs on iPhone 11 and newer), built with the iOS 27 SDK. Uses Liquid Glass (`glassEffect`, glass buttons, the shrinking tab bar). Native Swift is the only way to build iOS widgets and use Screen Time.
- **[Adhan](https://github.com/batoulapps/adhan-swift)** for the astronomical prayer time calculations (a well-tested library used by many prayer apps).
- **WidgetKit** for widgets, **App Intents** for the tappable tasbih widget.
- **FamilyControls / ManagedSettings / DeviceActivity** (Apple's Screen Time API) for Prayer Lock.
- Settings live in a shared **App Group** so the widgets and extensions can read them.

```
Niyat/             The app
  App/              Entry point, tab bar, AppModel (app-wide state)
  Features/         One folder per screen: Today, Quran, Qibla, Focus, Tasbih, Settings, Onboarding
  Services/         Location, notifications, background refresh, prayer tracker
  Resources/        Quran data, font, icons
Shared/             Code used by the app AND the widgets (prayer calculation, settings, models)
NiyatWidgets/      Home Screen & Lock Screen widgets
FocusShared/        Prayer Lock scheduling (Screen Time), shared with the extensions below
FocusMonitor/       Background extension that locks/unlocks apps at prayer times
FocusShield/        The "It's time for Dhuhr" screen shown over locked apps
NiyatTests/        Unit tests
project.yml         Project definition (XcodeGen). full-features.yml adds Prayer Lock.
```

If you know Luau: a SwiftUI `View` is like a component whose `body` describes the UI, and it re-renders automatically when the state it reads changes. `@Observable` classes such as `AppModel` are like a shared state module that UI subscribes to.

### Tests

Every push is built and tested by GitHub Actions on macOS 27 with Xcode 27 (`.github/workflows/build.yml`), in both the free and paid variants. The latest demo video and screenshots are on the [`demo-media`](https://github.com/yusufashryy/niyatapp/tree/demo-media) branch. Locally: press ⌘U in Xcode.

The `full` build also runs `NiyatUITests/DemoTour.swift`, which taps through every screen in a simulator and uploads a screen recording and screenshots as a build artifact named **demo**.

## Known limitations

- iOS only lets an app schedule 64 notifications, so adhan alerts are scheduled about 10 days ahead and topped up whenever the app opens. Open it at least once a week. It'll remind you.
- Notifications use the default iOS sound for now (no adhan audio yet).
- Prayer Lock can be turned off by the user in Settings. It's a tool for self-discipline, not a parental control.

## Roadmap ideas

- Adhan audio for notifications (needs a freely-licensed recording)
- Morning/evening adhkar
- More translations and languages (Urdu, Indonesian, Turkish, French…)
- Quran audio recitation
- Ramadan mode (suhoor/iftar times and countdown)
- Apple Watch app

Contributions are welcome! See [CONTRIBUTING.md](CONTRIBUTING.md).

## Credits & licences

The app's code is under the [MIT License](LICENSE). Bundled content keeps its own licence, listed in [docs/CREDITS.md](docs/CREDITS.md):

- Quran text: [Tanzil Project](https://tanzil.net), CC BY 3.0 (verbatim, unmodified)
- English translation: Talal Itani, [ClearQuran.com](https://clearquran.com), CC BY-ND 4.0
- Font: [Amiri Quran](https://github.com/aliftype/amiri), SIL Open Font License 1.1
- Prayer times: [Adhan](https://github.com/batoulapps/adhan-swift), MIT
