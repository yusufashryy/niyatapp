#!/usr/bin/env python3
"""Evaluate an open Qur'an speech recognition model for Niyat (research only).

Model: TheGreatQuran/QuranKarim-SpeechToText-onnxModel (NVIDIA FastConformer
CTC fine-tuned on tarteel-ai/everyayah, run with sherpa-onnx). Nothing here
goes into the app. Results are written up in docs/research/asr-eval-qurankarim.md.

Two modes:

  text   Needs no model and no audio. Measures the "spelling floor": how many
         words the comparison would flag even if the model heard everything
         right but wrote it in everyday (Imla'i) spelling instead of Uthmani,
         and how well the wrong-verse / skipped-word checks can work at best,
         with simulated recognition errors.
             python3 scripts/eval_quran_asr.py text

  audio  The real evaluation. Downloads per-ayah audio, transcribes it with
         the mixed and q8 models, scores it, adds noise / phone / speed
         variants, runs the synthetic mistake tests and times decoding.
             python3 scripts/eval_quran_asr.py audio --out ~/niyat-asr/eval
         Add --manifest my_clips.csv (columns: path,surah,first,last,group,speaker)
         for your own or amateur recordings, --retasy to try the
         RetaSy/quranic_audio_dataset from Hugging Face, and --quick for a
         small smoke test.

Setup (same as try_quran_asr.py, plus the q8 model):
    python3 -m pip install sherpa-onnx numpy
    cd ~/niyat-asr
    for f in qurankarim-fastconformer-mixed.onnx qurankarim-fastconformer-q8.onnx tokens.txt; do
      curl -LO https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main/$f
    done
"""

import argparse
import collections
import csv
import difflib
import json
import os
import random
import subprocess
import sys
import time
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from try_quran_asr import (DEFAULT_DIR, ROOT, UTHMANI, compare, expected_words, harakat,  # noqa: E402
                           letters, load_audio, words)

IMLAEI = os.path.join(ROOT, "Niyat", "Resources", "Quran", "quran-imlaei.json")
FORMS = os.path.join(ROOT, "Niyat", "Resources", "Quran", "recognition-forms.json")
SR = 16000

# ---------------------------------------------------------------- test data

# Surah, first ayah, last ayah. Short and long ayat: 94 ayat per reciter.
AYAT = [(1, 1, 7), (2, 1, 20), (18, 1, 10), (36, 1, 12), (55, 1, 20), (67, 1, 10),
        (112, 1, 4), (113, 1, 5), (114, 1, 6)]
QUICK_AYAT = [(1, 1, 7), (112, 1, 4)]

# EveryAyah folders. tarteel-ai/everyayah is built from EveryAyah, so treat
# every reciter here as SEEN in training.
SEEN = ["Alafasy_128kbps", "Husary_128kbps", "Abdul_Basit_Murattal_192kbps",
        "Minshawy_Murattal_128kbps", "Ghamadi_40kbps", "Abdullah_Basfar_192kbps"]

# Whole-surah files from mp3quran.net for reciters not (as far as we know) on
# EveryAyah. Paths are best guesses: check them on mp3quran.net/api if they 404.
UNSEEN_SURAH_FILES = {
    "Islam_Sobhi": "https://server14.mp3quran.net/islam/Rewayat-Hafs-A-n-Assem/{s:03d}.mp3",
    "Raad_AlKurdi": "https://server6.mp3quran.net/kurdi/{s:03d}.mp3",
    "Abdulrahman_Mosad": "https://server16.mp3quran.net/a_mosad/Rewayat-Hafs-A-n-Assem/{s:03d}.mp3",
}
UNSEEN_SURAHS = [1, 103, 108, 112, 113, 114]

# ---------------------------------------------------------------- text helpers

_quran = {}


def quran(path=UTHMANI):
    if path not in _quran:
        _quran[path] = json.load(open(path, encoding="utf-8"))
    return _quran[path]


def ayah_words(surah, ayah, path=UTHMANI):
    """Words of one ayah, without the Bismillah that the JSON puts in front of
    ayah 1 (every surah except 1 and 9). Same indexing as recognition-forms.json."""
    ws = words(quran(path)[str(surah)][ayah - 1]["text"])
    if ayah == 1 and surah not in (1, 9):
        ws = ws[4:]
    return ws


def expected(surah, first, last):
    """[(verse, word)] like try_quran_asr.expected_words, minus the Bismillah."""
    out = expected_words(surah, first, last)
    if first == 1 and surah not in (1, 9):
        out = out[4:]
    return out


BISMILLAH = [letters(w) for w in ayah_words(1, 1)]


ISTIADHA = "اعوذباللهمنالشيطانالرجيم"


