#!/usr/bin/env python3
"""Try a Qur'an speech recognition model on your own recordings, on your Mac.

Transcribes each recording and compares it, word by word, with the verses you
say you recited: words missed, words that differ, extra words, and words whose
harakat (fatha, kasra, damma, sukun, shadda, tanween) differ.

Nothing here goes into the app. It's for deciding whether a model is good
enough before building it in. See docs/research/recitation-roadmap.md.

One-time setup (Terminal):
    brew install ffmpeg
    python3 -m pip install sherpa-onnx numpy
    mkdir -p ~/niyat-asr && cd ~/niyat-asr
    curl -LO https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main/qurankarim-fastconformer-mixed.onnx
    curl -LO https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main/tokens.txt

Then, from the niyatapp folder, for a Voice Memo of Al-Fatiha:
    python3 scripts/try_quran_asr.py ~/Desktop/fatiha.m4a --surah 1
and for Al-Baqarah 1 to 5:
    python3 scripts/try_quran_asr.py ~/Desktop/baqarah.m4a --surah 2 --from 1 --to 5
"""

import argparse
import difflib
import json
import os
import subprocess
import sys
import time
import unicodedata

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
UTHMANI = os.path.join(ROOT, "Niyat", "Resources", "Quran", "quran-uthmani.json")
DEFAULT_DIR = os.path.expanduser("~/niyat-asr")

# Short-vowel marks compared for "harakat": fathatan, dammatan, kasratan,
# fatha, damma, kasra, shadda, sukun. The Uthmani round sukun (U+06E1) counts as sukun.
HARAKAT = set("ًٌٍَُِّْ")
SUKUN_UTHMANI = "ۡ"

# Letter forms folded together, as in the app's RecitationMatcher.normalize.
FOLD = {
    "آ": "ا", "أ": "ا", "إ": "ا", "ٱ": "ا",
    "ٲ": "ا", "ٳ": "ا", "ٰ": "ا",  # alef forms, dagger alef
    "ى": "ي", "ئ": "ي",  # alef maqsura, hamza on ya
    "ة": "ه",  # ta marbuta
    "ؤ": "و",  # hamza on waw
}
DROP = {"ء", "ـ"}  # hamza, tatweel


def is_letter(ch):
    return unicodedata.category(ch) == "Lo"


def letters(word):
    """Letters only, spelling variants folded (for finding the place)."""
    out = []
    for ch in word:
        if ch in DROP:
            continue
        ch = FOLD.get(ch, ch)
        if is_letter(ch):
            out.append(ch)
    return "".join(out)


def harakat(word):
    """The sequence of short-vowel marks in a word (for the harakat check)."""
    return "".join("ْ" if ch == SUKUN_UTHMANI else ch
                   for ch in word if ch in HARAKAT or ch == SUKUN_UTHMANI)


def words(text):
    return [w for w in text.split() if letters(w)]


def load_audio(path):
    """Any audio file to 16 kHz mono floats, using ffmpeg."""
    import numpy as np
    raw = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", path, "-ac", "1", "-ar", "16000", "-f", "f32le", "-"],
        check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def expected_words(surah, first, last):
    data = json.load(open(UTHMANI, encoding="utf-8"))
    verses = data[str(surah)]
    last = last or len(verses)
    result = []
    for verse in verses[first - 1:last]:
        result += [(verse["verse"], w) for w in words(verse["text"])]
    return result


