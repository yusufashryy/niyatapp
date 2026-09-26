#!/usr/bin/env python3
"""Builds Niyat/Resources/Quran/mushaf-lines.json: which words sit on each of
the 15 lines of each page of the Madinah mushaf (Hafs), as indices into Niyat's
own verified Tanzil Uthmani text.

Only the line breaks are taken from the layout dataset; no Arabic text or
glyphs from it are used. Every word Niyat draws comes from the bundled,
checksummed Tanzil text.

Layout source: https://github.com/zonetecde/mushaf-layout (one JSON file per
page of the standard 604-page Madinah mushaf, derived from Quran.com/QUL).

Checks performed (the script stops if any fails):
- every page starts at the verse given by Tanzil's own page index;
- every word of the Qur'an appears exactly once, in order;
- every surah starts right after its header (and Bismillah, except 1 and 9);
- every page has 15 rows (except the two opening pages).

Usage:
    git clone https://github.com/zonetecde/mushaf-layout /tmp/mushaf-layout
    python3 scripts/generate_mushaf_layout.py /tmp/mushaf-layout
"""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QURAN = ROOT / "Niyat/Resources/Quran/quran-uthmani.json"
CHAPTERS = ROOT / "Niyat/Resources/Quran/chapters.json"
OUT = ROOT / "Niyat/Resources/Quran/mushaf-lines.json"


def is_letter(c: str) -> bool:
    v = ord(c)
    return 0x0621 <= v <= 0x063A or 0x0641 <= v <= 0x064A or v in (0x0671, 0x066E, 0x066F, 0x06A1, 0x06BA, 0x06CC)


def words_of(text: str) -> list[str]:
    """Words as Niyat splits them: space-separated pieces that contain letters."""
    return [t for t in text.split(" ") if any(is_letter(c) for c in t)]


def fail(message: str) -> None:
    sys.exit(f"FAILED: {message}")


