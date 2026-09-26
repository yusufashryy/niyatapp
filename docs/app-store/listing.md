# App Store listing (draft)

Copy these into App Store Connect. Character limits are Apple's.

## Name (30)
Niyat: Prayer Times & Qur'an

## Subtitle (30)
Salah, Qur'an & Qibla. No ads.

## Promotional text (170, can change any time)
Free forever: no ads, no accounts, no tracking. Accurate prayer times, a daily Qur'an habit, Qibla and beautiful widgets, all on your iPhone.

## Description (4000)
Niyat (نيّة, "intention") helps you keep your prayers and build a daily Qur'an habit. It's free, has no ads, no subscriptions and no accounts, and everything stays on your iPhone.

PRAYER TIMES
• Accurate times for anywhere, calculated on your phone with your choice of method (Muslim World League, ISNA, Umm al-Qura, Egyptian, Karachi and more) and Hanafi or Standard Asr
• A unique prayer dial showing your whole day at a glance
• Notifications 30 or 10 minutes before, at the adhan, and a check-in 30 minutes after: choose exactly which you want
• Log a prayer straight from the notification: press and hold, tap Log Prayer

TRACK YOUR SALAH
• Check in each prayer as on time, late or missed, and note why you missed one
• A calendar and stats that show how consistent you're being, and which prayers you miss most
• Streaks that reward consistency

QUR'AN
• The full Qur'an with verified text from the Tanzil Project, checked against published checksums
• Uthmani, simplified Uthmani and modern (Imla'i) scripts, plus the Warsh and Qalun readings
• Mushaf view: the 604 pages of the Madinah mushaf, with the same 15 lines on every page as the printed copy
• Verse-by-verse recitation from well-known reciters, with the text following the reciter word by word
• Recite with the app: it follows you word by word and marks words to double-check (words only, not tajweed)
• Memorise: hide the text and recite from memory while the app follows along
• A daily goal in ayat with a streak, gentle reminders, a verse of the day and a Friday reminder for Surah Al-Kahf
• English translation (The Clear Quran)

QIBLA
• A clean, accurate compass using true north and your live location, with a gentle tap when you're facing the Qibla

AND MORE
• 10 widgets for your Home Screen and Lock Screen, including one to log prayers
• Tasbih counter
• Hijri date with local adjustment
• Themes, including your own colours
• Groups: optional accountability with family and friends through iCloud

PRIVATE BY DESIGN
No data is collected. Your location, prayer log and reading progress never leave your phone.

OPEN SOURCE
Niyat is open source. Every Qur'an source and calculation is documented on GitHub.

## Keywords (100, comma-separated, no spaces needed)
salah,namaz,adhan,azan,quran,koran,qibla,muslim,islam,prayer,mosque,tasbih,hijri,ramadan,dua

## Category
Primary: Lifestyle (or Reference). Secondary: Books.

## Age rating
4+ (no objectionable content).

## URLs
- Privacy Policy URL: https://yusufashryy.github.io/niyatapp/privacy (after enabling GitHub Pages, see below)
- Support URL: https://github.com/yusufashryy/niyatapp/issues

## App Privacy ("nutrition label")
Answer **"No, we do not collect data from this app."** Niyat has no server and no analytics. Apple's own services (geocoding, iCloud, In-App Purchase, speech recognition) don't count as the app collecting data: the developer never receives any of it.

## In-App Purchases (Support Niyat)
Create three **Consumable** in-app purchases with exactly these Product IDs:

| Product ID | Reference name | Display name | Description | Price |
|---|---|---|---|---|
| niyat.tip.small | Small tip | Small tip | A small thank-you | $0.99 |
| niyat.tip.medium | Kind tip | Kind tip | Helps cover a month of costs | $4.99 |
| niyat.tip.large | Generous tip | Generous tip | Keeps Niyat free for everyone | $9.99 |

Each needs a screenshot of the Support Niyat screen for review. Join the App Store Small Business Program so Apple's fee is 15% rather than 30%.

## App Review notes
Niyat is free with no login. Tips are optional and unlock nothing. Location is only used to calculate prayer times and the Qibla. Prayer Lock uses Screen Time (Family Controls) to lock apps the user chooses during prayer times. The microphone and speech recognition are only used after the user taps the microphone in the Qur'an reader, to follow their recitation word by word; audio is never recorded or saved. Speech recognition is also used, on the device only, to line up reciters' recordings with the text.

## Screenshots
Needed at 6.9" (1320 × 2868). CI's demo tour takes them on the largest iPhone simulator, so they're already the right size: download them from the `demo-media` branch (`screenshots/` folder) on GitHub. Suggested set (up to 10): 03 Today · 06 Quran - Al-Fatiha · 07 Mushaf · 07c Mushaf - memorisation · 08 Qibla · 09 Stats · 09c Year · 11 Tasbih.

## Enabling the privacy policy page (free)
1. On GitHub: repo **Settings › Pages**.
2. Source: **Deploy from a branch**, branch **main**, folder **/docs**. Save.
3. After a minute the policy is live at https://yusufashryy.github.io/niyatapp/privacy