def strip_bismillah(heard, surah=None, first=None):
    """Don't count an opening أعوذ بالله من الشيطان الرجيم and/or Bismillah as
    extra words. Matched loosely, because the model often garbles them. Kept when
    it is the expected text itself (Al-Fatiha 1; 1:3 الرحمن الرحيم)."""
    basmala = "".join(BISMILLAH)
    targets = [ISTIADHA] if (surah, first) == (1, 1) else [ISTIADHA, basmala, ISTIADHA + basmala]
    own = [letters(w) for _, w in expected(surah, first, first)] if surah else []
    best_k, best = 0, 0.0
    for k in range(2, min(len(heard), 11) + 1):
        got = "".join(letters(w) for w in heard[:k])
        mine = difflib.SequenceMatcher(a="".join(own[:k]), b=got, autojunk=False).ratio()
        for t in targets:
            r = difflib.SequenceMatcher(a=t, b=got, autojunk=False).ratio()
            if r > best and r > mine:
                best_k, best = k, r
    return heard[best_k:] if best >= 0.75 else heard


def recognition_forms():
    try:
        return json.load(open(FORMS, encoding="utf-8"))["forms"]
    except (OSError, KeyError):
        return {}


# --- Proposed normalisation fixes (what the report recommends) ---

DAGGER = "\u0670"
SHADDA, SUKUN = "\u0651", "\u0652"


def letter_variants(word):
    """letters(), with the dagger alef read both ways: the model writes
    العالمين (with alef) but الرحمن (without) for Uthmani ٱلْعَٰلَمِينَ, ٱلرَّحْمَٰنِ."""
    return {letters(word), letters(word.replace(DAGGER, ""))}


def clusters(word):
    """[(letter, marks)] for the harakat check. Madda alef (آ) is read as ءَا,
    as Uthmani writes it; a hamza, or a tatweel carrying one, is its own letter."""
    out = []
    for ch in word.replace("آ", "ءَا"):
        h = harakat(ch)
        if h:
            if out:
                out[-1][1].add(h)
        elif ch in "ءـ":
            out.append(("ء", set()))
        elif ch == "ٔ":
            if not out or out[-1][0] != "ء":
                out.append(("ء", set()))
        elif letters(ch):
            out.append((letters(ch), set()))
    return out


def harakat_check(want, got, last_in_ayah):
    """Compare harakat letter by letter. Returns (checked marks, differing marks).
    - Only letters the model actually vowelled are checked (it often writes none).
    - A missing sukun is not an error (sukun vs nothing is the same sound).
    - Shadda on the first letter is skipped (idgham from the previous word: لَّهُۥ).
    - The last letter of an ayah's last word is skipped (the reciter stops: waqf)."""
    a, b = clusters(want), clusters(got)
    if not any(m for _, m in b):
        return 0, 0
    checked = differ = 0
    sm = difflib.SequenceMatcher(a=[x for x, _ in a], b=[x for x, _ in b], autojunk=False)
    for op, a0, a1, b0, b1 in sm.get_opcodes():
        if op != "equal":
            continue
        for i, j in zip(range(a0, a1), range(b0, b1)):
            if last_in_ayah and i == len(a) - 1:
                continue
            ma, mb = set(a[i][1]) - {SUKUN}, set(b[j][1]) - {SUKUN}
            if i == 0:
                ma.discard(SHADDA)
                mb.discard(SHADDA)
            if not b[j][1]:
                continue
            checked += 1
            differ += ma != mb
    return checked, differ


def harakat_v2(word):
    """The marks of a word in a fixed order, for the text-only spelling check."""
    return "".join("".join(sorted(m, key=lambda x: (x != SHADDA, x))) for _, m in clusters(word))


def compare_v2(exp, heard, forms=None, surah=None):
    """Like compare(), but with the fixes a shipped matcher would need:
    - an expected word also matches its everyday spelling from recognition-forms.json,
      and its spelling with the dagger alef dropped (ٱلرَّحْمَٰنِ = الرحمن);
    - two heard words that join into one expected word count as that word
      (يا أيها -> يَٰٓأَيُّهَا, يا قوم -> يَٰقَوْمِ);
    - harakat checked with harakat_check (only where the model wrote harakat).
    Returns (rows, stats) like compare(); stats also has "unchecked": matched
    words the harakat check couldn't look at because the model wrote no harakat."""
    forms = forms or {}
    keys = []          # accepted letter forms per expected word
    index = collections.Counter()
    for verse, w in exp:
        i = index[verse]
        index[verse] += 1
        alts = letter_variants(w)
        if surah is not None:
            alts |= set(forms.get(f"{surah}:{verse}:{i}", []))
        keys.append(alts)
    wanted = set().union(*keys) if keys else set()
    last = {i for i in range(len(exp)) if i + 1 == len(exp) or exp[i + 1][0] != exp[i][0]}

    # Join adjacent heard words when together they spell an expected word.
    merged, j = [], 0
    while j < len(heard):
        if j + 1 < len(heard) and letters(heard[j]) not in wanted and \
                letters(heard[j]) + letters(heard[j + 1]) in wanted:
            merged.append(heard[j] + heard[j + 1])
            j += 2
        else:
            merged.append(heard[j])
            j += 1
    heard = merged

    canon = {letters(w): letters(w) for _, w in exp}  # a word's own spelling always wins
    for alts, (_, w) in zip(keys, exp):
        for a in alts:
            canon.setdefault(a, letters(w))
    want = [letters(w) for _, w in exp]
    got = [canon.get(letters(w), letters(w)) for w in heard]
    rows = []
    stats = {"correct": 0, "haraka": 0, "different": 0, "missed": 0, "extra": 0, "unchecked": 0}
    for op, a0, a1, b0, b1 in difflib.SequenceMatcher(a=want, b=got, autojunk=False).get_opcodes():
        if op == "equal":
            for i, j in zip(range(a0, a1), range(b0, b1)):
                verse, word = exp[i]
                checked, differ = harakat_check(word, heard[j], i in last)
                same = differ == 0
                stats["correct" if same else "haraka"] += 1
                stats["unchecked"] += checked == 0
                rows.append(("ok" if same else "HARAKA", verse, word, heard[j]))
            continue
        for k in range(max(a1 - a0, b1 - b0)):
            i, j = a0 + k, b0 + k
            if i < a1 and j < b1:
                stats["different"] += 1
                rows.append(("DIFFERENT", exp[i][0], exp[i][1], heard[j]))
            elif i < a1:
                stats["missed"] += 1
                rows.append(("MISSED", exp[i][0], exp[i][1], ""))
            else:
                stats["extra"] += 1
                rows.append(("EXTRA", "", "", heard[j]))
    return rows, stats


