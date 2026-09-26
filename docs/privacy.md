---
title: Niyat Privacy Policy
---

# Niyat Privacy Policy

_Last updated: 26 September 2026_

Niyat is a free, open-source prayer and Qur'an app. **Niyat does not collect, store or sell any personal data.** It has no accounts, no ads, no analytics and no tracking, and there is no Niyat server.

## What stays on your iPhone

Everything you do in Niyat is stored only on your device, in the app's own storage (shared with Niyat's widgets on the same device):

- your location (used to calculate prayer times and the Qibla direction)
- your prayer log, missed-prayer reasons and streaks
- your Qur'an reading progress, goal, bookmarks and settings
- tasbih counts, theme and other preferences
- when each word starts in the reciters' recordings (for word-by-word highlighting), worked out on the device

You can delete all of it at any time in **More › Settings › Erase all data**, or by deleting the app.

## When Niyat uses the internet

Niyat works offline. A few optional features connect to outside services:

| Feature | Service | What is sent |
|---|---|---|
| Finding a city, or naming your current location | Apple (Core Location geocoding) | The search text or coordinates, handled under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/) |
| Qur'an recitation audio | Islamic Network CDN (cdn.islamic.network), and EveryAyah.com for one reciter | A normal web request for the audio file, which includes your IP address, as with any website. With word-by-word highlighting on, each verse's file is fetched a second time to line it up with the text on your iPhone. |
| Groups (optional) | Apple iCloud (CloudKit) | The display name and summary you choose to share (prayers completed, Qur'an goal progress), visible only to people in the groups you create or join. Stored in your iCloud account, not by Niyat. |
| Reciting with the app (optional, microphone) | Apple speech recognition | While the microphone is on, your voice is turned into text by Apple's speech recognition: on your iPhone when it supports Arabic on the device, otherwise by Apple's servers (encrypted in transit) under [Apple's Privacy Policy](https://www.apple.com/legal/privacy/). See below. |
| Tips (optional) | Apple In-App Purchase | Handled entirely by Apple. Niyat never sees your payment details. |
| Send feedback (optional) | A private Discord channel read by the developer (or email/GitHub) | Only what you write, an email address if you choose to give one for a reply, plus app version, iOS version and your calculation settings if you leave "Include app details" on. Never your location. |

## Your recitation

Reciting with the app is off until you tap the microphone, and Niyat explains what happens before iOS asks for permission.

- Niyat never records, saves or uploads your voice. Audio from the microphone goes straight to Apple's speech recognition and is discarded as it's processed.
- Where your iPhone can recognise Arabic on the device, nothing leaves it. Otherwise Apple's speech recognition runs on Apple's servers, as for dictation, and Apple's privacy policy applies. The app tells you which one your iPhone uses.
- The words marked for you to review are kept in memory only, and cleared when you leave the page or surah.
- Your recitation is never used to train anything.
- Word-by-word highlighting of reciters uses Apple's speech recognition on the reciter's public recording, on your iPhone only; only the time each word starts is kept.

## Notifications

Prayer and Qur'an reminders are scheduled on your device. No notification server is used.

## Children

Niyat does not knowingly collect any information from anyone, including children.

## Changes

If this policy changes, the new version will be published at this address, with a new date above.

## Contact

Questions: open an issue at [github.com/yusufashryy/niyatapp](https://github.com/yusufashryy/niyatapp/issues).
