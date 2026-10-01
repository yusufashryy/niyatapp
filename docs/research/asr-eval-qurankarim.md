# Evaluating QuranKarim FastConformer (on-device Qur'an speech recognition)

Date: 2026-10-01. Research only, no app code changed.

Model: [TheGreatQuran/QuranKarim-SpeechToText-onnxModel](https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel),
an NVIDIA FastConformer CTC model fine-tuned on `tarteel-ai/everyayah`. It writes Arabic with harakat
and runs with sherpa-onnx (`OfflineRecognizer.from_nemo_ctc`, 16 kHz mono). Files:
`qurankarim-fastconformer-mixed.onnx` (87 MB), `-q8.onnx`, the full-precision `.onnx` (458 MB), and `tokens.txt`.
The model card claims 0.14% WER. Nobody has checked that figure.

## Summary (read this first)

**The audio part of this evaluation could not be run.** The cloud container used for it has a
network policy that blocks every host the test needs. Each request was refused with
`403 CONNECT tunnel failed`, on the first attempt and again on a retry:

| Host | Needed for | Result |
|---|---|---|
| `huggingface.co` | the model files and `tokens.txt`; RetaSy / Tarteel datasets | blocked |
| `everyayah.com` | seen-reciter per-ayah audio | blocked |
| `server*.mp3quran.net` | unseen-reciter whole-surah audio | blocked |
| `cdn.islamic.network` | alternative per-ayah audio | blocked |

So this report has **no measured accuracy, robustness, mistake-detection or speed numbers for
the model.** It does not make any up. What it has:

1. `scripts/eval_quran_asr.py`, the full evaluation, ready to run on a Mac (or in a cloud
   environment that allows those hosts). It covers seen reciters, unseen reciters, amateurs
   (your own clips or RetaSy), noise/phone/speed variants, the wrong-verse and skipped-word tests,
   the harakat false-alarm rate, and mixed vs q8 speed at 1 and 2 threads. Any host it can't
   reach is reported, not hidden. The download, noise, band-limit and speed code was tested
   here on synthetic audio: measured SNRs come out at exactly 20 / 10 / 5 dB.
2. **Measured, text-only results** that don't need the model (below). They show that the
   current comparison in `try_quran_asr.py` would raise many false alarms from *spelling
   differences alone*, which would make any model look worse than it is. They also show what
   fixes that. The fixes are implemented as `compare_v2` / `harakat_v2` in the evaluation script.
3. Limits for the go/no-go decision, so the audio run gives a clear answer.

**Verdict for now: not yet decidable.** The text results show the comparison side is in good
shape once normalised. Whether the *model* is good enough depends on the amateur and unseen-reciter
numbers, which need the audio run. The card's 0.14% WER is almost certainly measured on EveryAyah,
which is the same reciters the model trained on. Our roadmap notes that EveryAyah-trained models
have reached about 23% WER on crowd-sourced recitation. Expect the gap to be large until measured
otherwise.

## How to run the real evaluation

On a Mac (Terminal), from the repo folder:

```sh
brew install ffmpeg
python3 -m pip install sherpa-onnx numpy
mkdir -p ~/niyat-asr && cd ~/niyat-asr
for f in qurankarim-fastconformer-mixed.onnx qurankarim-fastconformer-q8.onnx tokens.txt; do
  curl -LO https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main/$f
done
cd -   # back to the repo
python3 scripts/eval_quran_asr.py audio --quick          # 2-minute smoke test
python3 scripts/eval_quran_asr.py audio                  # full run (seen + unseen)
python3 scripts/eval_quran_asr.py audio --retasy         # + amateurs (pip install datasets soundfile)
python3 scripts/eval_quran_asr.py audio --manifest mine.csv   # + your own recordings
```

It prints Markdown tables you can paste into this file. Every transcript goes to
`~/niyat-asr/eval/transcripts.jsonl`. In a Claude cloud session, first allow `huggingface.co`,
`everyayah.com`, `mp3quran.net` and `cdn.islamic.network` in the environment's network settings.

`mine.csv` looks like this (one row per recording; `group` is any label, such as `amateurs`):

```
path,surah,first,last,group,speaker
/Users/me/Desktop/fatiha.m4a,1,1,7,amateurs,me
```