def metrics(stats):
    """Letters-only WER, word accuracy (letters), harakat agreement on matched words."""
    n = stats["correct"] + stats["haraka"] + stats["different"] + stats["missed"]
    matched = stats["correct"] + stats["haraka"]
    checked = matched - stats.get("unchecked", 0)
    errors = stats["different"] + stats["missed"] + stats["extra"]
    return {
        "words": n,
        "wer": errors / n if n else 0.0,
        "word_acc": matched / n if n else 0.0,
        # v2: among matched words the model wrote harakat on
        "harakat_agree": (stats["correct"] - stats.get("unchecked", 0)) / checked if checked else 0.0,
        "harakat_checked": checked / matched if matched else 0.0,
    }


def letter_errors(stats):
    return stats["different"] + stats["missed"] + stats["extra"]


def add(total, stats):
    for k, v in stats.items():
        total[k] = total.get(k, 0) + v


# ---------------------------------------------------------------- text mode

def corrupt(heard, rate, rng):
    """Simulate recognition errors: each word is, with probability `rate`,
    replaced by a one-letter-wrong version, dropped, or followed by a junk word."""
    out = []
    for w in heard:
        r = rng.random()
        if r >= rate:
            out.append(w)
            continue
        kind = rng.choice(("sub", "sub", "del", "ins"))
        if kind == "del":
            continue
        if kind == "ins":
            out += [w, "مم"]
            continue
        chars = list(w)
        idx = [i for i, c in enumerate(chars) if letters(c)]
        chars[rng.choice(idx)] = rng.choice("بتثجحخدذرزسشصضطظعغفقكلمنهوي")
        out.append("".join(chars))
    return out


def every_ayah():
    for s in range(1, 115):
        for a in range(1, len(quran()[str(s)]) + 1):
            yield s, a


def text_mode(args):
    forms = recognition_forms()
    rng = random.Random(7)
    print("# Spelling floor: Uthmani expected vs Imla'i 'heard' (perfect recognition)\n")
    for label, scope in (("whole Qur'an", list(every_ayah())),
                         ("eval ayat", [(s, a) for s, f, l in AYAT for a in range(f, l + 1)])):
        for name, fn in (("current compare()", None), ("compare_v2 (forms + join + harakat_v2)", compare_v2)):
            total, clean = {}, 0
            for s, a in scope:
                exp = [(a, w) for w in ayah_words(s, a)]
                heard = ayah_words(s, a, IMLAEI)
                _, st = fn(exp, heard, forms, s) if fn else compare(exp, heard)
                add(total, st)
                clean += letter_errors(st) == 0 and st["haraka"] == 0
            m = metrics(total)
            print(f"- {label}, {name}: {len(scope)} ayat, {m['words']} words, letters-WER {m['wer']:.2%}, "
                  f"harakat agreement {m['harakat_agree']:.2%}, ayat with zero flags {clean / len(scope):.1%}")
    print()

    # Remaining differences after the fixes, most common first.
    left_l, left_h = collections.Counter(), collections.Counter()
    for s, a in every_ayah():
        rows, _ = compare_v2([(a, w) for w in ayah_words(s, a)], ayah_words(s, a, IMLAEI), forms, s)
        for lab, _, want, got in rows:
            if lab == "HARAKA":
                left_h[(want, got)] += 1
            elif lab != "ok":
                left_l[(lab, want, got)] += 1
    print("Most common letter flags left after compare_v2:")
    for (lab, want, got), c in left_l.most_common(12):
        print(f"  {c:4d} {lab:<9} expected {want or '-'}  heard {got or '-'}")
    print("Most common harakat flags left after compare_v2:")
    for (want, got), c in left_h.most_common(12):
        print(f"  {c:4d} expected {want}  heard {got}")
    print()

    # Mistake detection ceilings with simulated recognition errors.
    print("# Mistake detection with simulated recognition errors (Imla'i text as the transcript)\n")
    scope = list(every_ayah())
    print("| simulated word error rate | clean ayah flagged (any letter error) | wrong verse caught, acc < 0.5 "
          "| clean ayah with acc < 0.5 | skipped word caught | other words flagged per skipped-word test |")
    print("|---|---|---|---|---|---|")
    for rate in (0.0, 0.02, 0.05, 0.10, 0.20):
        n = flagged = wrong = clean_low = skip_hit = skip_other = skip_n = 0
        for s, a in scope:
            if a + 1 > len(quran()[str(s)]):
                continue
            exp = [(a, w) for w in ayah_words(s, a)]
            heard = corrupt(ayah_words(s, a, IMLAEI), rate, rng)
            _, st = compare_v2(exp, heard, forms, s)
            n += 1
            flagged += letter_errors(st) > 0
            clean_low += metrics(st)["word_acc"] < 0.5
            nxt = [(a + 1, w) for w in ayah_words(s, a + 1)]
            _, st2 = compare_v2(nxt, heard, forms, s)
            wrong += metrics(st2)["word_acc"] < 0.5
            if len(exp) >= 3:
                pos = rng.randrange(1, len(exp))
                extra_word = rng.choice(ayah_words(s, a + 1))
                test = exp[:pos] + [(a, extra_word)] + exp[pos:]
                rows, st3 = compare_v2(test, heard, forms, s)
                exp_rows = [r for r in rows if r[0] != "EXTRA"]
                # row index pos is the inserted word (EXTRA rows have no expected word)
                skip_n += 1
                skip_hit += exp_rows[pos][0] in ("MISSED", "DIFFERENT")
                skip_other += letter_errors(st3) - (exp_rows[pos][0] in ("MISSED", "DIFFERENT"))
        print(f"| {rate:.0%} | {flagged / n:.1%} | {wrong / n:.1%} | {clean_low / n:.1%} | "
              f"{skip_hit / skip_n:.1%} | {skip_other / skip_n:.2f} |")
    print(f"\n({n} ayah pairs, {skip_n} skipped-word tests; a 'skip' is an extra word from the next ayah "
          "inserted into the expected text, so the transcript lacks it.)")