def compare(expected, heard):
    """Line the words up by their letters, then check harakat on matched words."""
    want = [letters(w) for _, w in expected]
    got = [letters(w) for w in heard]
    rows = []
    stats = {"correct": 0, "haraka": 0, "different": 0, "missed": 0, "extra": 0}
    matcher = difflib.SequenceMatcher(a=want, b=got, autojunk=False)
    for op, a0, a1, b0, b1 in matcher.get_opcodes():
        if op == "equal":
            for i, j in zip(range(a0, a1), range(b0, b1)):
                verse, word = expected[i]
                same = harakat(word) == harakat(heard[j])
                stats["correct" if same else "haraka"] += 1
                rows.append(("ok" if same else "HARAKA", verse, word, heard[j]))
        elif op == "replace":
            pairs = max(a1 - a0, b1 - b0)
            for k in range(pairs):
                i, j = a0 + k, b0 + k
                if i < a1 and j < b1:
                    stats["different"] += 1
                    rows.append(("DIFFERENT", expected[i][0], expected[i][1], heard[j]))
                elif i < a1:
                    stats["missed"] += 1
                    rows.append(("MISSED", expected[i][0], expected[i][1], ""))
                else:
                    stats["extra"] += 1
                    rows.append(("EXTRA", "", "", heard[j]))
        elif op == "delete":
            for i in range(a0, a1):
                stats["missed"] += 1
                rows.append(("MISSED", expected[i][0], expected[i][1], ""))
        elif op == "insert":
            for j in range(b0, b1):
                stats["extra"] += 1
                rows.append(("EXTRA", "", "", heard[j]))
    return rows, stats


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("audio", nargs="+", help="recordings (m4a, wav, mp3...)")
    parser.add_argument("--surah", type=int, help="surah you recited, to compare against")
    parser.add_argument("--from", dest="first", type=int, default=1, help="first ayah (default 1)")
    parser.add_argument("--to", dest="last", type=int, help="last ayah (default: end of surah)")
    parser.add_argument("--model", default=os.path.join(DEFAULT_DIR, "qurankarim-fastconformer-mixed.onnx"))
    parser.add_argument("--tokens", default=os.path.join(DEFAULT_DIR, "tokens.txt"))
    args = parser.parse_args()

    try:
        import sherpa_onnx
    except ImportError:
        sys.exit("Install the recogniser first:  python3 -m pip install sherpa-onnx numpy")
    for path in (args.model, args.tokens):
        if not os.path.exists(path):
            sys.exit(f"Missing {path}. See the setup steps at the top of this script.")

    started = time.time()
    recognizer = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
        model=args.model, tokens=args.tokens, num_threads=4, sample_rate=16000, feature_dim=80,
        decoding_method="greedy_search")
    print(f"Model loaded in {time.time() - started:.1f} s\n")

    totals = {"correct": 0, "haraka": 0, "different": 0, "missed": 0, "extra": 0}
    for path in args.audio:
        samples = load_audio(path)
        seconds = len(samples) / 16000
        started = time.time()
        stream = recognizer.create_stream()
        stream.accept_waveform(16000, samples)
        recognizer.decode_stream(stream)
        took = time.time() - started
        text = stream.result.text.strip()
        print(f"== {os.path.basename(path)}  ({seconds:.1f} s of audio, recognised in {took:.2f} s)")
        print(f"Heard: {text}\n")

        if not args.surah:
            continue
        rows, stats = compare(expected_words(args.surah, args.first, args.last), words(text))
        for label, verse, want, got in rows:
            if label != "ok":
                print(f"  {label:<9} {f'{args.surah}:{verse}' if verse else '':<7} expected {want or '-':<20} heard {got or '-'}")
        checked = sum(stats.values()) - stats["extra"]
        print(f"\n  Words: {checked}  correct {stats['correct']}  harakat differ {stats['haraka']}  "
              f"different {stats['different']}  missed {stats['missed']}  extra {stats['extra']}\n")
        for key in totals:
            totals[key] += stats[key]

    if args.surah and len(args.audio) > 1:
        checked = sum(totals.values()) - totals["extra"]
        print(f"All recordings: {checked} words, correct {totals['correct']}, harakat differ {totals['haraka']}, "
              f"different {totals['different']}, missed {totals['missed']}, extra {totals['extra']}")
    print("Compare the flagged words with what you know you said: real mistakes the model caught, "
          "and correct words it flagged (false alarms), are what decide whether it's good enough.")


if __name__ == "__main__":
    main()
