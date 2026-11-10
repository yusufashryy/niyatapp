#!/usr/bin/env python3
"""Fetch the English "Abridged Explanation of the Quran" (al-Mukhtasar fi
Tafsir al-Qur'an, Tafsir Center for Quranic Studies) from QuranEnc.com and
write it into the app as a compressed tafsir file (`make tafsir-en`).

QuranEnc's terms let its contents be downloaded and republished as long as the
text isn't modified, QuranEnc.com is named as the source with the version, and
copies are kept up to date: run this again before each release. The text is
stored exactly as served; the app only hides the leading ayah number, which it
already shows.

Output: Niyat/Resources/Tafsir/mukhtasar-en.tafsir (same format as
build_tafsir.py: raw-DEFLATE JSON with one entry per ayah).

Usage: python3 scripts/build_tafsir_en.py [--from DIR]   (DIR: <surah>.json files from the API)
"""
import datetime
import json
import os
import subprocess
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Niyat", "Resources", "Tafsir", "mukhtasar-en.tafsir")
API = "https://quranenc.com/api/v1/translation/sura/english_mokhtasar/{}"
TOTAL_AYAT = 6236


def fetch(surah, folder):
    if folder:
        with open(os.path.join(folder, f"{surah}.json"), encoding="utf-8") as f:
            return json.load(f)
    # QuranEnc refuses Python's default client name; curl is accepted.
    raw = subprocess.run(["curl", "-sf", "--retry", "3", "-m", "60", API.format(surah)],
                         check=True, capture_output=True).stdout
    return json.loads(raw)


def main():
    folder = sys.argv[sys.argv.index("--from") + 1] if "--from" in sys.argv else None
    entries = []
    for surah in range(1, 115):
        for row in fetch(surah, folder)["result"]:
            text = row["translation"].strip()
            if not text:
                sys.exit(f"empty explanation at {surah}:{row['aya']}")
            entries.append([int(row["sura"]), int(row["aya"]), int(row["aya"]), text])
    if len(entries) != TOTAL_AYAT:
        sys.exit(f"expected {TOTAL_AYAT} ayat, got {len(entries)}")
    out = {
        "id": "mukhtasar-en",
        "name": "The Abridged Explanation of the Quran",
        "nameEnglish": "The Abridged Explanation of the Quran",
        "author": "Tafsir Center for Quranic Studies (al-Mukhtasar fi Tafsir al-Qur'an al-Karim)",
        "edition": "English translation, QuranEnc.com (english_mokhtasar)",
        "version": "QuranEnc.com, fetched " + datetime.date.today().isoformat(),
        "entries": entries,
    }
    encoded = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE, read by Foundation's .zlib
    packed = compressor.compress(encoded) + compressor.flush()
    with open(OUT, "wb") as f:
        f.write(packed)
    print(f"wrote {OUT}: {len(entries)} ayat, {len(packed) // 1024} KB")


if __name__ == "__main__":
    main()