# ---------------------------------------------------------------- audio mode

def fetch(url, dest, failures):
    if os.path.exists(dest) and os.path.getsize(dest) > 0:
        return dest
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    try:
        req = urllib.request.Request(url, headers={"User-Agent": "niyat-asr-eval"})
        with urllib.request.urlopen(req, timeout=60) as r, open(dest + ".part", "wb") as f:
            f.write(r.read())
        os.replace(dest + ".part", dest)
        return dest
    except Exception as e:  # noqa: BLE001 - record and carry on
        host = url.split("/")[2]
        failures[host] = failures.get(host, 0) + 1
        if failures[host] == 1:
            print(f"  ! could not download from {host}: {e}")
        return None


def build_clips(args, cache, failures):
    """[(group, speaker, surah, first, last, path)]"""
    clips = []
    ayat = QUICK_AYAT if args.quick else AYAT
    reciters = SEEN[:2] if args.quick else SEEN
    for rec in reciters:
        say(f"  {rec}")
        for s, f, l in ayat:
            for a in range(f, l + 1):
                p = fetch(f"https://everyayah.com/data/{rec}/{s:03d}{a:03d}.mp3",
                          os.path.join(cache, "everyayah", rec, f"{s:03d}{a:03d}.mp3"), failures)
                if p:
                    clips.append(("seen", rec, s, a, a, p))
    if not args.quick:
        for rec, pattern in UNSEEN_SURAH_FILES.items():
            say(f"  {rec}")
            for s in UNSEEN_SURAHS:
                p = fetch(pattern.format(s=s), os.path.join(cache, "mp3quran", rec, f"{s:03d}.mp3"), failures)
                if p:
                    clips.append(("unseen", rec, s, 1, len(quran()[str(s)]), p))
    if args.manifest:
        for row in csv.DictReader(open(args.manifest, encoding="utf-8")):
            clips.append((row.get("group") or "manifest", row.get("speaker") or "?", int(row["surah"]),
                          int(row["first"]), int(row.get("last") or row["first"]), row["path"]))
    if args.retasy:
        clips += retasy_clips(cache, args.retasy_limit)
    return clips


def ayah_key(text):
    """Letters of a whole ayah, with Persian/Urdu letter forms folded (RetaSy writes ی)."""
    text = text.replace("ی", "ي").replace("ک", "ك").replace("ۀ", "ه")
    return "".join(letters(w) for w in words(text))


_ayah_index = {}


def ayah_index():
    if not _ayah_index:
        for s in range(1, 115):
            for a in range(1, len(quran()[str(s)]) + 1):
                _ayah_index.setdefault(ayah_key(" ".join(ayah_words(s, a))), (s, a))
    return _ayah_index


