#!/usr/bin/env python3
"""Fetch Tafsir al-Jalalayn and Ibn Kathir's tafsir from Quranpedia and write
them into the app as compressed JSON (`make tafsir`).

Quranpedia's licence (in every file and https://quranpedia.net/dumps/LICENSE.md)
lets apps use its classical tafsirs freely; it asks that copies be kept current,
so run this again to pick up its corrections. The commentators' words are kept
as published. Only the markup changes (HTML to plain paragraphs), and the modern
editor's own material is left out: Quranpedia says contemporary work stays with
its publisher.

Output: Niyat/Resources/Tafsir/<id>.tafsir, raw-DEFLATE-compressed JSON:
  {"id", "name", "author", "edition", "version", "entries": [[surah, from, to, text], ...]}
An entry covers ayat from..to of its surah (the commentators often explain a
few ayat together).

Usage: python3 scripts/build_tafsir.py [--from DIR]   (DIR: already-downloaded files)
"""
import gzip
import hashlib
import html
import json
import os
import re
import sys
import urllib.request
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "Niyat", "Resources", "Tafsir")
CHAPTERS = os.path.join(ROOT, "Niyat", "Resources", "Quran", "chapters.json")
BASE = "https://quranpedia.net/dumps/"

BOOKS = [
    {"id": "jalalayn", "file": "tafsir-book-272.json.gz", "name_en": "Tafsir al-Jalalayn"},
    {"id": "ibn-kathir", "file": "tafsir-book-136.json.gz", "name_en": "Tafsir Ibn Kathir"},
]

# Arabic-Indic footnote markers the editor added, e.g. «(١)».
FOOTNOTE_MARK = re.compile(r"\(\s*[٠-٩]+\s*\)")


def fetch(name, folder):
    if folder:
        with open(os.path.join(folder, name), "rb") as f:
            return f.read()
    request = urllib.request.Request(BASE + name, headers={"User-Agent": "Niyat build script"})
    with urllib.request.urlopen(request, timeout=120) as response:
        return response.read()


def clean(text, editor_notes):
    """HTML to plain text with paragraph breaks; the editor's footnotes removed."""
    text = re.sub(r'<div class="foot-notes">.*?</div>', "", text, flags=re.S)
    if editor_notes:
        text = re.sub(r"<a[^>]*>\s*\(\s*[٠-٩]+\s*\)\s*</a>", "", text)
        text = FOOTNOTE_MARK.sub("", text)
    text = re.sub(r"<\s*(br|hr)\s*/?>", "\n", text, flags=re.I)
    text = re.sub(r"</\s*(p|div|tr|table)\s*>", "\n", text, flags=re.I)
    text = re.sub(r"<[^>]+>", "", text)
    text = html.unescape(text).replace("\r", "")
    text = re.sub(r"[ \t ]+", " ", text)
    text = re.sub(r" *\n *", "\n", text)
    text = re.sub(r"\n{2,}", "\n", text)
    return text.strip()


def keep_part(surah, ayah, part, edited):
    """In the edited Ibn Kathir, leave out the modern editor's study (volume 0)
    and Ibn Kathir's own introduction, which the data files under the last
    ayah (114:6) rather than any ayah it explains."""
    if not edited:
        return True
    if str(part.get("part")) == "0":
        return False
    if (surah, ayah) == (114, 6) and str(part.get("part")) == "1":
        return False
    return True


def build(book, manifest, folder, verse_counts):
    raw = fetch(book["file"], folder)
    expected = next(f["sha256"] for f in manifest["files"] if f["name"] == book["file"])
    actual = hashlib.sha256(raw).hexdigest()
    if actual != expected:
        sys.exit(f"{book['file']}: SHA-256 {actual} does not match the manifest's {expected}")
    data = json.loads(gzip.decompress(raw))
    info = data["book"]
    editor_notes = info.get("mohaqeq") is not None

    texts = {}
    for record in data["ayahs"]:
        s, a = record["surah"], record["ayah"]
        parts = [p for p in record["content"] if keep_part(s, a, p, editor_notes)]
        text = "\n".join(t for t in (clean(p["text"], editor_notes) for p in parts) if t)
        if text:
            texts[(s, a)] = text

    entries = []
    for surah in range(1, 115):
        starts = sorted(a for (s, a) in texts if s == surah)
        for i, start in enumerate(starts):
            end = (starts[i + 1] - 1) if i + 1 < len(starts) else verse_counts[surah]
            entries.append([surah, start, end, texts[(surah, start)]])

    covered = sum(e[2] - e[1] + 1 for e in entries)
    missing = [(s, a) for s in range(1, 115) for a in range(1, verse_counts[s] + 1)
               if not any(e[0] == s and e[1] <= a <= e[2] for e in entries if e[0] == s)]
    for s, a in missing:
        # Only ayat before a surah's first entry can be missing (Jalalayn starts Al-Fatiha at its second ayah).
        assert not any(e[0] == s and e[1] < a for e in entries), (s, a)

    out = {
        "id": book["id"],
        "name": info["name"],
        "nameEnglish": book["name_en"],
        "author": info["author"]["full_name"],
        "edition": " · ".join(x for x in [info.get("nasher"), info.get("publish_year")] if x),
        "version": data["license"]["version"],
        "entries": entries,
    }
    encoded = json.dumps(out, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    compressor = zlib.compressobj(9, zlib.DEFLATED, -15)  # raw DEFLATE, read by Foundation's .zlib
    packed = compressor.compress(encoded) + compressor.flush()
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, book["id"] + ".tafsir")
    with open(path, "wb") as f:
        f.write(packed)
    print(f"{book['id']}: {len(entries)} entries, {covered} of 6236 ayat covered, "
          f"{len(missing)} without commentary {missing[:5]}, {len(encoded) // 1024} KB -> {len(packed) // 1024} KB")


def main():
    folder = sys.argv[sys.argv.index("--from") + 1] if "--from" in sys.argv else None
    manifest = json.loads(fetch("manifest.json", folder))
    with open(CHAPTERS, encoding="utf-8") as f:
        chapters = json.load(f)
    chapters = chapters if isinstance(chapters, list) else next(v for v in chapters.values() if isinstance(v, list))
    verse_counts = {c["id"]: c["total_verses"] for c in chapters}
    assert sum(verse_counts.values()) == 6236
    for book in BOOKS:
        build(book, manifest, folder, verse_counts)


if __name__ == "__main__":
    main()
