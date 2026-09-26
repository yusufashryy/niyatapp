#!/usr/bin/env python3
"""Builds Niyat/Resources/Quran/recognition-forms.json: extra spellings that
live recitation tracking accepts for a few Uthmani words. Recognition only:
nothing here is ever displayed, and the Qur'an text is not changed.

Two kinds of entries, keyed "surah:verse:word" (word = 0-based index in the
displayed Uthmani verse, without the Bismillah of verse 1):
- Everyday spelling, from Tanzil's own Imla'i edition of the same Hafs text,
  for words whose Uthmani spelling differs a lot (ٱلرِّبَوٰا۟ / الربا,
  يَبْنَؤُمَّ / يا ابن أم).
- The disjoined letters that open 29 surahs (الٓمٓ, كٓهيعٓصٓ ...), which are
  recited by their letter names (alif lam mim).

Forms are letters only, normalised exactly like the app's matcher.
"""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UTHMANI = json.loads((ROOT / "Niyat/Resources/Quran/quran-uthmani.json").read_text())
IMLAEI = json.loads((ROOT / "Niyat/Resources/Quran/quran-imlaei.json").read_text())
OUT = ROOT / "Niyat/Resources/Quran/recognition-forms.json"


def is_letter(v: int) -> bool:
    return 0x0621 <= v <= 0x063A or 0x0641 <= v <= 0x064A or v in (0x0671, 0x066E, 0x066F, 0x06A1, 0x06A2, 0x06A7, 0x06A8, 0x06BA)


def normalize(word: str) -> str:
    """Same as RecitationMatcher.normalize in the app."""
    out = []
    for ch in word:
        v = ord(ch)
        if v in (0x0622, 0x0623, 0x0625, 0x0671, 0x0672, 0x0673, 0x0670):
            out.append("ا")
        elif v in (0x0649, 0x0626):
            out.append("ي")
        elif v == 0x0629:
            out.append("ه")
        elif v == 0x0624:
            out.append("و")
        elif v in (0x0621, 0x0640):
            continue
        elif is_letter(v):
            out.append(ch)
    return "".join(out)


def distance(a: str, b: str) -> int:
    previous = list(range(len(b) + 1))
    for i in range(1, len(a) + 1):
        current = [i] + [0] * len(b)
        for j in range(1, len(b) + 1):
            current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + (a[i - 1] != b[j - 1]))
        previous = current
    return previous[-1]


def similar(a: str, b: str) -> bool:
    """Same as RecitationMatcher.similar."""
    if a == b:
        return True
    allowed = max(1, max(len(a), len(b)) // 4)
    return abs(len(a) - len(b)) <= allowed and distance(a, b) <= allowed


def words(text: str) -> list[str]:
    return [t for t in text.split(" ") if any(is_letter(ord(c)) for c in t)]


def verse_words(source, surah: int, verse: int) -> list[str]:
    result = words(source[str(surah)][verse - 1]["text"])
    if verse == 1 and surah not in (1, 9):
        result = result[4:]  # the Bismillah (4 words in both editions)
    return result


def align(uthmani: list[str], imlaei: list[str]):
    """Pairs each Uthmani word with 1-3 Imla'i words (or two Uthmani words
    with one Imla'i word), preferring similar pairs."""
    n, m, inf = len(uthmani), len(imlaei), float("inf")
    cost = [[inf] * (m + 1) for _ in range(n + 1)]
    back = [[None] * (m + 1) for _ in range(n + 1)]
    cost[0][0] = 0
    for i in range(n + 1):
        for j in range(m + 1):
            if cost[i][j] == inf:
                continue
            for k in (1, 2, 3):
                if i < n and j + k <= m:
                    joined = "".join(imlaei[j:j + k])
                    c = cost[i][j] + (0 if similar(uthmani[i], joined) else 1) + 0.01 * (k - 1)
                    if c < cost[i + 1][j + k]:
                        cost[i + 1][j + k], back[i + 1][j + k] = c, (i, j, k)
            if i + 1 < n and j < m:
                c = cost[i][j] + (0 if similar(uthmani[i] + uthmani[i + 1], imlaei[j]) else 1) + 0.02
                if c < cost[i + 2][j + 1]:
                    cost[i + 2][j + 1], back[i + 2][j + 1] = c, (i, j, -1)
    pairs, i, j = [], n, m
    while (i, j) != (0, 0):
        pi, pj, k = back[i][j]
        if k != -1:
            pairs.append((pi, "".join(imlaei[pj:pj + k])))
        i, j = pi, pj
    return pairs


# Letter names for the disjoined letters (al-huruf al-muqatta'at).
LETTER_NAMES = {"ا": "الف", "ل": "لام", "م": "ميم", "ص": "صاد", "ر": "را", "ك": "كاف", "ه": "ها",
                "ي": "يا", "ع": "عين", "ط": "طا", "س": "سين", "ح": "حا", "ق": "قاف", "ن": "نون"}
DISJOINED = [(2, 1), (3, 1), (7, 1), (10, 1), (11, 1), (12, 1), (13, 1), (14, 1), (15, 1), (19, 1), (20, 1),
             (26, 1), (27, 1), (28, 1), (29, 1), (30, 1), (31, 1), (32, 1), (36, 1), (38, 1), (40, 1), (41, 1),
             (42, 1), (42, 2), (43, 1), (44, 1), (45, 1), (46, 1), (50, 1), (68, 1)]


def main() -> None:
    forms: dict[str, list[str]] = {}
    for surah in range(1, 115):
        for verse in range(1, len(UTHMANI[str(surah)]) + 1):
            uthmani = [normalize(w) for w in verse_words(UTHMANI, surah, verse)]
            imlaei = [normalize(w) for w in verse_words(IMLAEI, surah, verse)]
            for index, everyday in align(uthmani, imlaei):
                if not similar(uthmani[index], everyday):
                    forms.setdefault(f"{surah}:{verse}:{index}", []).append(everyday)
    for surah, verse in DISJOINED:
        letters = normalize(verse_words(UTHMANI, surah, verse)[0])
        spoken = "".join(LETTER_NAMES[c] for c in letters)
        forms.setdefault(f"{surah}:{verse}:0", []).append(spoken)
    OUT.write_text(json.dumps({
        "source": "Everyday spellings from Tanzil's Imla'i edition; letter names for the disjoined letters. "
                  "Recognition only, never displayed.",
        "forms": forms,
    }, ensure_ascii=False, separators=(",", ":")))
    print(f"Wrote {OUT}: {len(forms)} words with extra forms")


if __name__ == "__main__":
    main()