def retasy_clips(cache, limit, scan=4000):
    """RetaSy/quranic_audio_dataset: recitations by non-Arabic speakers with
    correctness labels. Streamed (only `limit` clips are downloaded), audio kept
    as raw bytes so no torch is needed. Column names are detected, and printed."""
    try:
        from datasets import Audio, load_dataset
    except ImportError:
        print("  ! --retasy needs: python3 -m pip install datasets")
        return []
    try:
        ds = load_dataset("RetaSy/quranic_audio_dataset", split="train", streaming=True)
        audio_c = next((c for c, f in (ds.features or {}).items() if isinstance(f, Audio)), "audio")
        ds = ds.cast_column(audio_c, Audio(decode=False))
        rows = iter(ds)
        first = next(rows)
    except Exception as e:  # noqa: BLE001
        print(f"  ! could not load RetaSy/quranic_audio_dataset: {e}")
        return []
    print(f"  RetaSy columns: { {k: (v if k != audio_c else '<audio>') for k, v in first.items()} }")

    def number_col(*names):
        for c in first:
            if any(n in c.lower() for n in names):
                try:
                    int(first[c])
                    return c
                except (TypeError, ValueError):
                    pass
        return None
    surah_c, ayah_c = number_col("surah", "sura", "chapter"), number_col("aya", "verse")
    text_c = next((c for c in first if c.lower() in ("aya", "ayah", "verse", "text")), None)
    label_c = next((c for c in first if "label" in c.lower()), None)
    if not (surah_c and ayah_c) and not text_c:
        print("  ! RetaSy: no surah/ayah columns recognised, skipping")
        return []
    index = ayah_index()
    out, i, unmatched = [], 0, 0
    for row in [first, *rows]:
        if len(out) >= limit or i >= scan:
            break
        i += 1
        try:
            if surah_c and ayah_c:
                s, a = int(row[surah_c]), int(row[ayah_c])
            else:
                s, a = index[ayah_key(row[text_c])]
            if not 1 <= a <= len(quran()[str(s)]):
                continue
        except (TypeError, ValueError, KeyError):
            unmatched += 1
            continue
        blob = row[audio_c]
        ext = os.path.splitext(blob.get("path") or "x.wav")[1] or ".wav"
        path = os.path.join(cache, "retasy", f"{i}{ext}")
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as f:
                f.write(blob["bytes"])
        label = row.get(label_c) if label_c else None
        label = str(label).strip().lower() if label not in (None, "") else "unlabelled"
        out.append((f"amateur ({label})", "retasy", s, a, a, path))
    if unmatched:
        print(f"  RetaSy: {unmatched} rows whose ayah text didn't match the Qur'an text, skipped")
    print(f"  RetaSy: {len(out)} clips")
    return out


def ffmpeg_filter(samples, af):
    import numpy as np
    raw = subprocess.run(["ffmpeg", "-v", "error", "-f", "f32le", "-ar", str(SR), "-ac", "1", "-i", "-",
                          "-af", af, "-ar", str(SR), "-ac", "1", "-f", "f32le", "-"],
                         input=samples.astype(np.float32).tobytes(), check=True, capture_output=True).stdout
    return np.frombuffer(raw, dtype=np.float32)


def add_noise(samples, snr_db, rng, babble_pool=None):
    import numpy as np
    power = float(np.mean(samples ** 2)) or 1e-9
    if babble_pool:
        noise = np.zeros_like(samples)
        for other in rng.sample(babble_pool, min(4, len(babble_pool))):
            reps = int(np.ceil(len(samples) / len(other))) + 1
            tiled = np.tile(other, reps)
            start = rng.randrange(0, len(other))
            noise += tiled[start:start + len(samples)]
    else:
        noise = np.random.default_rng(rng.randrange(1 << 30)).standard_normal(len(samples)).astype(np.float32)
    noise *= np.sqrt(power / (10 ** (snr_db / 10)) / (float(np.mean(noise ** 2)) or 1e-9))
    return (samples + noise).astype(np.float32)


def augmentations(samples, rng, babble_pool):
    yield "white SNR 20", add_noise(samples, 20, rng)
    yield "white SNR 10", add_noise(samples, 10, rng)
    yield "white SNR 5", add_noise(samples, 5, rng)
    yield "babble SNR 10", add_noise(samples, 10, rng, babble_pool)
    yield "babble SNR 5", add_noise(samples, 5, rng, babble_pool)
    yield "phone 300-3400 Hz", ffmpeg_filter(samples, "highpass=f=300,lowpass=f=3400,aresample=8000")
    yield "speed 0.9x", ffmpeg_filter(samples, "atempo=0.9")
    yield "speed 1.15x", ffmpeg_filter(samples, "atempo=1.15")


class Model:
    def __init__(self, path, tokens, threads):
        import sherpa_onnx
        self.name = os.path.basename(path)
        self.rec = sherpa_onnx.OfflineRecognizer.from_nemo_ctc(
            model=path, tokens=tokens, num_threads=threads, sample_rate=SR, feature_dim=80,
            decoding_method="greedy_search")

    def __call__(self, samples, pad=0.0):
        if pad:
            import numpy as np
            silence = np.zeros(int(pad * SR), dtype=np.float32)
            samples = np.concatenate([silence, samples, silence])
        t = time.perf_counter()
        stream = self.rec.create_stream()
        stream.accept_waveform(SR, samples)
        self.rec.decode_stream(stream)
        return stream.result.text.strip(), time.perf_counter() - t


def say(*args):
    print(*args, flush=True)


