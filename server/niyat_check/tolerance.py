"""What a correct recitation may do that a single reference text doesn't show.

Measured on 564 professional recordings (docs/research/asr-eval-muaalem.md),
most flags on correct recitation came from these, not from the model:

* stopping on a word in the middle of an ayah (مَرَضًا said مَرَضَا),
  and starting the next word with a hamza after the stop;
* going back to repeat words;
* holding a madd for any length the reading allows;
* sounds at the very edges of the clip (the word before, or the next ayah).
"""

from __future__ import annotations

import unicodedata

from quran_transcript import ReciterError

from .quran import Segment

# Counts the reader may choose, by rule (Hafs). A tolerance of one count is
# added for the model's own timing.
ALLOWED_COUNTS: dict[str, tuple[int, int]] = {
    "NormalMaddRule": (2, 2),
    "MonfaselMaddRule": (2, 5),
    "MottaselMaddRule": (4, 6),
    "MottaselMaddPauseRule": (4, 6),
    "LazemMaddRule": (6, 6),
    "AaredMaddRule": (2, 6),
    "LeenMaddRule": (2, 6),
}
COUNT_SLACK = 1

_HAMZA_WASL = "ٱ"  # ٱ


def _letters(text: str) -> list[int]:
    return [i for i, c in enumerate(text) if unicodedata.category(c).startswith("L")]


def _in_word_tail(error: ReciterError, segment: Segment) -> bool:
    """At the last letter of a word, its marks, or a tanween's alif after it."""
    for start, end in segment.word_spans():
        letters = [start + i for i in _letters(segment.text[start:end])]
        tail = letters[-2] + 1 if len(letters) > 1 else start
        if letters and tail <= error.uthmani_pos[0] <= end:
            return True
    return False


def _crosses_words(error: ReciterError, segment: Segment) -> bool:
    return " " in segment.text[error.uthmani_pos[0]:error.uthmani_pos[1]]


def _at_word_start_with_wasl(error: ReciterError, segment: Segment) -> bool:
    for start, end in segment.word_spans():
        if segment.text[start:end].startswith(_HAMZA_WASL) and error.uthmani_pos[0] in (start, max(start - 1, 0)):
            return True
    return False


def is_pause_form(error: ReciterError, segment: Segment) -> bool:
    """A stop on this word: the last vowel or the tanween dropped, ة said as
    ه, tanween fatha said as a long ā, the joining with the next word gone, or
    a hamza to start the word after. A lost letter is still a slip."""
    got, expected = error.preditected_ph, error.expected_ph
    kind, op = error.error_type, error.speech_error_type
    if kind in ("tashkeel", "tajweed") and _crosses_words(error, segment):
        return True
    if op == "insert" and got.startswith("ء"):
        return _at_word_start_with_wasl(error, segment)
    if not _in_word_tail(error, segment):
        return False
    if op == "insert":
        return set(got) <= {"ا"}
    if kind == "tashkeel":
        return not got or not expected or got[0] == expected[0]
    if kind == "normal" and op == "delete":
        return expected.startswith("ن") and len(expected) <= 2  # the tanween's nun
    if kind == "normal" and op == "replace":
        return expected.startswith("ت") and got.startswith("ه")  # ة said as ه
    return False


def is_allowed_length(error: ReciterError) -> bool:
    if error.error_type != "tajweed" or error.expected_len is None or error.predicted_len is None:
        return False
    rules = error.ref_tajweed_rules or []
    for rule in rules:
        low, high = ALLOWED_COUNTS.get(type(rule).__name__, (rule.golden_len, rule.golden_len))
        if low - COUNT_SLACK <= error.predicted_len <= high + COUNT_SLACK:
            return True
    return False


def is_repeat(inserted: str, segment: Segment, before: int) -> bool:
    """Extra sounds that are words already recited (going back to repeat)."""
    return len(inserted) >= 4 and inserted in segment.phonemes[: max(before, 0) + len(inserted)]
