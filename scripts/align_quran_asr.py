#!/usr/bin/env python3
"""Forced-alignment test for the QuranKarim model (research only).

eval_quran_asr.py asks the model "what was said?" and compares its spelling
with the Qur'an, which flags many correct words because the model's spelling
is sloppy (يُؤْمِن for يُؤْمِنُونَ). This script asks a different question:
"how well does the audio fit the words that SHOULD have been said?"

It runs the ONNX model directly (onnxruntime) to get, for every ~80 ms frame,
the probability of every token. Then, for a target text, CTC forced alignment
finds the best way to lay tokens spelling that text over the audio. Any
spelling counts: harakat are optional and letter forms (أ/ا, ة/ه, ى/ي) are
equal, so a correctly recited word isn't penalised for how the model would have
written it. Each word gets a score: the average best log-probability of the
pieces used for it (0 = certain, more negative = the audio doesn't fit). From that:

  - per-word false alarms on correct recitation, at several thresholds;
  - a skipped word: one extra word inserted into the target (no audio for it);
  - a wrong word: one word in the target swapped for a word from elsewhere;
  - wrong verse and "which ayah am I on": the audio scored against nearby ayat.

Before trusting any score it checks itself: greedy decoding of its own
probabilities must reproduce sherpa-onnx's transcripts for the same clips,
which proves the audio features are computed the same way.

Uses the audio cached by `eval_quran_asr.py audio` (run that first).
    python3 -m pip install onnxruntime
    python3 scripts/align_quran_asr.py --retasy 2>&1 | tee ~/niyat-asr/align.txt
Re-score a saved run without the model:
    python3 scripts/align_quran_asr.py --rescore docs/research/asr-eval-align.jsonl
"""

import argparse
import collections
import json
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import eval_quran_asr as ev  # noqa: E402
from try_quran_asr import DEFAULT_DIR, load_audio, words  # noqa: E402

SR = 16000
HARAKAT = "ًٌٍَُِّْ"
THRESHOLDS = (-0.5, -1.0, -2.0, -3.0, -5.0)
VARIANTS = ("letters",)
SCORED_GROUPS = ("seen", "amateur (correct)", "amateur (unlabelled)", "amateur (in_correct)")


# ---------------------------------------------------------------- features