def score(text, surah, first, last, forms):
    heard = strip_bismillah(words(text), surah, first)
    exp = expected(surah, first, last)
    rows, st = compare(exp, heard)
    rows2, st2 = compare_v2(exp, heard, forms, surah)
    return rows, st, rows2, st2


def table(title, groups):
    say(f"\n### {title}\n")
    say("| group | clips | words | letters-WER | word acc | harakat agree | sequence acc | "
        "letters-WER (v2) | word acc (v2) | harakat agree (v2) | words with harakat | sequence acc (v2) |")
    say("|---|---|---|---|---|---|---|---|---|---|---|---|")
    for g, (n, tot, seq, tot2, seq2) in groups.items():
        m, m2 = metrics(tot), metrics(tot2)
        say(f"| {g} | {n} | {m['words']} | {m['wer']:.2%} | {m['word_acc']:.2%} | {m['harakat_agree']:.2%} | "
            f"{seq / n:.1%} | {m2['wer']:.2%} | {m2['word_acc']:.2%} | {m2['harakat_agree']:.2%} | "
            f"{m2['harakat_checked']:.0%} | "
            f"{seq2 / n:.1%} |")


def report(records, threshold=0.5, examples=15):
    """Print every table from transcript records (fresh, or loaded by `rescore`).
    Scores are recomputed here, so a scoring fix needs no new decoding."""
    forms = recognition_forms()
    rng = random.Random(7)
    groups, noisy = collections.OrderedDict(), collections.OrderedDict()
    flags = collections.defaultdict(list)
    harakat_fa = {"v1": [0, 0], "v2": [0, 0]}
    single = []  # (group, surah, ayah, text) of clean single-ayah clips
    speed = [r for r in records if r.get("kind") == "speed"]
    for r in records:
        if r.get("kind") == "speed":
            continue
        rows, st, rows2, st2 = score(r["text"], r["surah"], r["first"], r["last"], forms)
        aug = r.get("aug") or ""
        key = aug if aug else f"{r['group']} [{r['model']}]"
        g = (noisy if aug else groups).setdefault(key, [0, {}, 0, {}, 0])
        g[0] += 1
        add(g[1], st)
        g[2] += letter_errors(st) == 0
        add(g[3], st2)
        g[4] += letter_errors(st2) == 0
        if aug or r["model"] != "mixed":
            continue
        if r["first"] == r["last"]:
            single.append((r["group"], r["surah"], r["first"], r["text"]))
        if r["group"] == "seen":
            harakat_fa["v1"][0] += st["haraka"]
            harakat_fa["v1"][1] += st["haraka"] + st["correct"]
            harakat_fa["v2"][0] += st2["haraka"]
            harakat_fa["v2"][1] += st2["haraka"] + st2["correct"] - st2["unchecked"]
        for lab, verse, want, got in rows2:
            if lab != "ok":
                flags[r["group"]].append((r["speaker"], f"{r['surah']}:{verse}" if verse else f"{r['surah']}",
                                          lab, want, got))
    table("Accuracy by group (v2 = proposed normalisation)", groups)
    if noisy:
        table("Variants (noise / phone / speed: mixed model, seen clips; pad: silence added before and after)",
              noisy)

    say("\n### Mistake detection (mixed model, single-ayah clips)\n")
    say(f"Wrong verse = audio of ayah N scored against the text of N+1, caught when word accuracy < {threshold}; "
        "false alarm = the right ayah scoring below the same threshold. Skipped word = one word inserted "
        "into the expected text.\n")
    say("| group | clips | correct ayah with any letter flag | wrong verse caught | wrong-verse false alarm | "
        "skipped word caught | other words flagged per skip test |")
    say("|---|---|---|---|---|---|---|")
    by_group = collections.OrderedDict()
    for group, s, a, text in single:
        by_group.setdefault(group, []).append((s, a, text))
    for group, items in by_group.items():
        n = wrong = clean_low = skip_n = skip_hit = skip_other = clean_flag = 0
        for s, a, text in items:
            if a + 1 > len(quran()[str(s)]):
                continue
            heard = strip_bismillah(words(text), s, a)
            exp = expected(s, a, a)
            _, st = compare_v2(exp, heard, forms, s)
            n += 1
            clean_flag += letter_errors(st) > 0
            clean_low += metrics(st)["word_acc"] < threshold
            _, st2 = compare_v2(expected(s, a + 1, a + 1), heard, forms, s)
            wrong += metrics(st2)["word_acc"] < threshold
            if len(exp) >= 3:
                pos = rng.randrange(1, len(exp))
                test = exp[:pos] + [(a, rng.choice(ayah_words(s, a + 1)))] + exp[pos:]
                rows, st3 = compare_v2(test, heard, forms, s)
                hit = [x for x in rows if x[0] != "EXTRA"][pos][0] in ("MISSED", "DIFFERENT")
                skip_n += 1
                skip_hit += hit
                skip_other += letter_errors(st3) - hit
        if n:
            skips = f"{skip_hit / skip_n:.1%} of {skip_n} | {skip_other / skip_n:.2f}" if skip_n else "- | -"
            say(f"| {group} | {n} | {clean_flag / n:.1%} | {wrong / n:.1%} | {clean_low / n:.1%} | {skips} |")
    say("")
    for k, (bad, tot) in harakat_fa.items():
        if tot:
            say(f"- Harakat false alarms on seen professional audio ({k}): {bad}/{tot} checked words = {bad / tot:.2%}")

    if speed:
        say("\n### Decode speed (real-time factor = decode time / audio length; lower is faster)\n")
        say("| model | threads | clips | audio s | decode s | RTF |")
        say("|---|---|---|---|---|---|")
        for r in speed:
            say(f"| {r['model']} | {r['threads']} | {r['clips']} | {r['audio']:.0f} | {r['decode']:.1f} | "
                f"{r['decode'] / r['audio']:.3f} |")

    say("\n### Example flags (mixed, v2)\n")
    for group, items in flags.items():
        say(f"{group}: {len(items)} flags")
        for spk, ref, lab, want, got in items[:examples]:
            say(f"  {spk:<28} {ref:<7} {lab:<9} expected {want or '-'}  heard {got or '-'}")


