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


def strip_bismillah(heard):
    """Reciters often start a surah with the Bismillah: don't count it as extra."""
    if [letters(w) for w in heard[:4]] == BISMILLAH:
        return heard[4:]
    return heard


def recognition_forms():
    try:
        return json.load(open(FORMS, encoding="utf-8"))["forms"]
    except (OSError, KeyError):
        return {}


# --- Proposed normalisation fixes (what the report recommends) ---

def harakat_v2(word):
    """harakat(), plus: madda alef (آ) counts as fatha + alef, as Uthmani writes
    it (ءَا), and marks on one letter are put in a fixed order (shadda first)."""
    word = word.replace("آ", "ءَا")
    out, cluster = [], []
    for ch in word:
        h = harakat(ch)
        if h:
            cluster.append(h)
        elif letters(ch) or ch in "ءٔـ":
            out += sorted(cluster, key=lambda m: (m != "ّ", m))
            cluster = []
    out += sorted(cluster, key=lambda m: (m != "ّ", m))
    return "".join(out)


def compare_v2(exp, heard, forms=None, surah=None):
    """Like compare(), but with the fixes a shipped matcher would need:
    - an expected word also matches its everyday spelling from recognition-forms.json;
    - two heard words that join into one expected word count as that word
      (يا أيها -> يَٰٓأَيُّهَا, يا قوم -> يَٰقَوْمِ);
    - harakat compared with harakat_v2.
    Returns the same (rows, stats) as compare()."""
    forms = forms or {}
    keys = []          # accepted letter forms per expected word
    index = collections.Counter()
    for verse, w in exp:
        i = index[verse]
        index[verse] += 1
        alts = {letters(w)}
        if surah is not None:
            alts |= set(forms.get(f"{surah}:{verse}:{i}", []))
        keys.append(alts)
    wanted = set().union(*keys) if keys else set()

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

    canon = {}
    for alts, (_, w) in zip(keys, exp):
        for a in alts:
            canon.setdefault(a, letters(w))
    want = [letters(w) for _, w in exp]
    got = [canon.get(letters(w), letters(w)) for w in heard]
    rows, stats = [], {"correct": 0, "haraka": 0, "different": 0, "missed": 0, "extra": 0}
    for op, a0, a1, b0, b1 in difflib.SequenceMatcher(a=want, b=got, autojunk=False).get_opcodes():
        if op == "equal":
            for i, j in zip(range(a0, a1), range(b0, b1)):
                verse, word = exp[i]
                same = harakat_v2(word) == harakat_v2(heard[j])
                stats["correct" if same else "haraka"] += 1
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
    errors = stats["different"] + stats["missed"] + stats["extra"]
    return {
        "words": n,
        "wer": errors / n if n else 0.0,
        "word_acc": matched / n if n else 0.0,
        "harakat_agree": stats["correct"] / matched if matched else 0.0,
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
        for s, f, l in ayat:
            for a in range(f, l + 1):
                p = fetch(f"https://everyayah.com/data/{rec}/{s:03d}{a:03d}.mp3",
                          os.path.join(cache, "everyayah", rec, f"{s:03d}{a:03d}.mp3"), failures)
                if p:
                    clips.append(("seen", rec, s, a, a, p))
    if not args.quick:
        for rec, pattern in UNSEEN_SURAH_FILES.items():
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


def retasy_clips(cache, limit):
    """RetaSy/quranic_audio_dataset: recitations by non-Arabic speakers with
    correctness labels. Column names are guessed defensively; check them."""
    try:
        from datasets import load_dataset
    except ImportError:
        print("  ! --retasy needs: python3 -m pip install datasets soundfile")
        return []
    try:
        ds = load_dataset("RetaSy/quranic_audio_dataset", split="train")
    except Exception as e:  # noqa: BLE001
        print(f"  ! could not load RetaSy/quranic_audio_dataset: {e}")
        return []
    import soundfile as sf
    cols = {c.lower(): c for c in ds.column_names}
    surah_c = next((cols[c] for c in cols if "surah" in c or "sura" in c), None)
    ayah_c = next((cols[c] for c in cols if c in ("aya", "ayah", "verse") or "aya" in c), None)
    label_c = next((cols[c] for c in cols if "label" in c), None)
    if not (surah_c and ayah_c):
        print(f"  ! RetaSy columns not recognised: {ds.column_names}")
        return []
    out = []
    for i, row in enumerate(ds):
        if len(out) >= limit:
            break
        try:
            s, a = int(row[surah_c]), int(row[ayah_c])
        except (TypeError, ValueError):
            continue
        label = str(row[label_c]).lower() if label_c else "unknown"
        path = os.path.join(cache, "retasy", f"{i}.wav")
        if not os.path.exists(path):
            os.makedirs(os.path.dirname(path), exist_ok=True)
            sf.write(path, row["audio"]["array"], row["audio"]["sampling_rate"])
        group = "amateur" if label in ("correct", "1", "true") else f"amateur-{label}"
        out.append((group, "retasy", s, a, a, path))
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

    def __call__(self, samples):
        t = time.perf_counter()
        stream = self.rec.create_stream()
        stream.accept_waveform(SR, samples)
        self.rec.decode_stream(stream)
        return stream.result.text.strip(), time.perf_counter() - t


def score(text, surah, first, last, forms):
    heard = strip_bismillah(words(text))
    exp = expected(surah, first, last)
    rows, st = compare(exp, heard)
    rows2, st2 = compare_v2(exp, heard, forms, surah)
    return rows, st, rows2, st2


def table(title, groups):
    print(f"\n### {title}\n")
    print("| group | clips | words | letters-WER | word acc | harakat agree | sequence acc | "
          "letters-WER (v2) | harakat agree (v2) | sequence acc (v2) |")
    print("|---|---|---|---|---|---|---|---|---|---|")
    for g, (n, tot, seq, tot2, seq2) in groups.items():
        m, m2 = metrics(tot), metrics(tot2)
        print(f"| {g} | {n} | {m['words']} | {m['wer']:.2%} | {m['word_acc']:.2%} | {m['harakat_agree']:.2%} | "
              f"{seq / n:.1%} | {m2['wer']:.2%} | {m2['harakat_agree']:.2%} | {seq2 / n:.1%} |")


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
    forms = recognition_forms()
    rng = random.Random(7)

    print("Downloading audio...")
    clips = build_clips(args, cache, failures)
    if failures:
        print(f"Unreachable hosts (files failed): {failures}")
    if not clips:
        sys.exit("No audio could be fetched: nothing to evaluate.")
    audio = {c[5]: load_audio(c[5]) for c in clips}
    log = open(os.path.join(args.out, "transcripts.jsonl"), "w", encoding="utf-8")

    models = {k: Model(p, tokens, args.threads) for k, p in paths.items()}
    groups = collections.OrderedDict()
    failures_shown = collections.defaultdict(list)
    harakat_flags = {"v1": [0, 0], "v2": [0, 0]}
    clean_texts = {}  # (speaker, surah, ayah) -> mixed transcript, for mistake tests
    for key, model in models.items():
        if key == "q8" and not args.full_q8:
            subset = [c for c in clips if c[0] == "seen"][: args.q8_clips]
        else:
            subset = clips
        for group, spk, s, f, l, path in subset:
            text, took = model(audio[path])
            rows, st, rows2, st2 = score(text, s, f, l, forms)
            g = groups.setdefault(f"{group} [{key}]", [0, {}, 0, {}, 0])
            g[0] += 1
            add(g[1], st)
            g[2] += letter_errors(st) == 0
            add(g[3], st2)
            g[4] += letter_errors(st2) == 0
            log.write(json.dumps({"model": key, "group": group, "speaker": spk, "surah": s, "first": f, "last": l,
                                  "seconds": len(audio[path]) / SR, "decode": took, "text": text,
                                  "stats": st, "stats_v2": st2}, ensure_ascii=False) + "\n")
            if key == "mixed":
                if f == l:
                    clean_texts[(spk, s, f)] = text
                if group == "seen":
                    harakat_flags["v1"][0] += st["haraka"]
                    harakat_flags["v1"][1] += st["haraka"] + st["correct"]
                    harakat_flags["v2"][0] += st2["haraka"]
                    harakat_flags["v2"][1] += st2["haraka"] + st2["correct"]
                for lab, verse, want, got in rows2:
                    if lab != "ok":
                        failures_shown[group].append((spk, f"{s}:{verse}" if verse else f"{s}", lab, want, got))
    table("Accuracy by group (letters-WER etc.; v2 = proposed normalisation)", groups)

    # Robustness on a subset of seen clean single-ayah clips.
    seen = [c for c in clips if c[0] == "seen" and c[3] == c[4]]
    rng.shuffle(seen)
    subset = seen[: args.noise_clips]
    pool = [audio[c[5]] for c in seen[args.noise_clips: args.noise_clips + 40]] or [audio[c[5]] for c in subset]
    noisy = collections.OrderedDict()
    for group, spk, s, f, l, path in subset:
        for name, samples in augmentations(audio[path], rng, pool):
            text, _ = models["mixed"](samples)
            _, st, _, st2 = score(text, s, f, l, forms)
            g = noisy.setdefault(name, [0, {}, 0, {}, 0])
            g[0] += 1
            add(g[1], st)
            g[2] += letter_errors(st) == 0
            add(g[3], st2)
            g[4] += letter_errors(st2) == 0
    table(f"Robustness, mixed model, {len(subset)} seen clips", noisy)

    # Synthetic mistake detection on single-ayah clean clips.
    print("\n### Mistake detection (mixed model, clean single-ayah clips)\n")
    n = wrong = clean_low = skip_n = skip_hit = skip_other = clean_flag = 0
    for (spk, s, a), text in clean_texts.items():
        if a + 1 > len(quran()[str(s)]):
            continue
        heard = strip_bismillah(words(text))
        exp = expected(s, a, a)
        _, st = compare_v2(exp, heard, forms, s)
        n += 1
        clean_flag += letter_errors(st) > 0
        clean_low += metrics(st)["word_acc"] < args.threshold
        _, st2 = compare_v2(expected(s, a + 1, a + 1), heard, forms, s)
        wrong += metrics(st2)["word_acc"] < args.threshold
        if len(exp) >= 3:
            pos = rng.randrange(1, len(exp))
            test = exp[:pos] + [(a, rng.choice(ayah_words(s, a + 1)))] + exp[pos:]
            rows, st3 = compare_v2(test, heard, forms, s)
            hit = [r for r in rows if r[0] != "EXTRA"][pos][0] in ("MISSED", "DIFFERENT")
            skip_n += 1
            skip_hit += hit
            skip_other += letter_errors(st3) - hit
    print(f"- {n} clips. Correct recitation flagged with any letter error: {clean_flag / n:.1%}")
    print(f"- Wrong verse (ayah N audio vs ayah N+1 text) caught at word acc < {args.threshold}: {wrong / n:.1%}; "
          f"correct ayah below the same threshold (false alarm): {clean_low / n:.1%}")
    print(f"- Skipped word caught: {skip_hit / max(skip_n, 1):.1%} of {skip_n}; "
          f"other words flagged per test: {skip_other / max(skip_n, 1):.2f}")
    for k, (bad, tot) in harakat_flags.items():
        if tot:
            print(f"- Harakat false alarms on seen professional audio ({k}): {bad}/{tot} matched words = {bad / tot:.2%}")

    # Speed.
    print("\n### Decode speed (real-time factor = decode time / audio length; lower is faster)\n")
    print("| model | threads | clips | audio s | decode s | RTF |")
    print("|---|---|---|---|---|---|")
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
            print(f"| {key} | {threads} | {len(timing)} | {total_audio:.0f} | {total:.1f} | {total / total_audio:.3f} |")

    print("\n### Example flags (mixed, v2)\n")
    for group, items in failures_shown.items():
        print(f"{group}:")
        for spk, ref, lab, want, got in items[:15]:
            print(f"  {spk:<28} {ref:<7} {lab:<9} expected {want or '-'}  heard {got or '-'}")
    print(f"\nAll transcripts: {os.path.join(args.out, 'transcripts.jsonl')}")


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
    args = p.parse_args()
    text_mode(args) if args.mode == "text" else audio_mode(args)


if __name__ == "__main__":
    main()
