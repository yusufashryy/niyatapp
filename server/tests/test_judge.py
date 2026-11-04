"""Matching and judging, with recitations built from the reference text itself
(so no model is needed): a perfect recitation, and the same with each kind of
mistake or allowed variation."""

from quran_transcript import quran_phonetizer

from niyat_check.judge import judge
from niyat_check.quran import MOSHAF, Place, ayah_words, segment, segments
from niyat_check.span import find_span


def said(*texts: str) -> str:
    """Each text phonetized on its own (a pause after each)."""
    return "".join(quran_phonetizer(t, MOSHAF, remove_spaces=True).phonemes for t in texts)


def ayah(surah: int, number: int) -> str:
    return " ".join(ayah_words(surah, number))


def results(heard: str, place: Place, certainty: float = 0.95) -> dict[tuple[int, int, int], str]:
    span = find_span(heard, place, 40)
    assert span is not None
    return {(w.place.surah, w.place.ayah, w.place.word): w.result for w in judge(heard, certainty, span)}


def flagged(r: dict) -> dict:
    return {k: v for k, v in r.items() if v != "correct"}


def test_perfect_recitation_covers_the_ayat_and_flags_nothing():
    heard = said(ayah(1, 2), ayah(1, 3), ayah(1, 4))
    r = results(heard, Place(1, 2, 0))
    assert flagged(r) == {}
    assert min(r) == (1, 2, 0) and max(r) == (1, 4, 2)


def test_stops_where_the_recording_ends():
    heard = said(ayah(1, 2))
    r = results(heard, Place(1, 2, 0))
    assert max(r) == (1, 2, len(ayah_words(1, 2)) - 1)


def test_stopping_mid_ayah_is_allowed():
    words = ayah_words(2, 10)
    stop = words.index("مَرَضًۭا") + 1
    heard = said(" ".join(words[:stop]), " ".join(words[stop:]))
    assert flagged(results(heard, Place(2, 10, 0))) == {}


def test_repeating_words_is_allowed():
    words = ayah_words(2, 2)
    heard = said(" ".join(words[:4])) + said(ayah(2, 2))
    r = results(heard, Place(2, 2, 0))
    assert [v for v in r.values() if v in ("mistake", "skipped")] == []


def test_a_skipped_word_is_found():
    words = list(ayah_words(1, 2))
    heard = said(" ".join(words[:1] + words[2:]))
    r = results(heard, Place(1, 2, 0))
    assert r[(1, 2, 1)] == "skipped"
    assert all(v == "correct" for k, v in r.items() if k != (1, 2, 1))


def test_a_wrong_letter_is_a_mistake():
    seg = segment(1, 4, 0, 2)
    heard = seg.phonemes.replace("لِ", "دِ", 1)  # مَالِكِ said مَادِكِ
    r = results(heard, Place(1, 4, 0))
    assert r[(1, 4, 0)] == "mistake"


def test_doubtful_hearing_is_unsure_not_a_mistake():
    heard = segment(1, 4, 0, 2).phonemes.replace("لِ", "دِ", 1)
    assert results(heard, Place(1, 4, 0), certainty=0.5)[(1, 4, 0)] == "unsure"


def test_any_allowed_length_of_the_final_madd_passes():
    base = segment(1, 4, 0, 2).phonemes  # ...ددِۦۦۦۦن (four counts)
    assert "ۦۦۦۦن" in base
    for counts in (2, 6):
        heard = base.replace("ۦۦۦۦن", "ۦ" * counts + "ن")
        assert flagged(results(heard, Place(1, 4, 0))) == {}


def test_starting_the_ayah_again_is_followed():
    heard = said(ayah(1, 2))
    r = results(heard, Place(1, 2, 2))
    assert min(r) == (1, 2, 0)
    assert flagged(r) == {}


def test_another_surah_is_not_found():
    assert find_span(said(ayah(114, 1)), Place(2, 255, 0), 40) is None


def test_segments_split_per_ayah():
    segs = segments(Place(1, 6, 1), Place(1, 7, 2))
    assert [(s.ayah, s.first, s.last) for s in segs] == [(6, 1, 2), (7, 0, 2)]


def test_words_after_the_recitation_stopped_are_left_out():
    # Heard 1:2 only, but the closest stretch ran on: nothing after 1:2 is marked.
    heard = said(ayah(1, 2))
    span = find_span(heard, Place(1, 2, 0), 40)
    from niyat_check.span import Span
    longer = Span(span.start, Place(1, 3, 1), span.distance)
    words = judge(heard, 0.95, longer)
    assert max((w.place.surah, w.place.ayah, w.place.word) for w in words) == (1, 2, 3)


def test_another_surah_while_reciting_is_not_taken_for_this_one():
    # On Al-Faatiha, reciting An-Nas: the check says "not here", so the app looks it up.
    from niyat_check.find import find
    heard = said(ayah(114, 1), ayah(114, 2), ayah(114, 3))
    assert find_span(heard, Place(1, 3, 0), 40) is None
    places = find(heard)
    assert places and (places[0].start.surah, places[0].start.ayah) == (114, 1)
