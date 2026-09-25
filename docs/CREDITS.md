# Bundled content and licences

The app's source code is MIT-licensed. The following bundled files keep their
own licences. **Don't edit the Quran text or translation files.** Both licences
require them to stay exactly as published.

| File | What | Source | Licence |
|---|---|---|---|
| `Niyati/Resources/Quran/quran-uthmani.json` | Quran Arabic text, Uthmani script (Hafs) | [Tanzil Project](https://tanzil.net), via [risan/quran-json](https://github.com/risan/quran-json) (`data/tanzil/uthmani.json`, sha256 `adaebb37…4b761`) | [CC BY 3.0](https://tanzil.net/docs/text_license): *"Permission is granted to copy and distribute verbatim copies of this text, but changing it is not allowed."* |
| `Niyati/Resources/Quran/chapters.json` | Surah names and verse counts | Tanzil `quran-data.xml`, via risan/quran-json (`data/tanzil/chapters.json`) | CC BY 3.0 |
| `Niyati/Resources/Quran/translation-en-clearquran.json` | English translation | *Translation by Talal Itani, ClearQuran.com* ("Allah" edition), via risan/quran-json (`data/extra/english_itani_allah.json`, sha256 `2e5d4d9f…250ed`) | [CC BY-ND 4.0](https://blog.clearquran.com/download): free to use and share, including commercially, unmodified, with credit |
| `Niyati/Resources/Fonts/AmiriQuran-Regular.ttf` | Amiri Quran font | [aliftype/amiri](https://github.com/aliftype/amiri), via google/fonts | SIL Open Font License 1.1 (`AmiriQuran-OFL.txt`) |
| `Shared/DailyVerses.swift` | Verses for the Verse of the Day widget | Generated verbatim from the two files above by `scripts/generate_daily_verses.py` | As above |
| Swift package `Adhan` | Prayer time calculation | [batoulapps/adhan-swift](https://github.com/batoulapps/adhan-swift) | MIT |

Popular translations such as Saheeh International and Abdel Haleem are
copyrighted with no free licence, which is why they aren't bundled.
risan/quran-json keeps a detailed record of which translations can legally be
redistributed, so check there before adding a new one.

Arabic dhikr phrases in `Shared/Tasbih.swift` are standard phrases, not copied from any dataset.
