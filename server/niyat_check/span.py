"""Which words the recording covers.

The app says where the reciter is; they may have gone back to the start of
the ayah (or the one before) and stopped anywhere ahead. Every start and end
is tried and the text that sounds closest to the recording wins.
"""

from __future__ import annotations

from dataclasses import dataclass

from rapidfuzz import fuzz
from rapidfuzz.distance import Levenshtein

from .quran import Place, ayah_words, segments, window

# Beyond this the recording isn't the text around the place (wrong surah, not
# Qur'an, or too unclear).
NOT_FOUND_DISTANCE = 0.55
# Going back must fit clearly better than the place the app gave: a repeated
# phrase shouldn't pull the start back to the ayah before.
GOING_BACK_COST = (0.0, 0.03, 0.08)
LEAD_WEIGHT = 0.25


@dataclass(frozen=True)
class Span:
    start: Place
    end: Place
    distance: float


def start_candidates(place: Place) -> list[Place]:
    out = [place]
    if place.word > 0:
        out.append(Place(place.surah, place.ayah, 0))
    if place.ayah > 1:
        out.append(Place(place.surah, place.ayah - 1, 0))
    return out


def _phonemes(start: Place, end: Place) -> str:
    return "".join(s.phonemes for s in segments(start, end))


def score(heard: str, reference: str) -> float:
    """How far the recording is from the text, 0 (same) to 1. Sound before the
    first word costs a quarter: it's often the words before, or a repeat, but
    when the reciter went back the earlier start should still win."""
    def cost(lead: int) -> float:
        rest = heard[lead:]
        return (Levenshtein.distance(reference, rest) + LEAD_WEIGHT * lead) / max(len(reference), len(rest), 1)

    best = cost(0)
    if len(heard) > len(reference) and reference:
        # Where the text fits best inside the recording.
        lead = fuzz.partial_ratio_alignment(reference, heard).dest_start
        if lead:
            best = min(best, cost(lead))
    return best


def find_span(heard: str, place: Place, max_words: int) -> Span | None:
    """The closest stretch of text, or None when nothing is close enough."""
    if not heard:
        return None
    best: Span | None = None
    for rank, start in enumerate(start_candidates(place)):
        # Going back means the words before the place are recited again.
        extra = 0 if rank == 0 else len(window_between(start, place))
        cost = GOING_BACK_COST[min(rank, len(GOING_BACK_COST) - 1)]
        for end in window(start, max_words + extra):
            distance = score(heard, _phonemes(start, end)) + cost
            # Prefer the place the app gave, then the longer stretch.
            if best is None or distance < best.distance - 1e-9 or (
                abs(distance - best.distance) < 1e-9 and start == best.start
            ):
                best = Span(start, end, distance)
    if best is None or best.distance > NOT_FOUND_DISTANCE:
        return None
    return best


def window_between(start: Place, place: Place) -> list[Place]:
    """Words from `start` up to (not including) `place`."""
    out = []
    ayah, word = start.ayah, start.word
    while (ayah, word) < (place.ayah, place.word):
        if word >= len(ayah_words(start.surah, ayah)):
            ayah, word = ayah + 1, 0
            continue
        out.append(Place(start.surah, ayah, word))
        word += 1
    return out