def mel_filters(n_mels=80, n_fft=512, sr=SR):
    """librosa.filters.mel(sr, n_fft, n_mels) with Slaney scale and norm, as NeMo uses."""
    import numpy as np

    def hz_to_mel(f):
        f = np.asarray(f, dtype=np.float64)
        lin = 3.0 * f / 200.0
        log = 15.0 + np.log(np.maximum(f, 1e-10) / 1000.0) / (np.log(6.4) / 27.0)
        return np.where(f >= 1000.0, log, lin)

    def mel_to_hz(m):
        m = np.asarray(m, dtype=np.float64)
        lin = 200.0 * m / 3.0
        log = 1000.0 * np.exp((np.log(6.4) / 27.0) * (m - 15.0))
        return np.where(m >= 15.0, log, lin)

    fft_freqs = np.linspace(0, sr / 2, n_fft // 2 + 1)
    mel_f = mel_to_hz(np.linspace(hz_to_mel(0.0), hz_to_mel(sr / 2), n_mels + 2))
    fdiff = np.diff(mel_f)
    ramps = mel_f[:, None] - fft_freqs[None, :]
    lower = -ramps[:-2] / fdiff[:-1, None]
    upper = ramps[2:] / fdiff[1:, None]
    weights = np.maximum(0, np.minimum(lower, upper))
    weights *= (2.0 / (mel_f[2:n_mels + 2] - mel_f[:n_mels]))[:, None]
    return weights.astype(np.float32)


_MEL = None


def features(samples, mode="nemo", n_fft=512, win=400, hop=160):
    """80 log-mel features, per-feature normalised. mode "nemo" follows NeMo's
    AudioToMelSpectrogramPreprocessor (pre-emphasis 0.97, centred STFT with a
    Hann 400 window in a 512 FFT, hop 160, Slaney mels, log(x + 2^-24)); mode
    "kaldi" follows kaldi-native-fbank as sherpa-onnx configures it for NeMo
    models. The self-check picks whichever reproduces sherpa-onnx. Returns (80, T)."""
    import numpy as np
    global _MEL
    if _MEL is None:
        _MEL = mel_filters()
    x = np.asarray(samples, dtype=np.float64)
    if mode == "kaldi":
        # kaldi-native-fbank with snip_edges=false (what sherpa-onnx uses): frames
        # centred on multiples of the hop, edges reflected, pre-emphasis per frame,
        # 400-sample Hann window zero-padded to 512, log floored at float epsilon.
        n = len(x)
        frames = max(1, (n + hop // 2) // hop)
        idx = np.arange(win)[None, :] + (hop * np.arange(frames) + hop // 2 - win // 2)[:, None]
        idx = np.where(idx < 0, -idx - 1, idx)
        idx = np.where(idx >= n, 2 * n - 1 - idx, idx)
        fr = x[np.clip(idx, 0, n - 1)]
        fr = np.concatenate([fr[:, :1] * (1 - 0.97), fr[:, 1:] - 0.97 * fr[:, :-1]], axis=1)
        fr = fr * (0.5 - 0.5 * np.cos(2 * np.pi * np.arange(win) / (win - 1)))
        spec = np.abs(np.fft.rfft(fr, n=n_fft)) ** 2
        feats = np.log(np.maximum(_MEL @ spec.T.astype(np.float32), np.finfo(np.float32).eps))
    else:
        x = np.concatenate([x[:1], x[1:] - 0.97 * x[:-1]])
        x = np.pad(x, (n_fft // 2, n_fft // 2))
        window = np.zeros(n_fft)
        left = (n_fft - win) // 2
        window[left:left + win] = np.hanning(win)
        frames = 1 + (len(x) - n_fft) // hop
        idx = np.arange(n_fft)[None, :] + hop * np.arange(frames)[:, None]
        spec = np.abs(np.fft.rfft(x[idx] * window, n=n_fft)) ** 2
        feats = np.log(_MEL @ spec.T.astype(np.float32) + 2.0 ** -24)
    mean = feats.mean(axis=1, keepdims=True)
    std = feats.std(axis=1, ddof=1, keepdims=True) if feats.shape[1] > 1 else np.ones_like(mean)
    return ((feats - mean) / (std + 1e-5)).astype(np.float32)


# ---------------------------------------------------------------- model

class CTCModel:
    def __init__(self, path, tokens_path):
        import onnxruntime as ort
        opts = ort.SessionOptions()
        opts.intra_op_num_threads = 2
        self.sess = ort.InferenceSession(path, opts, providers=["CPUExecutionProvider"])
        ins = self.sess.get_inputs()
        self.feat_in = next(i for i in ins if len(i.shape) == 3)
        self.len_in = next((i for i in ins if i is not self.feat_in), None)
        self.channels_first = self.feat_in.shape[1] == 80
        self.vocab, self.id_of = [], {}
        for line in open(tokens_path, encoding="utf-8"):
            line = line.rstrip("\n")
            if not line:
                continue
            piece, idx = line.rsplit(" ", 1) if " " in line.strip() else (line, len(self.vocab))
            idx = int(idx)
            while len(self.vocab) <= idx:
                self.vocab.append("")
            self.vocab[idx] = piece
            self.id_of.setdefault(piece, idx)
        meta = self.sess.get_modelmeta().custom_metadata_map
        self.blank = int(meta.get("blank_id", self.id_of.get("<blk>", len(self.vocab) - 1)))
        self.unk = self.id_of.get("<unk>")
        self.chars = set("".join(p for p in self.vocab if not p.startswith("<")))
        self.max_piece = max(len(p) for p in self.vocab)
        self.space = "▁" if any(p.startswith("▁") for p in self.vocab) else None

    def logprobs(self, samples, mode="nemo"):
        """(T', V) log-probabilities."""
        import numpy as np
        f = features(samples, mode)
        x = f[None] if self.channels_first else f.T[None]
        feeds = {self.feat_in.name: x}
        if self.len_in is not None:
            dtype = np.int32 if "int32" in self.len_in.type else np.int64
            feeds[self.len_in.name] = np.array([f.shape[1]], dtype=dtype)
        out = self.sess.run(None, feeds)[0][0]
        out = out - out.max(axis=-1, keepdims=True)
        return out - np.log(np.exp(out).sum(axis=-1, keepdims=True))

    def greedy(self, lp):
        best = lp.argmax(axis=-1)
        out, prev = [], None
        for t in best:
            if t != prev and t != self.blank:
                out.append(self.vocab[t])
            prev = t
        text = "".join(out)
        return (text.replace("▁", " ") if self.space else text).strip()

    def build_groups(self):
        """Group the vocabulary by what each piece spells in letters only
        (harakat dropped, alef / ya / ta marbuta forms folded, as in the matcher).
        Pieces that spell nothing (pure harakat, punctuation, <unk>) are fillers,
        like the blank: they can be emitted anywhere without consuming a letter."""
        import numpy as np
        groups = collections.defaultdict(list)
        filler = [self.blank]
        for i, piece in enumerate(self.vocab):
            if i == self.blank or not piece:
                continue
            space = self.space and piece.startswith(self.space)
            body = ev.letters(piece[1:] if space else piece)
            key = ("▁" if space else "") + body
            if key:
                groups[key].append(i)
            else:
                filler.append(i)
        self.group_keys = list(groups)
        self.group_of = {k: g for g, k in enumerate(self.group_keys)}
        self.group_members = [np.array(groups[k]) for k in self.group_keys]
        self.filler = np.array(filler)
        self.max_group = max(len(k) for k in self.group_keys)

    def group_logprobs(self, lp):
        """(T, G) best log-prob of any piece in each letter group, and (T,) filler."""
        import numpy as np
        g = np.stack([lp[:, m].max(axis=1) for m in self.group_members], axis=1)
        return g, lp[:, self.filler].max(axis=1)


def model_spelling(word):
    """An Imla'i word reduced to the letters the model writes: no dagger alef
    (it writes الرحمن, ذلك), harakat and letter forms ignored by ev.letters."""
    return ev.letters(word.replace("ٰ", ""))


# ---------------------------------------------------------------- alignment

def lattice_align(lpg, lpf, model, word_list):
    """CTC Viterbi alignment of a word sequence where each word may be spelled
    with ANY sequence of vocabulary pieces whose letters spell it (harakat and
    letter forms ignored). States: "between pieces at letter position p" (blank
    or filler emitted) or "inside piece arc k". Returns (word scores, total
    path log-prob) or None when the audio is too short for the letters.
    A word's score is the mean, over the pieces used for it, of the best
    log-probability that piece reached."""
    import numpy as np
    text, word_of = "", []
    for w, word in enumerate(word_list):
        piece = "▁" + model_spelling(word)
        text += piece
        word_of += [w] * len(piece)
    P = len(text)
    starts, ends, gids = [], [], []
    for i in range(P):
        for j in range(i + 1, min(P, i + model.max_group) + 1):
            g = model.group_of.get(text[i:j])
            if g is not None:
                starts.append(i)
                ends.append(j)
                gids.append(g)
    if not starts:
        return None
    starts, ends, gids = np.array(starts), np.array(ends), np.array(gids)
    T, neg = lpg.shape[0], -1e30
    B = np.full(P + 1, neg)
    B[0] = lpf[0]
    A = np.where(starts == 0, lpg[0, gids], neg)
    stay_bt = np.zeros((T, len(starts)), dtype=bool)
    src_bt = np.full((T, P + 1), -1, dtype=np.int64)

    def entry(A, B):
        order = np.lexsort((A, ends))
        e_sorted = ends[order]
        last = np.r_[e_sorted[1:] != e_sorted[:-1], True]
        E = np.full(P + 1, neg)
        Eidx = np.full(P + 1, -1, dtype=np.int64)
        E[e_sorted[last]] = A[order[last]]
        Eidx[e_sorted[last]] = order[last]
        better = E > B
        return np.where(better, E, B), np.where(better, Eidx, -1)

    for t in range(1, T):
        ent, src = entry(A, B)
        from_entry = ent[starts]
        stay = A >= from_entry
        A = np.where(stay, A, from_entry) + lpg[t, gids]
        B = ent + lpf[t]
        stay_bt[t], src_bt[t] = stay, src
    ent, src = entry(A, B)
    if ent[P] <= neg / 2:
        return None
    # Backtrack. State: ("arc", k) or ("pos", p).
    state = ("pos", P) if src[P] == -1 else ("arc", int(src[P]))
    best = {}
    for t in range(T - 1, -1, -1):
        kind, v = state
        if kind == "arc":
            best[v] = max(best.get(v, neg), lpg[t, gids[v]])
            if t == 0 or stay_bt[t, v]:
                continue
            p = int(starts[v])
        else:
            if t == 0:
                break
            p = v
        k = int(src_bt[t, p])
        state = ("pos", p) if k == -1 else ("arc", k)
    per_word = collections.defaultdict(list)
    for k, score in best.items():
        per_word[word_of[int(starts[k])]].append(score)
    scores = [float(np.mean(per_word[w])) if w in per_word else neg for w in range(len(word_list))]
    return scores, float(ent[P])


def ayah_fit(lp, lpg, lpf, model, word_list):
    """(word scores, per-frame fit) of the audio against a word list; per-frame
    fit = (forced path log-prob - best free path log-prob) / frames, <= 0."""
    res = lattice_align(lpg, lpf, model, word_list)
    if res is None:
        return None, float("-inf")
    scores, total = res
    return scores, (total - float(lp.max(axis=-1).sum())) / lp.shape[0]


# ---------------------------------------------------------------- experiment

def experiment(lp, model, s, a, rng):
    """Every test for one single-ayah clip."""
    lpg, lpf = model.group_logprobs(lp)
    n_ayat = len(ev.quran()[str(s)])
    target = ev.ayah_words(s, a, ev.IMLAEI)
    clean, fit = ayah_fit(lp, lpg, lpf, model, target)
    r = {"clean": clean, "fit": fit}
    # Which ayah fits best, among this one and up to two either side.
    cands = {}
    for b in range(max(1, a - 2), min(n_ayat, a + 2) + 1):
        cands[b] = fit if b == a else ayah_fit(lp, lpg, lpf, model, ev.ayah_words(s, b, ev.IMLAEI))[1]
    r["candidates"] = cands
    other = a + 1 if a < n_ayat else a - 1
    if other != a:
        r["wrong_fit"] = cands.get(other)
        pool = ev.ayah_words(s, other, ev.IMLAEI)
        if len(target) >= 2:
            pos = rng.randrange(0, len(target) + 1)
            extra = rng.choice(pool)
            sk, _ = ayah_fit(lp, lpg, lpf, model, target[:pos] + [extra] + target[pos:])
            r["skip"] = {"pos": pos, "scores": sk}
            pos = rng.randrange(0, len(target))
            swaps = [w for w in pool if model_spelling(w) != model_spelling(target[pos])]
            if swaps:
                sub, _ = ayah_fit(lp, lpg, lpf, model, target[:pos] + [rng.choice(swaps)] + target[pos + 1:])
                r["sub"] = {"pos": pos, "scores": sub}
    return {VARIANTS[0]: r}


def check_stats(pairs):
    """(exact letter matches, mean letter similarity) of (ours, sherpa) transcripts."""
    import difflib
    same, sims = 0, []
    for ours, theirs in pairs:
        a, b = ev.letters("".join(words(ours))), ev.letters("".join(words(theirs)))
        same += a == b
        sims.append(difflib.SequenceMatcher(a=a, b=b, autojunk=False).ratio() if (a or b) else 1.0)
    return same, sum(sims) / max(len(sims), 1)


def summarise(records):
    groups = collections.OrderedDict((g, []) for g in SCORED_GROUPS)
    for r in records:
        if r.get("group") in groups:
            groups[r["group"]].append(r)
    checks = [r for r in records if "greedy" in r]
    if checks:
        same, sim = check_stats([(r["greedy"], r["sherpa"]) for r in checks])
        mode = checks[0].get("features", "nemo")
        print(f"\n### Self-check\n\nWith `{mode}` features, greedy decoding of this script's probabilities "
              f"matched sherpa-onnx's transcript exactly (letters) on {same} of {len(checks)} clips; average "
              f"letter similarity {sim:.1%}. "
              + ("Close enough: the scores below come from the same model output sherpa-onnx sees."
                 if sim >= 0.97 else
                 "**The features still differ noticeably from sherpa-onnx's; treat the scores with caution.**"))

    for v in VARIANTS:
        print("\n### Word and ayah scores (any spelling of the expected letters)\n")
        print("Word-level: a correct word is a false alarm when its score is below the threshold; "
              "a skipped word (inserted into the target, no audio) or a wrong word (swapped for a word "
              "from the next ayah) is caught when its score is below it.\n")
        print("| group | clips | threshold | correct words flagged | correct ayat with any flag | "
              "skipped word caught | wrong word caught |")
        print("|---|---|---|---|---|---|---|")
        for g, rs in groups.items():
            rs = [r for r in rs if r[v].get("clean")]
            if not rs:
                continue
            for thr in THRESHOLDS:
                words_n = sum(len(r[v]["clean"]) for r in rs)
                fa = sum(sum(x < thr for x in r[v]["clean"]) for r in rs)
                any_fa = sum(any(x < thr for x in r[v]["clean"]) for r in rs)
                sk = [r[v]["skip"] for r in rs if r[v].get("skip") and r[v]["skip"]["scores"]]
                sb = [r[v]["sub"] for r in rs if r[v].get("sub") and r[v]["sub"]["scores"]]
                skc = sum(x["scores"][x["pos"]] < thr for x in sk)
                sbc = sum(x["scores"][x["pos"]] < thr for x in sb)
                print(f"| {g} | {len(rs)} | {thr} | {fa / words_n:.1%} | {any_fa / len(rs):.1%} | "
                      f"{skc / max(len(sk), 1):.1%} | {sbc / max(len(sb), 1):.1%} |")
        print("\nAyah-level (follow-along): 'which ayah' picks the best-fitting of this ayah and up to two "
              "either side; 'wrong verse' compares the fit against the next ayah's text.\n")
        print("| group | clips | right ayah picked | wrong verse fits worse than the right one |")
        print("|---|---|---|---|")
        for g, rs in groups.items():
            rs = [r for r in rs if r[v].get("candidates")]
            if not rs:
                continue
            picked = sum(int(max(r[v]["candidates"], key=lambda b: r[v]["candidates"][b])) == r["ayah"] for r in rs)
            wv = [r for r in rs if r[v].get("wrong_fit") is not None]
            worse = sum(r[v]["wrong_fit"] < r[v]["fit"] for r in wv)
            print(f"| {g} | {len(rs)} | {picked / len(rs):.1%} | {worse / max(len(wv), 1):.1%} |")

    inc = groups.get("amateur (in_correct)", [])
    cor = groups.get("amateur (correct)", [])
    if inc and cor:
        print("\n### Real mistakes (RetaSy labels)\n")
        print("Clip flagged = at least one word below the threshold. A good checker flags the "
              "`in_correct` clips and not the `correct` ones.\n")
        print("| threshold | in_correct clips flagged | correct clips flagged |")
        print("|---|---|---|")
        for thr in THRESHOLDS:
            v = VARIANTS[0]
            fi = sum(any(x < thr for x in r[v]["clean"] or []) for r in inc)
            fc = sum(any(x < thr for x in r[v]["clean"] or []) for r in cor)
            print(f"| {thr} | {fi}/{len(inc)} | {fc}/{len(cor)} |")


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model-dir", default=DEFAULT_DIR)
    p.add_argument("--model", default="q8", choices=("q8", "mixed"))
    p.add_argument("--out", default=os.path.join(DEFAULT_DIR, "eval"))
    p.add_argument("--retasy", action="store_true", help="include the RetaSy amateur clips")
    p.add_argument("--retasy-limit", type=int, default=150)
    p.add_argument("--quick", action="store_true")
    p.add_argument("--checks", type=int, default=40, help="clips to cross-check against sherpa-onnx")
    p.add_argument("--features", default="auto", choices=("auto", "nemo", "kaldi"),
                   help="audio feature recipe; auto = whichever reproduces sherpa-onnx best")
    p.add_argument("--rescore", help="summarise a saved align.jsonl instead of running the model")
    args = p.parse_args()
    if args.rescore:
        summarise([json.loads(line) for line in open(args.rescore, encoding="utf-8") if line.strip()])
        return

    try:
        import numpy  # noqa: F401
        import onnxruntime  # noqa: F401
    except ImportError:
        sys.exit("Install first:  python3 -m pip install onnxruntime numpy")
    path = os.path.join(args.model_dir, f"qurankarim-fastconformer-{args.model}.onnx")
    tokens = os.path.join(args.model_dir, "tokens.txt")
    for f in (path, tokens):
        if not os.path.exists(f):
            sys.exit(f"Missing {f}. See the setup steps in eval_quran_asr.py.")
    model = CTCModel(path, tokens)
    print(f"{args.model}: {len(model.vocab)} tokens, blank {model.blank}, "
          f"input {model.feat_in.name} {model.feat_in.shape}", flush=True)

    clips = ev.build_clips(argparse.Namespace(quick=args.quick, manifest=None, retasy=args.retasy,
                                              retasy_limit=args.retasy_limit),
                           os.path.join(args.out, "audio"), {})
    clips = [c for c in clips if c[3] == c[4] and c[0] in SCORED_GROUPS]
    print(f"{len(clips)} single-ayah clips", flush=True)

    sherpa = None
    if args.checks:
        try:
            sherpa = ev.Model(path, tokens, 2)
        except Exception as e:  # noqa: BLE001
            print(f"  ! sherpa-onnx not available for the self-check: {e}")
    mode = args.features
    if sherpa is not None and mode == "auto":
        print(f"Self-check on {min(args.checks, len(clips))} clips: which audio features reproduce sherpa-onnx?",
              flush=True)
        pairs = {"nemo": [], "kaldi": []}
        for c in clips[: args.checks]:
            samples = load_audio(c[5])
            theirs = sherpa(samples)[0]
            for m in pairs:
                pairs[m].append((model.greedy(model.logprobs(samples, m)), theirs))
        results = {m: check_stats(p) for m, p in pairs.items()}
        for m, (same, sim) in results.items():
            print(f"  {m}: {same}/{len(pairs[m])} exact, {sim:.1%} letter similarity", flush=True)
        mode = max(results, key=lambda m: (results[m][1], results[m][0]))
        print(f"  using {mode}", flush=True)
    elif mode == "auto":
        mode = "nemo"
    model.build_groups()
    rng = random.Random(7)
    os.makedirs(args.out, exist_ok=True)
    out_path = os.path.join(args.out, "align.jsonl")
    records = []
    with open(out_path, "w", encoding="utf-8") as log:
        for n, (group, spk, s, a, _, clip) in enumerate(clips, 1):
            samples = load_audio(clip)
            lp = model.logprobs(samples, mode)
            rec = {"group": group, "speaker": spk, "surah": s, "ayah": a, "seconds": len(samples) / SR,
                   "frames": int(lp.shape[0]), "features": mode}
            if sherpa is not None and n <= args.checks:
                rec["greedy"] = model.greedy(lp)
                rec["sherpa"] = sherpa(samples)[0]
            rec.update(experiment(lp, model, s, a, rng))
            records.append(rec)
            log.write(json.dumps(rec, ensure_ascii=False) + "\n")
            if n % 50 == 0:
                print(f"  {n}/{len(clips)}", flush=True)
    summarise(records)
    print(f"\nAll scores: {out_path}")


if __name__ == "__main__":
    main()
