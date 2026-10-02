#!/usr/bin/env python3
"""Forced-alignment test for the QuranKarim model (research only).

eval_quran_asr.py asks the model "what was said?" and compares its spelling
with the Qur'an, which flags many correct words because the model's spelling
is sloppy (يُؤْمِن for يُؤْمِنُونَ). This script asks a different question:
"how well does the audio fit the words that SHOULD have been said?"

It runs the ONNX model directly (onnxruntime) to get, for every ~80 ms frame,
the probability of every token. Then, for a target text, CTC forced alignment
finds the best way to lay those tokens over the audio, and each word gets a
score: the average log-probability of its tokens where they were placed
(0 = certain, more negative = the audio doesn't fit). From that:

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
VARIANTS = ("vowelled", "bare")
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


def features(samples, n_fft=512, win=400, hop=160):
    """NeMo AudioToMelSpectrogramPreprocessor at inference: pre-emphasis 0.97,
    centred STFT (Hann 400 in a 512 FFT, hop 160), power, 80 Slaney mels,
    log(x + 2^-24), then per-feature normalisation. Returns (80, T)."""
    import numpy as np
    global _MEL
    if _MEL is None:
        _MEL = mel_filters()
    x = np.asarray(samples, dtype=np.float64)
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

    def logprobs(self, samples):
        """(T', V) log-probabilities."""
        import numpy as np
        f = features(samples)
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

    def tokenize(self, word):
        """Greedy longest match against the vocabulary (an approximation of the
        model's SentencePiece segmentation; CTC can score any segmentation)."""
        s = (self.space or "") + word
        ids, i = [], 0
        while i < len(s):
            for j in range(min(len(s), i + self.max_piece), i, -1):
                if s[i:j] in self.id_of:
                    ids.append(self.id_of[s[i:j]])
                    i = j
                    break
            else:
                if self.unk is not None:
                    ids.append(self.unk)
                i += 1
        return ids


def model_spelling(word, variant):
    """An Imla'i word written the way the model writes: no dagger alef (it
    writes الرحمن, ذلك), and for 'bare' no harakat either."""
    word = word.replace("ٰ", "")
    if variant == "bare":
        word = "".join(c for c in word if c not in HARAKAT)
    return word


# ---------------------------------------------------------------- alignment

def force_align(lp, token_lists, blank):
    """CTC Viterbi alignment of a word sequence. Returns (word scores, total
    path log-prob), or None if the audio is too short for the tokens."""
    import numpy as np
    tokens, owner = [], []
    for w, ids in enumerate(token_lists):
        tokens += ids
        owner += [w] * len(ids)
    T, L = lp.shape[0], len(tokens)
    if L == 0:
        return None
    ext = [blank]
    for t in tokens:
        ext += [t, blank]
    ext = np.array(ext)
    S = len(ext)
    skip_ok = np.zeros(S, dtype=bool)
    skip_ok[2:] = (ext[2:] != blank) & (ext[2:] != ext[:-2])
    neg = -1e30
    dp = np.full(S, neg)
    dp[0] = lp[0, ext[0]]
    dp[1] = lp[0, ext[1]]
    back = np.zeros((T, S), dtype=np.int8)
    for t in range(1, T):
        c1 = np.concatenate([[neg], dp[:-1]])
        c2 = np.where(skip_ok, np.concatenate([[neg, neg], dp[:-2]]), neg)
        stacked = np.stack([dp, c1, c2])
        choice = stacked.argmax(axis=0)
        dp = stacked[choice, np.arange(S)] + lp[t, ext]
        back[t] = choice
    end = S - 1 if dp[S - 1] >= dp[S - 2] else S - 2
    total = dp[end]
    if total <= neg / 2:
        return None
    states = np.empty(T, dtype=np.int64)
    s = end
    for t in range(T - 1, -1, -1):
        states[t] = s
        s -= back[t, s]
    best = collections.defaultdict(lambda: neg)
    for t, s in enumerate(states):
        if s % 2 == 1:
            k = s // 2
            best[k] = max(best[k], lp[t, ext[s]])
    per_word = collections.defaultdict(list)
    for k, w in enumerate(owner):
        per_word[w].append(best[k])
    scores = [float(np.mean(per_word[w])) if w in per_word else neg for w in range(len(token_lists))]
    return scores, float(total)


def ayah_fit(lp, model, word_list, variant):
    """(word scores, per-frame fit) of the audio against a word list; per-frame
    fit = (forced path log-prob - best free path log-prob) / frames, <= 0."""
    res = force_align(lp, [model.tokenize(model_spelling(w, variant)) for w in word_list], model.blank)
    if res is None:
        return None, float("-inf")
    scores, total = res
    return scores, (total - float(lp.max(axis=-1).sum())) / lp.shape[0]


# ---------------------------------------------------------------- experiment

def experiment(lp, model, s, a, rng):
    """Every test for one single-ayah clip, both spellings."""
    n_ayat = len(ev.quran()[str(s)])
    target = ev.ayah_words(s, a, ev.IMLAEI)
    rec = {}
    for v in VARIANTS:
        clean, fit = ayah_fit(lp, model, target, v)
        r = {"clean": clean, "fit": fit}
        # Which ayah fits best, among this one and up to two either side.
        cands = {}
        for b in range(max(1, a - 2), min(n_ayat, a + 2) + 1):
            cands[b] = fit if b == a else ayah_fit(lp, model, ev.ayah_words(s, b, ev.IMLAEI), v)[1]
        r["candidates"] = cands
        other = a + 1 if a < n_ayat else a - 1
        if other != a:
            r["wrong_fit"] = cands.get(other)
            pool = ev.ayah_words(s, other, ev.IMLAEI)
            if len(target) >= 2:
                pos = rng.randrange(0, len(target) + 1)
                extra = rng.choice(pool)
                sk, _ = ayah_fit(lp, model, target[:pos] + [extra] + target[pos:], v)
                r["skip"] = {"pos": pos, "scores": sk}
                pos = rng.randrange(0, len(target))
                swaps = [w for w in pool if ev.letters(w) != ev.letters(target[pos])]
                if swaps:
                    sub, _ = ayah_fit(lp, model, target[:pos] + [rng.choice(swaps)] + target[pos + 1:], v)
                    r["sub"] = {"pos": pos, "scores": sub}
        rec[v] = r
    return rec


def summarise(records):
    groups = collections.OrderedDict((g, []) for g in SCORED_GROUPS)
    for r in records:
        if r.get("group") in groups:
            groups[r["group"]].append(r)
    checks = [r for r in records if "greedy" in r]
    if checks:
        same = sum(ev.letters("".join(words(r["greedy"]))) == ev.letters("".join(words(r["sherpa"])))
                   for r in checks)
        print(f"\n### Self-check\n\nGreedy decoding of this script's probabilities matched sherpa-onnx's transcript "
              f"(letters) on {same} of {len(checks)} clips. "
              + ("Features match: scores below are trustworthy." if same >= 0.9 * len(checks) else
                 "**Too many mismatches: the audio features differ from sherpa-onnx's; don't trust the scores.**"))

    for v in VARIANTS:
        print(f"\n### Target spelling: {v}\n")
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
        print("\n### Real mistakes (RetaSy labels, bare spelling)\n")
        print("Clip flagged = at least one word below the threshold. A good checker flags the "
              "`in_correct` clips and not the `correct` ones.\n")
        print("| threshold | in_correct clips flagged | correct clips flagged |")
        print("|---|---|---|")
        for thr in THRESHOLDS:
            fi = sum(any(x < thr for x in r["bare"]["clean"] or []) for r in inc)
            fc = sum(any(x < thr for x in r["bare"]["clean"] or []) for r in cor)
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
    rng = random.Random(7)
    os.makedirs(args.out, exist_ok=True)
    out_path = os.path.join(args.out, "align.jsonl")
    records = []
    with open(out_path, "w", encoding="utf-8") as log:
        for n, (group, spk, s, a, _, clip) in enumerate(clips, 1):
            samples = load_audio(clip)
            lp = model.logprobs(samples)
            rec = {"group": group, "speaker": spk, "surah": s, "ayah": a, "seconds": len(samples) / SR,
                   "frames": int(lp.shape[0])}
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