def audio_mode(args):
    try:
        import numpy as np  # noqa: F401
        import sherpa_onnx  # noqa: F401
    except ImportError:
        sys.exit("Install first:  python3 -m pip install sherpa-onnx numpy")
    tokens = os.path.join(args.model_dir, "tokens.txt")
    paths = {k: os.path.join(args.model_dir, f"qurankarim-fastconformer-{k}.onnx") for k in ("mixed", "q8")}
    for p in [tokens, *paths.values()]:
        if not os.path.exists(p):
            sys.exit(f"Missing {p}. See the setup steps at the top of this script.")
    os.makedirs(args.out, exist_ok=True)
    cache = os.path.join(args.out, "audio")
    failures = {}
    rng = random.Random(7)

    say("Downloading audio (cached after the first run)...")
    clips = build_clips(args, cache, failures)
    if failures:
        say(f"Unreachable hosts (files failed): {failures}")
    if not clips:
        sys.exit("No audio could be fetched: nothing to evaluate.")
    audio = {c[5]: load_audio(c[5]) for c in clips}
    out_path = os.path.join(args.out, "transcripts.jsonl")
    log = open(out_path, "w", encoding="utf-8")
    records = []

    def keep(rec):
        records.append(rec)
        log.write(json.dumps(rec, ensure_ascii=False) + "\n")
        log.flush()

    models = {k: Model(p, tokens, args.threads) for k, p in paths.items()}
    for key, model in models.items():
        subset = clips if key == "mixed" or args.full_q8 else [c for c in clips if c[0] == "seen"][: args.q8_clips]
        say(f"Transcribing {len(subset)} clips with {key}...")
        for done, (group, spk, s, f, l, path) in enumerate(subset, 1):
            text, took = model(audio[path], args.pad)
            keep({"model": key, "group": group, "speaker": spk, "surah": s, "first": f, "last": l,
                  "seconds": len(audio[path]) / SR, "decode": took, "text": text})
            if done % 50 == 0:
                say(f"  {done}/{len(subset)}")

    seen = [c for c in clips if c[0] == "seen" and c[3] == c[4]]
    rng.shuffle(seen)
    subset = seen[: args.noise_clips]
    pool = [audio[c[5]] for c in seen[args.noise_clips: args.noise_clips + 40]] or [audio[c[5]] for c in subset]
    say(f"Noise / phone / speed variants on {len(subset)} clips...")
    for group, spk, s, f, l, path in subset:
        for name, samples in augmentations(audio[path], rng, pool):
            text, _ = models["mixed"](samples, args.pad)
            keep({"model": "mixed", "group": group, "speaker": spk, "surah": s, "first": f, "last": l,
                  "aug": name, "text": text})

    say("Timing...")
    timing = sorted(seen, key=lambda c: c[5])[: args.speed_clips]
    for key, path in paths.items():
        for threads in (1, 2):
            m = Model(path, tokens, threads)
            m(audio[timing[0][5]])  # warm up
            total_audio = total = 0.0
            for c in timing:
                _, took = m(audio[c[5]])
                total += took
                total_audio += len(audio[c[5]]) / SR
            keep({"kind": "speed", "model": key, "threads": threads, "clips": len(timing),
                  "audio": total_audio, "decode": total})
    log.close()
    report(records, args.threshold)
    say(f"\nAll transcripts: {out_path}")


