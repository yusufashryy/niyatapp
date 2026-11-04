"""The Qur'an text the server checks against, word by word.

Words are numbered from 0 within each ayah, as the app numbers the Uthmani
text it shows (checked for all 6,236 ayat). The app shows the basmala as a
header, not as words of the first ayah, so there's no offset.
"""

from __future__ import annotations

import unicodedata
from dataclasses import dataclass
from functools import lru_cache

from quran_transcript import Aya, MoshafAttributes, QuranPhoneticScriptOutput, quran_phonetizer

# Hafs ʿan ʿAsim by way of ash-Shatibiyyah, the most common way it's taught.
# Lengths the reciter may choose are accepted by the matcher (see tolerance.py).
MOSHAF = MoshafAttributes(
    rewaya="hafs",
    madd_monfasel_len=4,
    madd_mottasel_len=4,
    madd_mottasel_waqf=4,
    madd_aared_len=4,
)

SURAH_COUNT = 114


@dataclass(frozen=True)
class Place:
    surah: int
    ayah: int
    word: int


def _has_letter(piece: str) -> bool:
    return any(unicodedata.category(c).startswith("L") for c in piece)


@lru_cache(maxsize=8192)
def ayah_text(surah: int, ayah: int) -> str:
    return Aya(surah, ayah).get().uthmani


@lru_cache(maxsize=128)
def ayah_count(surah: int) -> int:
    return Aya(surah, 1).get().num_ayat_in_sura


@lru_cache(maxsize=8192)
def ayah_words(surah: int, ayah: int) -> tuple[str, ...]:
    return tuple(p for p in ayah_text(surah, ayah).split(" ") if _has_letter(p))


def is_valid(place: Place) -> bool:
    if not 1 <= place.surah <= SURAH_COUNT:
        return False
    if not 1 <= place.ayah <= ayah_count(place.surah):
        return False
    return 0 <= place.word < len(ayah_words(place.surah, place.ayah))


def window(start: Place, max_words: int) -> list[Place]:
    """Up to `max_words` words from `start`, on to the end of the surah."""
    out: list[Place] = []
    ayah, word = start.ayah, start.word
    while len(out) < max_words and ayah <= ayah_count(start.surah):
        words = ayah_words(start.surah, ayah)
        while word < len(words) and len(out) < max_words:
            out.append(Place(start.surah, ayah, word))
            word += 1
        ayah, word = ayah + 1, 0
    return out


@dataclass(frozen=True)
class Segment:
    """Part of one ayah, phonetized on its own: a reciter stops at the end of
    each ayah (and at the end of what they recited), so each segment ends in
    its pause form."""

    surah: int
    ayah: int
    first: int
    last: int  # inclusive
    text: str
    script: QuranPhoneticScriptOutput

    @property
    def phonemes(self) -> str:
        return self.script.phonemes

    def word_spans(self) -> list[tuple[int, int]]:
        """Character range of each word in `text`."""
        spans, pos = [], 0
        for piece in self.text.split(" "):
            if _has_letter(piece):
                spans.append((pos, pos + len(piece)))
            pos += len(piece) + 1
        return spans

    def word_at(self, char: int) -> int:
        """Index (in the ayah) of the word holding a character, or the nearest before it."""
        spans = self.word_spans()
        for i, (s, e) in enumerate(spans):
            if char < e:
                return self.first + (i if char >= s else max(i - 1, 0))
        return self.last


@lru_cache(maxsize=16384)
def segment(surah: int, ayah: int, first: int, last: int) -> Segment:
    text = " ".join(ayah_words(surah, ayah)[first:last + 1])
    return Segment(surah, ayah, first, last, text, quran_phonetizer(text, MOSHAF, remove_spaces=True))


def segments(start: Place, end: Place) -> list[Segment]:
    """The text from `start` to `end` (inclusive), one segment per ayah."""
    out = []
    for ayah in range(start.ayah, end.ayah + 1):
        first = start.word if ayah == start.ayah else 0
        last = end.word if ayah == end.ayah else len(ayah_words(start.surah, ayah)) - 1
        out.append(segment(start.surah, ayah, first, last))
    return out
