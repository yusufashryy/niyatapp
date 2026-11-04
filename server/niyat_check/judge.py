"""Word-by-word results for one recording: compare what was heard with the
text it covers, drop what a correct recitation may do, and say what's left."""

from __future__ import annotations

from dataclasses import dataclass, field

from quran_transcript import ReciterError, explain_error
from rapidfuzz.distance import Levenshtein

from . import feedback, tolerance
from .quran import Place, Segment
from .span import Span
from .quran import segments as text_segments

# Below this average certainty the model's own hearing is doubtful: flags are
# shown as "not sure" rather than as mistakes.
CONFIDENT = 0.80
# This share of a word's sounds missing means the word was skipped.
SKIPPED_SHARE = 0.8

# correct: as written. unsure: the model wasn't sure what it heard.
# check: a vowel or tajweed point worth checking (amber, never red).
# mistake: a letter was different or missing. skipped: the word wasn't heard.
RANK = {"correct": 0, "unsure": 1, "check": 2, "mistake": 3, "skipped": 4}


@dataclass
class WordResult:
    place: Place
    result: str = "correct"
    notes: list[dict] = field(default_factory=list)

    def raise_to(self, result: str, note: dict | None = None) -> None:
        if RANK[result] > RANK[self.result]:
            self.result = result
        if note and note not in self.notes and len(self.notes) < 3:
            self.notes.append(note)


def split_heard(heard: str, segs: list[Segment]) -> list[str]:
    """The part of the recording that belongs to each segment."""
    reference = "".join(s.phonemes for s in segs)
    ops = [op for op in Levenshtein.opcodes(reference, heard) if op.tag != "insert"]

    def heard_index(ref_index: int) -> int:
        if ref_index >= len(reference):
            return len(heard)
        for op in ops:
            if op.src_start <= ref_index < op.src_end:
                if op.tag == "delete":
                    return op.dest_start
                return min(op.dest_start + ref_index - op.src_start, op.dest_end)
        return len(heard)

    cuts, total = [0], 0
    for s in segs[:-1]:
        total += len(s.phonemes)
        cuts.append(heard_index(total))
    cuts.append(len(heard))
    return [heard[cuts[i]:cuts[i + 1]] for i in range(len(segs))]


def _word_phoneme_ranges(seg: Segment) -> list[tuple[int, int]]:
    ranges = []
    for start, end in seg.word_spans():
        pos = [m.pos for m in seg.script.mappings[start:end] if m.pos and m.pos[1] > m.pos[0]]
        ranges.append((min(p[0] for p in pos), max(p[1] for p in pos)) if pos else (0, 0))
    return ranges


def _filtered(errors: list[ReciterError], seg: Segment, first_seg: bool, last_seg: bool) -> list[ReciterError]:
    end = len(seg.phonemes)
    kept, i = [], 0
    while i < len(errors):
        e = errors[i]
        if e.speech_error_type == "insert":
            # Consecutive inserted groups are one stretch of extra sound.
            j, inserted = i, ""
            while j < len(errors) and errors[j].speech_error_type == "insert" and errors[j].ph_pos == e.ph_pos:
                inserted += errors[j].preditected_ph
                j += 1
            at_edge = (first_seg and e.ph_pos[0] == 0) or (last_seg and e.ph_pos[0] >= end)
            if not at_edge and not tolerance.is_repeat(inserted, seg, e.ph_pos[0]):
                kept.extend(x for x in errors[i:j] if not tolerance.is_pause_form(x, seg))
            i = j
            continue
        if not tolerance.is_pause_form(e, seg) and not tolerance.is_allowed_length(e):
            kept.append(e)
        i += 1
    return kept


def judge(heard: str, confidence: float, span: Span) -> list[WordResult]:
    segs = text_segments(span.start, span.end)
    parts = split_heard(heard, segs)
    results: list[WordResult] = []
    for n, (seg, part) in enumerate(zip(segs, parts)):
        words = [WordResult(Place(seg.surah, seg.ayah, seg.first + k)) for k in range(seg.last - seg.first + 1)]
        errors = explain_error(seg.text, seg.phonemes, part, seg.script.mappings) if part else []
        errors = _filtered(errors, seg, n == 0, n == len(segs) - 1)
        ranges = _word_phoneme_ranges(seg)
        missing = [0] * len(words)
        for e in errors:
            k = min(max(seg.word_at(e.uthmani_pos[0]) - seg.first, 0), len(words) - 1)
            if e.speech_error_type == "delete":
                missing[k] += e.ph_pos[1] - e.ph_pos[0]
            kind = {"tajweed": "check", "tashkeel": "check"}.get(e.error_type, "mistake")
            if e.speech_error_type == "insert":
                kind = "unsure"
            if kind == "mistake" and confidence < CONFIDENT:
                kind = "unsure"
            words[k].raise_to(kind, feedback.note(e))
        for k, (lo, hi) in enumerate(ranges):
            if not part or (hi > lo and missing[k] >= SKIPPED_SHARE * (hi - lo)):
                words[k].raise_to("skipped", {"kind": "missing", "text": "This word wasn't heard."})
        results.extend(words)
    # The reciter stopped before these: words at the end that weren't heard
    # at all aren't part of what was recited.
    while len(results) > 1 and results[-1].result == "skipped":
        results.pop()
    return results