def main(layout_repo: Path) -> None:
    quran = json.loads(QURAN.read_text())
    tanzil_pages = [(m["sura"], m["aya"]) for m in json.loads(CHAPTERS.read_text())["indexes"]["pages"]]

    # Niyat shows the Bismillah of verse 1 as a header, so verse 1's words
    # start after it (except Al-Fatiha, where it is verse 1, and At-Tawbah).
    bismillah_words = len(words_of(quran["1"][0]["text"]))
    tanzil_words = {}
    for surah in range(1, 115):
        for verse in quran[str(surah)]:
            words = words_of(verse["text"])
            if verse["verse"] == 1 and surah not in (1, 9):
                words = words[bismillah_words:]
            tanzil_words[(surah, verse["verse"])] = words

    pages = {}
    for page in range(1, 605):
        pages[page] = json.loads((layout_repo / "mushaf" / f"page-{page:03d}.json").read_text())["lines"]

    # Map each layout word (1-based) to Niyat word indices (0-based) by their
    # letters. A few layout words hold two Tanzil words ("بَعْدَ مَا",
    # "إِلْ يَاسِينَ"), and the layout's own text has stray spaces, so words are
    # matched letter by letter rather than by splitting its text.
    def letters(text: str) -> str:
        """Letter skeleton: alef and hamza forms dropped, and the spelling
        variants between the two Uthmani texts folded (ى dropped, ة/ه, ؤ/و, ئ/ي)."""
        fold = {"ئ": "ي", "ة": "ه", "ؤ": "و"}
        drop = set("اٱأإآءٲٳى")
        return "".join(fold.get(c, c) for c in text if is_letter(c) and c not in drop)

    layout_words = {}
    for page in pages.values():
        for line in page:
            for w in line.get("words", []):
                s, v, i = map(int, w["location"].split(":"))
                layout_words.setdefault((s, v), {})[i] = letters(w["word"])
    if set(layout_words) != set(tanzil_words):
        fail("layout and Tanzil cover different verses")
    mapping = {}
    for key, words in layout_words.items():
        ours = tanzil_words[key]
        position = 0
        for i in sorted(words):
            start, consumed = position, ""
            while position < len(ours) and len(consumed) < len(words[i]):
                consumed += letters(ours[position])
                position += 1
            if consumed != words[i]:
                fail(f"{key[0]}:{key[1]} word {i}: layout letters {words[i]} vs Tanzil {consumed}")
            mapping[(key[0], key[1], i)] = (start, position - 1)
        if position != len(ours):
            fail(f"{key[0]}:{key[1]}: {len(ours) - position} Tanzil words not covered by the layout")

    # Two pages in the dataset lack their header lines; the next page starts with
    # a Bismillah and no header, which places the header at the bottom of these.
    repairs = {586: (81, 82), 590: (85, 86)}

    out_pages = []
    expected = [(s, v, w) for s in range(1, 115) for v in range(1, len(quran[str(s)]) + 1)
                for w in range(len(tanzil_words[(s, v)]))]
    cursor = 0
    for page in range(1, 605):
        rows = []
        if page in repairs:
            rows += [["h", repairs[page][0]], ["b"]]
        for line in pages[page]:
            if line["type"] == "surah-header":
                rows.append(["h", int(line["surah"])])
            elif line["type"] == "basmala":
                rows.append(["b"])
            else:
                first = line["words"][0]["location"].split(":")
                last = line["words"][-1]["location"].split(":")
                s1, v1, i1 = map(int, first)
                s2, v2, i2 = map(int, last)
                w1 = mapping[(s1, v1, i1)][0]
                w2 = mapping[(s2, v2, i2)][1]
                rows.append([s1, v1, w1, s2, v2, w2])
                # Every word, in order, exactly once.
                while True:
                    if cursor >= len(expected):
                        fail(f"page {page}: more words than the Qur'an has")
                    if expected[cursor] == (s1, v1, w1):
                        break
                    fail(f"page {page}: expected {expected[cursor]} next but the line starts at {(s1, v1, w1)}")
                while expected[cursor] != (s2, v2, w2):
                    cursor += 1
                cursor += 1
        if page in repairs:
            rows.append(["h", repairs[page][1]])
        if page > 2 and len(rows) != 15:
            fail(f"page {page} has {len(rows)} rows")
        first_text = next(r for r in rows if len(r) == 6)
        if (first_text[0], first_text[1]) != tanzil_pages[page - 1] or first_text[2] != 0:
            fail(f"page {page} starts at {first_text[:3]}, Tanzil says {tanzil_pages[page - 1]}")
        out_pages.append(rows)
    if cursor != len(expected):
        fail(f"only {cursor} of {len(expected)} words placed")

    # A header that isn't followed by the start of a surah on its page is out of
    # place in the dataset (e.g. page 207 lists Yunus's header first, though the
    # page starts mid-Tawbah and page 208 opens with Yunus's Bismillah). Move it
    # to the end of the page, where the next page's Bismillah continues it.
    def starts_surah(rows: list, index: int) -> bool:
        """The rows after `index` are optional Bismillahs then verse 1, word 0."""
        for r in rows[index + 1:]:
            if r == ["b"]:
                continue
            return len(r) == 6 and r[1] == 1 and r[2] == 0
        return False

    moved = 0
    for page_index, rows in enumerate(out_pages):
        next_page = out_pages[page_index + 1] if page_index + 1 < len(out_pages) else []
        index = 0
        while index < len(rows):
            row = rows[index]
            if row[0] != "h" or starts_surah(rows, index):
                index += 1
                continue
            # Only valid at the bottom of a page whose next page opens a surah.
            if not starts_surah([None] + next_page, 0):
                fail(f"page {page_index + 1}: header in an unexpected place")
            if index != len(rows) - 1:
                rows.append(rows.pop(index))
                moved += 1
                print(f"Moved a misplaced header on page {page_index + 1} to the bottom of the page")
                continue
            index += 1
    print(f"Moved {moved} misplaced headers")

    # A header belongs to the surah that starts right after it. (The dataset
    # labels headers at the bottom of a page with the previous surah's number.)
    flat = [(p, r) for p, rows in enumerate(out_pages, 1) for r in rows]
    corrected = 0
    for index, (page, row) in enumerate(flat):
        if row[0] == "h":
            following = next(r for _, r in flat[index + 1:] if len(r) == 6)
            if following[1] != 1 or following[2] != 0:
                fail(f"page {page}: header not followed by the start of a surah")
            if row[1] != following[0]:
                corrected += 1
                row[1] = following[0]
    print(f"Corrected {corrected} header labels at page ends")

    # Every surah starts right after its header (and Bismillah except 1 and 9).
    for index, (page, row) in enumerate(flat):
        if len(row) == 6 and row[1] == 1 and row[2] == 0:
            surah = row[0]
            before = [r for _, r in flat[max(0, index - 2):index]]
            if surah in (1, 9):
                ok = before and before[-1] == ["h", surah]
            else:
                ok = len(before) == 2 and before[0] == ["h", surah] and before[1] == ["b"]
            if not ok:
                fail(f"surah {surah} (page {page}) is not preceded by its header")

    OUT.write_text(json.dumps({
        "source": "Line breaks of the 604-page Madinah mushaf (Hafs) from github.com/zonetecde/mushaf-layout; "
                  "word indices refer to Niyat's Tanzil Uthmani text (verse 1 without the Bismillah).",
        "pages": out_pages,
    }, separators=(",", ":")))
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB): 604 pages, {cursor} words, all checks passed")


if __name__ == "__main__":
    main(Path(sys.argv[1]).resolve())