## Test design (what the script does)

**Ayat** (94 per reciter): 1:1-7, 2:1-20, 18:1-10, 36:1-12, 55:1-20, 67:1-10, 112:1-4, 113:1-5, 114:1-6.
This mix has long ayat (2:19-20, 18:5) and very short ones (55:13 فَبِأَيِّ آلَاءِ رَبِّكُمَا تُكَذِّبَانِ repeats, 112:1-4).

| Group | Source | Reciters | Clips |
|---|---|---|---|
| Seen reciters | everyayah.com per-ayah MP3 | Alafasy_128kbps, Husary_128kbps, Abdul_Basit_Murattal_192kbps, Minshawy_Murattal_128kbps, Ghamadi_40kbps, Abdullah_Basfar_192kbps | 6 × 94 = 564 |
| Unseen reciters | mp3quran.net whole-surah files, surahs 1, 103, 108, 112, 113, 114 | Islam Sobhi, Raad Al-Kurdi, Abdulrahman Mosad (not on EveryAyah as far as known; the mp3quran URLs in the script are best guesses, so check them if they 404) | 18 |
| Amateurs | `RetaSy/quranic_audio_dataset` (non-Arabic speakers, labelled), or your own clips via `--manifest` | | up to 150 |
| Noisy | 60 random seen single-ayah clips × white noise SNR 20/10/5, babble SNR 10/5 (4 other reciters mixed), phone band 300-3400 Hz at 8 kHz, tempo 0.9× and 1.15× | | 480 |