def padtest_mode(args):
    """Do silence around the clip, or faint noise (like the dither used in
    training), fix the dropped last syllables? Seen clips, both models.
    Audio comes from the cache of an earlier run."""
    tokens = os.path.join(args.model_dir, "tokens.txt")
    clips = build_clips(argparse.Namespace(quick=args.quick, manifest=None, retasy=False),
                        os.path.join(args.out, "audio"), {})
    clips = [c for c in clips if c[0] == "seen"]
    audio = {c[5]: load_audio(c[5]) for c in clips}
    out_path = os.path.join(args.out, "padtest.jsonl")
    records = []
    with open(out_path, "w", encoding="utf-8") as log:
        for key in ("mixed", "q8"):
            model = Model(os.path.join(args.model_dir, f"qurankarim-fastconformer-{key}.onnx"), tokens, 2)
            rng = random.Random(7)
            variants = [(f"pad {p} s", p, None) for p in (0.0, 0.25, 0.5, 1.0)] + \
                       [("noise SNR 40", 0.0, 40), ("noise SNR 30", 0.0, 30), ("noise SNR 30 + pad 0.5 s", 0.5, 30)]
            for name, pad, snr in variants:
                say(f"{key}, {name}: {len(clips)} clips")
                for group, spk, s, f, l, path in clips:
                    samples = audio[path]
                    if pad and snr:  # pad first, so the added silence gets the same faint noise
                        import numpy as np
                        silence = np.zeros(int(pad * SR), dtype=np.float32)
                        samples, pad_now = np.concatenate([silence, samples, silence]), 0.0
                    else:
                        pad_now = pad
                    if snr:
                        samples = add_noise(samples, snr, rng)
                    text, _ = model(samples, pad_now)
                    rec = {"model": key, "group": group, "speaker": spk, "surah": s, "first": f, "last": l,
                           "aug": f"{name} [{key}]", "text": text}
                    records.append(rec)
                    log.write(json.dumps(rec, ensure_ascii=False) + "\n")
    report(records, args.threshold)
    say(f"\nAll transcripts: {out_path}")


def rescore_mode(args):
    records = [json.loads(line) for line in open(args.transcripts, encoding="utf-8") if line.strip()]
    report(records, args.threshold, args.examples)


PLAIN_LETTERS = set("ابتثجحخدذرزسشصضطظعغفقكلمنهوي")


def inspect_mode(args):
    """Which marks can the model write? Read from tokens.txt."""
    path = os.path.join(args.model_dir, "tokens.txt")
    marks = collections.Counter()
    n = 0
    for line in open(path, encoding="utf-8"):
        tok = line.rsplit(" ", 1)[0]
        n += 1
        for ch in tok:
            if ch not in PLAIN_LETTERS and not ch.isspace() and ch != "▁":
                marks[ch] += 1
    say(f"{n} tokens. Characters other than the 28 plain letters that the model can write:")
    try:
        import onnx
        for key in ("mixed", "q8"):
            m = onnx.load(os.path.join(args.model_dir, f"qurankarim-fastconformer-{key}.onnx"),
                          load_external_data=False)
            say(f"{key} metadata: { {p.key: p.value[:60] for p in m.metadata_props} }")
    except ImportError:
        say("(pip install onnx to also print the models' metadata)")
    for ch, c in marks.most_common():
        import unicodedata
        say(f"  U+{ord(ch):04X} {unicodedata.name(ch, '?'):<45} in {c} tokens")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = p.add_subparsers(dest="mode", required=True)
    sub.add_parser("text", help="spelling floor and simulated mistake detection (no model needed)")
    a = sub.add_parser("audio", help="full evaluation with audio")
    a.add_argument("--model-dir", default=DEFAULT_DIR)
    a.add_argument("--out", default=os.path.join(DEFAULT_DIR, "eval"))
    a.add_argument("--threads", type=int, default=2)
    a.add_argument("--manifest", help="CSV of your own clips: path,surah,first,last,group,speaker")
    a.add_argument("--retasy", action="store_true", help="also try RetaSy/quranic_audio_dataset (amateurs)")
    a.add_argument("--retasy-limit", type=int, default=150)
    a.add_argument("--quick", action="store_true", help="2 reciters, 11 ayat: a smoke test")
    a.add_argument("--full-q8", action="store_true", help="run q8 on every clip, not just a subset")
    a.add_argument("--q8-clips", type=int, default=150)
    a.add_argument("--noise-clips", type=int, default=60)
    a.add_argument("--speed-clips", type=int, default=40)
    a.add_argument("--threshold", type=float, default=0.5, help="word accuracy below this = wrong verse")
    a.add_argument("--pad", type=float, default=0.0, help="seconds of silence added before and after each clip")
    r = sub.add_parser("rescore", help="recompute all tables from a transcripts.jsonl (no model needed)")
    r.add_argument("transcripts", nargs="?", default=os.path.join(DEFAULT_DIR, "eval", "transcripts.jsonl"))
    r.add_argument("--threshold", type=float, default=0.5)
    r.add_argument("--examples", type=int, default=15)
    t = sub.add_parser("padtest", help="seen clips with silence padding / faint noise added, both models")
    t.add_argument("--model-dir", default=DEFAULT_DIR)
    t.add_argument("--out", default=os.path.join(DEFAULT_DIR, "eval"))
    t.add_argument("--quick", action="store_true")
    t.add_argument("--threshold", type=float, default=0.5)
    i = sub.add_parser("inspect", help="list the marks the model can output (reads tokens.txt)")
    i.add_argument("--model-dir", default=DEFAULT_DIR)
    args = p.parse_args()
    {"text": text_mode, "audio": audio_mode, "rescore": rescore_mode, "inspect": inspect_mode,
     "padtest": padtest_mode}[args.mode](args)


if __name__ == "__main__":
    main()
