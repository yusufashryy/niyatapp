# Putting Niyat on the App Store

A step-by-step checklist for the first release. Things only you can do (your
Apple account, your Mac) are marked **You**. Everything in the code is already
set up: version 1.0.0, privacy manifests, the listing text (`listing.md`) and
the privacy policy (`docs/privacy.md`).

Rough timeline: enrolment 1–2 days, Family Controls approval days to a few
weeks, App Review usually 1–3 days.

## 1. Join the Apple Developer Program (**You**)
1. Go to <https://developer.apple.com/programs/enroll/> with the Apple ID you'll publish under ($99/year).
2. Enrol as an **Individual** (quickest; your name shows as the seller) or an **Organization** (needs a D-U-N-S number).
3. Wait for the "Welcome" email.

## 2. Ask Apple for Prayer Lock permission early (**You**)
Prayer Lock uses Screen Time ("Family Controls"). Apps can use it on your own
phone straight away, but **App Store builds need Apple's approval**.
1. Request it at <https://developer.apple.com/contact/request/family-controls-distribution>.
2. Say it's for Niyat's Prayer Lock: the user picks apps to lock during prayer times, on their own device.

If it hasn't come through when everything else is ready, you can ship 1.0
without Prayer Lock: build with `make project` instead of `make full` (this
also leaves out Groups and Time Sensitive alerts). Add them in 1.1.

## 3. Your signing settings (**You**, on the Mac)
1. `make setup` (or copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig`).
2. In `Config/Local.xcconfig`:
   - `DEVELOPMENT_TEAM` = your Team ID (developer.apple.com › Account › Membership details).
   - `BUNDLE_ID_PREFIX` = something you own, e.g. `com.yourname`. **Pick it carefully: it can't change after release.**
3. `make full`, then open `Niyat.xcodeproj`. Xcode › Settings › Accounts: sign in with your developer Apple ID.
4. With "Automatically manage signing" Xcode creates the App IDs, the App Group and the iCloud container for you the first time you build to your phone.

## 4. Create the app in App Store Connect (**You**)
1. <https://appstoreconnect.apple.com> › Apps › **+** › New App.
2. Platform iOS, name **Niyat: Prayer Times & Qur'an**, language English, bundle ID `<your prefix>.Niyat`, SKU `niyat`.
3. Copy the numeric **Apple ID** from App Information into `Config/Base.xcconfig` › `APP_STORE_ID` (it powers "Rate Niyat"). This one is fine to commit.

## 5. Upload a build (**You**, on the Mac)
1. In Xcode choose the device **Any iOS Device (arm64)**.
2. Product › **Archive**. When it finishes the Organizer opens.
3. **Distribute App** › **App Store Connect** › Upload. Accept the defaults.
4. After 10–30 minutes the build appears in App Store Connect › TestFlight.
5. Optional but recommended: install it through **TestFlight** on your phone and try it once more.

Each new upload needs a higher build number: raise `CURRENT_PROJECT_VERSION`
in `project.yml` (1, 2, 3…), then `make full` again.

## 6. Fill in the listing (**You**, copying from `listing.md`)
- Name, subtitle, promotional text, description, keywords, category, age rating (answer "None" to everything → 4+).
- **Privacy Policy URL**: turn on GitHub Pages first (bottom of `listing.md`).
- **App Privacy**: "No, we do not collect data".
- **Screenshots**: 6.9" from the `demo-media` branch (see `listing.md`).
- **In-App Purchases**: the three tips (table in `listing.md`), and join the Small Business Program for a 15% fee.
- **App Review notes**: paste the text from `listing.md`.
- Pricing: **Free**. Availability: all countries (or choose).

## 7. Submit (**You**)
Pick the build, then **Add for Review** › **Submit**. If Apple asks
questions, they arrive in App Store Connect; reply there.

## Before each release
- CI is green on the branch you build from.
- `CURRENT_PROJECT_VERSION` raised (and `MARKETING_VERSION` for a new version, e.g. 1.0.1).
- Qur'an sources: check for a newer Qur'anpedia dump (see `docs/SOURCES.md`).
- The mushaf line layout comes from a project with no licence file (see `docs/SOURCES.md`): asking its author (zonetecde on GitHub) for written permission before release is the safe course.