Reciters who start a surah with the Bismillah are not penalised for it (it is stripped from the
transcript when the ayah text doesn't include it). For the unseen set, `cdn.islamic.network` was
considered and rejected: nearly all of its Arabic editions are reciters that EveryAyah also hosts.

**Metrics.** Words are lined up on letters only (spelling variants folded, as in
`try_quran_asr.letters()`). Then:
- **letters-WER** = (different + missed + extra) / expected words
- **word accuracy** = words matched on letters / expected words
- **harakat agreement** = matched words whose harakat are identical / matched words
- **sequence accuracy** = clips with zero letter errors
- **RTF** (real-time factor) = decode time / audio length, mixed vs q8, 1 and 2 CPU threads

Each metric is reported with the current `compare()` and with the proposed `compare_v2`.

**Synthetic mistakes** (clean single-ayah clips, mixed model):
- *Wrong verse*: audio of ayah N scored against the text of N+1. It counts as "caught" if word accuracy is below 0.5. The false-alarm side is correct ayat that fall below the same 0.5.
- *Skipped word*: one word (taken from the next ayah) is inserted into the expected text, so the reciter "skipped" it. It counts as caught if that exact word is flagged missed or different. Words flagged elsewhere are counted too.
- *Harakat false alarms*: matched words whose harakat differ, on clean professional audio, where the reciters are assumed correct.

## Results that could be measured (text only)

These answer one question: if the model heard everything perfectly but wrote it the way it
probably writes (everyday Imla'i spelling with tashkeel, like most Qur'an ASR training text), how
many words would our checker still flag? That is the floor of false alarms caused by the comparison
itself. "Heard" here is Tanzil's Imla'i edition of the same Hafs text
(`quran-imlaei.json`); "expected" is `quran-uthmani.json`. Neither file was modified.

| Comparison | Scope | Words | letters-WER | Harakat agreement | Ayat with zero flags |
|---|---|---|---|---|---|
| current `compare()` | whole Qur'an, 6,236 ayat | 77,433 | 2.72% | 98.06% | 63.9% |
| `compare_v2` | whole Qur'an | 77,433 | **0.00%** | **99.99%** | **99.9%** |
| current `compare()` | the 94 eval ayat | 695 | 0.86% | 96.81% | 76.6% |
| `compare_v2` | the 94 eval ayat | 695 | **0.00%** | **99.86%** | **98.9%** |

So with today's script, **about 1 in 3 perfectly recited ayat would be flagged** across the Qur'an
because of spelling alone. With the fixes, it is about 1 in 1,000.

What causes it, and what `compare_v2` changes:

| Cause (count in the whole Qur'an) | Example: expected (Uthmani) / heard (Imla'i) | Fix in `compare_v2` |
|---|---|---|
| Vocative يا written joined in Uthmani, separate in Imla'i (≈350) | يَٰٓأَيُّهَا / يَا أَيُّهَا · يَٰقَوْمِ / يَا قَوْمِ | Two heard words that join into an expected word count as that word |
| Uthmani rasm spellings (≈1,400) | ٱلصَّلَوٰةَ / الصَّلَاةَ · ٱلْحَيَوٰةِ / الْحَيَاةِ · ٱلَّيْلِ / اللَّيْلِ · شَيْـًٔا / شَيْئًا · إِسْرَٰٓءِيلَ / إِسْرَائِيلَ · إِبْرَٰهِـۧمَ / إِبْرَاهِيمَ | Accept the everyday spelling listed for that word in `recognition-forms.json` (the app already ships this file; the eval script now uses it) |
| Madda alef: Uthmani writes hamza + fatha + alef, Imla'i writes آ with no fatha (≈1,470 harakat flags, nearly all of them) | ءَامَنُوا۟ / آمَنُوا · ٱلْـَٔاخِرَةِ / الْآخِرَةِ · ٱلْقُرْءَانَ / الْقُرْآنَ | `harakat_v2` reads آ as ءَا |
| Marks on one letter in a different order (shadda + vowel) | | `harakat_v2` puts each letter's marks in a fixed order (shadda first) |

What is left after the fixes: 1 letter case (يَبْنَؤُمَّ / يَا ابْنَ أُمَّ, three words in Imla'i,
20:94) and 4 harakat cases (مَجْر۪ىٰهَا with imala, عِوَجَا vs عِوَجًا at a pause in 18:1,
ءَاتَىٰنِۦَ, and ءَا۬عْجَمِىٌّ with tas-heel). All of these are genuine reading features, and the
checker should probably skip harakat on them.

### Marks in the Uthmani file, and how the comparison treats them

Counted over all of `quran-uthmani.json`:

| Mark | Count | Treated as |
|---|---|---|
| fatha / kasra / damma / sukun U+0652 / shadda / tanween | 3,741-123,396 each | harakat |
| **U+06E1 (Uthmani round sukun)** | **0** | This file uses the plain sukun U+0652 throughout. `harakat()` already maps U+06E1 to sukun in case the *model* writes it. Check the model's `tokens.txt` for U+06E1 when the files can be downloaded. |
| U+0670 dagger alef ٰ | 9,838 | letters: folded to ا (so ٱلْعَٰلَمِينَ = العالمين). harakat: ignored. Fine. |
| U+0653 maddah above | 5,376 | ignored |
| U+06DF small high rounded zero (letter written but not read, e.g. ءَامَنُوا۟) | 3,988 | ignored. The silent letter is still counted for letters, which matches Imla'i spelling (آمَنُوا keeps the alef). Fine. |
| U+06E5 small waw ۥ, U+06E6 small yeh ۦ (silah) | 1,257 / 957 | dropped from letters (category Lm). Fine: Imla'i writes لَهُ, not لَهُو. |
| U+0640 tatweel | 812 | dropped. `harakat_v2` treats it as a letter boundary. |
| U+0654 hamza above | 773 | ignored |
| U+06E2 / U+06ED small meem (iqlab) | 510 / 99 | ignored. Don't add these to harakat: no ASR model writes them. |
| U+06E0, U+06E7, U+06DC, U+06E8, U+06E3, U+06EA-06EC | 1-66 | ignored |

### Mistake detection: best case, with simulated recognition errors

To see how much recognition error each check can tolerate, the Imla'i text was used as the
transcript, and random word errors (wrong letter, dropped word, extra junk word) were added at a
fixed rate. All 6,122 ayah pairs in the Qur'an were used, scored with `compare_v2`.

| Simulated word error rate | Correct ayah flagged (≥1 letter error) | Wrong verse caught (acc < 0.5) | Correct ayah with acc < 0.5 | Skipped word caught (exact word) | Other words flagged per skip test |
|---|---|---|---|---|---|
| 0% | 0.0% | 99.1% | 0.0% | 96.9% | 0.11 |
| 2% | 20.2% | 99.1% | 0.0% | 97.1% | 0.35 |
| 5% | 42.0% | 99.2% | 0.1% | 97.5% | 0.73 |
| 10% | 63.3% | 99.2% | 0.3% | 97.0% | 1.36 |
| 20% | 82.2% | 99.3% | 1.1% | 97.8% | 2.55 |

What this means:
- **Wrong-verse detection is robust.** Even at 20% word errors, a word-accuracy threshold of 0.5
  catches 99% of wrong verses and wrongly rejects about 1% of correct ones. The 0.9% it misses at
  0% are ayat whose neighbour shares most of its words (for example, the repeated refrain in Surah 55).
- **Skipped words are always noticed** (the transcript has one word fewer, so something is always
  flagged). The *exact* word is right about 97% of the time. The rest are cases where the skipped
  word also appears next to it (such as ٱللَّهِ twice), so a neighbouring copy is flagged instead.
- **Flagging every single wrong word is the fragile part.** At 5% word errors, 42% of correctly
  recited ayat would get at least one false flag. An app that marks words red needs a confidence
  gate: CTC per-token scores, flagging only when the same word is wrong twice, or only after
  the user finishes the ayah. Or the model's error rate on real users must be well under 2%.

## Results that could not be measured

The tables below come from `scripts/eval_quran_asr.py audio`. **They are empty because the
audio and model hosts were blocked.** Fill them from the script's output.

| Group | clips | letters-WER | word acc | harakat agree | sequence acc |
|---|---|---|---|---|---|
| Seen reciters (mixed) | not run | | | | |
| Seen reciters (q8, 150-clip subset) | not run | | | | |
| Unseen reciters (mixed) | not run | | | | |
| Amateurs (mixed) | not run | | | | |
| Noisy / phone / speed (mixed) | not run | | | | |

Not run: mistake detection on real transcripts, the harakat false-alarm rate on professional
audio, decode speed (RTF), and failure examples.

## Go/no-go limits for the audio run

Suggested bar for shipping it as an **optional on-device download** ("Check my recitation, beta"),
all measured with `compare_v2`:

| Measure | Ship | Ship as follow-along only (no red words) | Don't ship |
|---|---|---|---|
| Amateurs letters-WER | ≤ 5% | 5-15% | > 15% |
| Unseen reciters letters-WER | ≤ 3% | 3-8% | > 8% |
| Correct ayat (amateur) with any false flag | ≤ 10% | ≤ 30% | > 30% |
| Wrong verse caught at acc < 0.5 | ≥ 95% | ≥ 90% | < 90% |
| Harakat false alarms, professional audio | ≤ 2% | ≤ 5%, harakat check off by default | > 5%: never show harakat flags |
| mixed RTF, 1 thread, container CPU | ≤ 0.3 | ≤ 0.6 | > 1 (slower than real time) |
| q8 vs mixed letters-WER | q8 within 0.5 points means ship q8 (smaller download) | | |

For speed, a recent iPhone CPU core is roughly comparable to one desktop core, so 1-thread
RTF is a fair rough proxy. Core ML / ANE would be faster but needs a conversion step.

## What to fix regardless of the model

1. **Port `compare_v2`'s normalisation into the app's matcher and into `try_quran_asr.py`**:
   join split words, accept `recognition-forms.json` spellings (the app already does this for
   letters), and use `harakat_v2` (madda alef = ءَا, fixed mark order). Without it, about 1 in 3
   correct ayat get flagged by spelling alone.
2. **Harakat checks: compare per letter, not as one string per word, and skip known
   reading-feature words** (imala, tas-heel, pause forms like عِوَجَا). Also consider ignoring the
   last letter's vowel at the end of an ayah, because a reciter stopping there drops it (waqf).
3. **Don't flag on one word alone**: use the wrong-verse threshold (0.5) for "you're on a different
   verse", and require a per-word confidence threshold before marking a word red.
4. When `tokens.txt` can be downloaded, list which marks the model can output (does it use U+06E1,
   dagger alef, U+0671 alef wasla?) and add any it writes to the fold tables.

## Files

- `scripts/eval_quran_asr.py`: the evaluation (`text` mode produced every number above; `audio` mode is the full run).
- `scripts/try_quran_asr.py`: unchanged; its `letters()`, `harakat()`, `words()`, `compare()` and `expected_words()` are reused.
