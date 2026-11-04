"""Short notes for the reader, in plain words.

Only fixed sentences and the letters involved; never generated text, and
never a ruling: notes are prompts to check with the text or a teacher.
"""

from __future__ import annotations

from quran_transcript import ReciterError

_VOWELS = {"َ": "fatha", "ُ": "damma", "ِ": "kasra"}
# Muaalem's phoneme alphabet writes a few sounds with their own signs.
_SOUND_LETTER = {"ۦ": "ي", "ۥ": "و", "ں": "ن", "۾": "م", "ٲ": "ء"}
# Marks that colour a sound rather than being one: qalqalah, sakt, imalah,
# a shortened damma.
_MARKS = {"ڇ", "ۜ", "ؙ", "۪", "ـ"}


def _letter(ph: str) -> str:
    for c in ph:
        if c in _VOWELS or c in _MARKS:
            continue
        return _SOUND_LETTER.get(c, c)
    return ""


def _vowel(ph: str) -> str:
    for c in ph:
        if c in _VOWELS:
            return _VOWELS[c]
    return "no vowel"


def _rule(error: ReciterError) -> tuple[str, str]:
    rule = (error.ref_tajweed_rules or error.missing_tajweed_rules or [None])[0]
    if rule is None:
        return "Tajweed", "تجويد"
    return rule.name.en, rule.name.ar


def note(error: ReciterError) -> dict:
    """{kind, text, rule?}: kind is letter, missing, extra, haraka or tajweed."""
    expected, got = _letter(error.expected_ph), _letter(error.preditected_ph)
    if error.error_type == "tajweed":
        en, ar = _rule(error)
        if error.expected_len is not None and error.predicted_len is not None:
            text = f"{en}: held for about {error.predicted_len} counts; usually {error.expected_len}."
        else:
            text = f"{en} wasn't clear."
        return {"kind": "tajweed", "text": text, "rule": {"en": en, "ar": ar}}
    if error.error_type == "tashkeel":
        if _vowel(error.preditected_ph) == _vowel(error.expected_ph):
            doubled = len(error.expected_ph) > len(error.preditected_ph)
            return {"kind": "haraka", "text": f"Check the shadda on «{expected or got}»: "
                                              f"{'said once' if doubled else 'doubled'}, "
                                              f"written {'doubled' if doubled else 'once'}."}
        return {"kind": "haraka",
                "text": f"Check the vowel on «{expected or got}»: heard {_vowel(error.preditected_ph)}, "
                        f"written {_vowel(error.expected_ph)}."}
    if error.speech_error_type == "insert":
        return {"kind": "extra", "text": f"An extra sound was heard{f' («{got}»)' if got else ''}."}
    if error.speech_error_type == "delete":
        return {"kind": "missing", "text": f"«{expected}» wasn't heard." if expected else "A sound wasn't heard."}
    if expected and got and expected != got:
        return {"kind": "letter", "text": f"Heard «{got}» where «{expected}» is written."}
    return {"kind": "letter", "text": "This part sounded different."}
