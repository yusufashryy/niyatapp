"""Where in the Qur'an a recording is, without being told (like a song
finder): Muaalem's phonetic search finds candidate places, then each is
scored against the phonetic text of that stretch and the closest wins."""

from __future__ import annotations

from dataclasses import dataclass
from functools import lru_cache

from quran_transcript import NoPhonemesSearchResult, PhoneticSearch

from .quran import Place, ayah_words, is_valid, segments
from .span import score

# How loosely the search matches (a share of the query's sounds), and how
# close the best place must be to the recording to count as found.
SEARCH_ERROR_RATIO = 0.25
FOUND_DISTANCE = 0.45
# Other places this close to the best are offered too (shared phrases).
ALTERNATIVE_MARGIN = 0.04
MAX_PLACES = 3
# Shorter than this says too little to tell surahs apart.
MIN_SOUNDS = 12


@dataclass(frozen=True)
class Found:
    start: Place
    end: Place
    distance: float


@lru_cache(maxsize=1)
def _search() -> PhoneticSearch:
    return PhoneticSearch()


def _end_word(surah: int, ayah: int, word: int) -> Place:
    return Place(surah, ayah, min(word, len(ayah_words(surah, ayah)) - 1))


def find(heard: str) -> list[Found]:
    """The likeliest places, best first (empty when nothing is close)."""
    if len(heard) < MIN_SOUNDS:
        return []
    try:
        results = _search().search(heard, error_ratio=SEARCH_ERROR_RATIO)
    except (NoPhonemesSearchResult, ValueError):
        return []
    scored: dict[tuple[int, int], Found] = {}
    for r in results:
        start = Place(r.start.sura_idx, r.start.aya_idx, r.start.uthmani_word_idx)
        end = _end_word(r.end.sura_idx, r.end.aya_idx, r.end.uthmani_word_idx)
        if start.surah != end.surah or not is_valid(start) or not is_valid(end) or (end.ayah, end.word) < (start.ayah, start.word):
            continue
        reference = "".join(s.phonemes for s in segments(start, end))
        found = Found(start, end, score(heard, reference))
        key = (start.surah, start.ayah)
        if key not in scored or found.distance < scored[key].distance:
            scored[key] = found
    ranked = sorted(scored.values(), key=lambda f: f.distance)
    if not ranked or ranked[0].distance > FOUND_DISTANCE:
        return []
    best = ranked[0].distance
    return [f for f in ranked if f.distance <= best + ALTERNATIVE_MARGIN][:MAX_PLACES]
