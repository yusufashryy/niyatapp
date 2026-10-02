# Evaluating QuranKarim FastConformer (on-device Qur'an speech recognition)

Date: 2026-10-01. Research only, no app code changed.

Model: [TheGreatQuran/QuranKarim-SpeechToText-onnxModel](https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel),
an NVIDIA FastConformer CTC model fine-tuned on `tarteel-ai/everyayah`. It writes Arabic with harakat
and runs with sherpa-onnx (`OfflineRecognizer.from_nemo_ctc`, 16 kHz mono). Files:
`qurankarim-fastconformer-mixed.onnx` (83 MB), `-q8.onnx` (166 MB: twice the size of "mixed",
not smaller), the full-precision `.onnx` (458 MB), and `tokens.txt`.
The model card claims 0.14% WER. Nobody has checked that figure.

## Summary (read this first)

**Status: complete.** Professional reciters (seen and unseen), amateurs (RetaSy), noise / phone /
tempo variants, a silence and dither test, and speed have all been measured. The cloud container that wrote this
couldn't reach the audio or model hosts (its network policy refused `huggingface.co`,
`everyayah.com`, `server*.mp3quran.net`, `cdn.islamic.network`). So the owner ran the audio on a
Mac and committed the transcripts (`docs/research/asr-eval-transcripts.jsonl`,
`docs/research/asr-eval-padtest.jsonl`). Every number below is recomputed from those files with
`eval_quran_asr.py rescore`.

### Verdict: don't ship it, not even as an optional download

It works on the professional reciters it was trained on, and it's fast. But **on ordinary
learners' voices it gets about half the words wrong, and it can't reliably tell which ayah they're
on**. Those are the people a "check my recitation" feature is for.

| Question | Professionals it was trained on | Professionals it wasn't | Amateurs (non-Arabic speakers) |
|---|---|---|---|
| Words wrong (letters-WER) | 8.3% (q8: 6.6%) | 31% | **56%** (29% on the 14 clips labelled correct) |
| Correctly recited ayah gets at least one false red word | 41% | n/a (whole surahs) | **69%** |
| Right ayah mistaken for a wrong one (follow-along false alarm) | 2.4% | n/a | **41%** |
| Wrong ayah caught | 97% | n/a | 93% |
| Skipped word caught | 98% | n/a | 98%, but 2.4 other words falsely flagged each time |
| Harakat false alarms (where it writes harakat) | 0.16% | 0% | 2% |
| Speed, 1 Mac CPU thread | 30-55× faster than real time | | |

Main findings:

1. **The card's 0.14% WER doesn't hold up anywhere we tested.** Even on its own training reciters
   it's 6.6-8.3%.
2. **The errors come from the model, not from our setup.** The ONNX metadata matches sherpa-onnx's
   NeMo settings (80 mel features, per-feature normalisation, blank id 1024 = last). Adding silence
   makes things worse (8.3% becomes 17% with 1 s of padding). Faint noise barely helps. Most errors
   are word pieces dropped or repeated (يُؤْمِنُونَ heard as يُؤْمِن or يُؤْمِنُونَُونَ), worst on an ayah's
   last word (19% vs 6% for the other words).
3. **q8 is the better file**: 6.6% vs 8.3% letters-WER on the same 564 clips, and 2× faster.
   But it's the larger download (166 MB vs 83 MB; both files are quantised).
4. **The model writes everyday (Imla'i) spelling only.** No Uthmani signs at all: no U+06E1, no
   dagger alef, no alef wasla, no small high letters. The matcher must compare against everyday
   spellings. `compare_v2` does, and it brings spelling-only false alarms from about 1 in 3 ayat
   to about 1 in 100.
5. **Background voices hurt badly** (13% letters-WER at SNR 10, 31% at SNR 5). Phone-band audio
   and tempo changes barely matter. Strong white noise (SNR 10) actually *lowers* errors on the
   same clips (8.7% to 5.4%), a sign the model was trained on noisier audio than studio recordings.

### What would change the verdict

- **Fine-tune for ordinary voices** (roadmap step 3): EveryAyah plus crowd-sourced recitation
  (Tarteel v1, RetaSy's labelled clips), with noise augmentation. Re-run this script on the result.
  The bar: amateurs ≤ 15% letters-WER for follow-along, ≤ 5% for marking mistakes.
- **Or evaluate a different model** with the same script: `audio --manifest` takes any clips, and
  only the `Model` class needs swapping.
- **If it ships to anyone before that, make it follow-along for professionals' recordings only**
  (it's reliable there), with no red words and no harakat flags.

## Smoke test (Mac, `audio --quick`, old scoring)

Alafasy and Husary, 1:1-7 and 112:1-4 (22 clips, 88 words). Scored with the first version of
`compare_v2`, before the fixes it prompted, so treat the harakat columns as wrong.

| group | clips | letters-WER | word acc | harakat agree (old) | sequence acc |
|---|---|---|---|---|---|
| seen, mixed | 22 | 9.09% | 92.05% | 70.37% | 68.2% |
| seen, q8 | 22 | 7.95% | 92.05% | 70.37% | 68.2% |
| + white noise SNR 20 / 10 / 5 | 22 each | 10.2% / 9.1% / 12.5% | | | |
| + babble SNR 10 / 5 | 22 each | 27.3% / 52.3% | | | |
| + phone band 300-3400 Hz | 22 | 9.1% | | | |
| + tempo 0.9× / 1.15× | 22 each | 10.2% / 14.8% | | | |

| model | threads | RTF (decode time / audio time) |
|---|---|---|
| mixed | 1 / 2 | 0.049 / 0.028 |
| q8 | 1 / 2 | 0.025 / 0.014 |

Mistake checks (18 single-ayah clips): wrong verse caught 88.9% with 0% false alarms; skipped
word caught 14/14; correct ayat flagged with at least one letter error 38.9%.

The smoke test exposed three scoring problems, all now fixed in `compare_v2`:

| Flag in the smoke test | Why it was wrong | Fix |
|---|---|---|
| ٱلرَّحْمَٰنِ / الرحمن (DIFFERENT) | the dagger alef was always read as a full alef, but the model drops it in some words (الرحمن) and writes it in others (العالمين) | accept both readings |
| بِسْمِ / بسم, ٱللَّهِ / الله (HARAKA) | the model wrote no harakat, which was scored as all wrong | only letters the model vowelled are checked; the share of words checked is reported |
| نَسْتَعِينُ / نَسْتَعِين, ٱلصَّمَدُ / الصمد | the reciter stops at the end of the ayah, so the final vowel is dropped (waqf). That's correct recitation | skip the last letter of an ayah's last word |
| لَّهُۥ / لَهُ | Uthmani writes the idgham shadda from the previous word on the first letter | skip shadda on a word's first letter |

The harakat check is now letter by letter. A missing sukun doesn't count. Real mistakes are still caught
(نُعْبُدُ for نَعْبُدُ, الْحَمْدَ for الْحَمْدُ, يُلِدْ for يَلِدْ are all flagged).

## How to run the evaluation

On a Mac (Terminal). Python 3.12 is used because sherpa-onnx may not support the newest Python yet.

```sh
brew install ffmpeg python@3.12
mkdir -p ~/niyat-asr
python3.12 -m venv ~/niyat-asr/venv
source ~/niyat-asr/venv/bin/activate          # again in every new Terminal window
pip install sherpa-onnx numpy datasets soundfile
cd ~/niyat-asr
for f in qurankarim-fastconformer-mixed.onnx qurankarim-fastconformer-q8.onnx tokens.txt; do
  curl -LO https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel/resolve/main/$f
done
cd ~/niyatapp
python3 scripts/eval_quran_asr.py inspect                 # which marks can the model write?
python3 scripts/eval_quran_asr.py audio --quick           # 2-minute smoke test
python3 scripts/eval_quran_asr.py audio --retasy          # full run, with amateurs
python3 scripts/eval_quran_asr.py audio --manifest mine.csv   # + your own recordings
python3 scripts/eval_quran_asr.py padtest                 # silence / faint-noise variants (seen clips)
python3 scripts/eval_quran_asr.py rescore                 # tables again from saved transcripts
```

Every transcript (including the noisy variants and the timings) goes to
`~/niyat-asr/eval/transcripts.jsonl`. `rescore` rebuilds every table from that file without the
model, so a scoring change never needs a new run. To hand results to a cloud session, commit that
file as `docs/research/asr-eval-transcripts.jsonl`.

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

## Text-only results (no model needed)

These answer one question: if the model heard everything perfectly but wrote it the way it
probably writes (everyday Imla'i spelling with tashkeel, like most Qur'an ASR training text), how
many words would our checker still flag? That is the floor of false alarms caused by the comparison
itself. "Heard" here is Tanzil's Imla'i edition of the same Hafs text
(`quran-imlaei.json`); "expected" is `quran-uthmani.json`. Neither file was modified.

| Comparison | Scope | Words | letters-WER | Harakat agreement | Ayat with zero flags |
|---|---|---|---|---|---|
| current `compare()` | whole Qur'an, 6,236 ayat | 77,433 | 2.72% | 98.06% | 63.9% |
| `compare_v2` | whole Qur'an | 77,433 | **0.00%** | **99.91%** | **98.9%** |
| current `compare()` | the 94 eval ayat | 695 | 0.86% | 96.81% | 76.6% |
| `compare_v2` | the 94 eval ayat | 695 | **0.00%** | **99.86%** | **98.9%** |

So with today's script, **about 1 in 3 perfectly recited ayat would be flagged** across the Qur'an
because of spelling alone. With the fixes, it is about 1 in 100.

What causes it, and what `compare_v2` changes:

| Cause (count in the whole Qur'an) | Example: expected (Uthmani) / heard (Imla'i) | Fix in `compare_v2` |
|---|---|---|
| Vocative يا written joined in Uthmani, separate in Imla'i (≈350) | يَٰٓأَيُّهَا / يَا أَيُّهَا · يَٰقَوْمِ / يَا قَوْمِ | Two heard words that join into an expected word count as that word |
| Uthmani rasm spellings (≈1,400) | ٱلصَّلَوٰةَ / الصَّلَاةَ · ٱلْحَيَوٰةِ / الْحَيَاةِ · ٱلَّيْلِ / اللَّيْلِ · شَيْـًٔا / شَيْئًا · إِسْرَٰٓءِيلَ / إِسْرَائِيلَ · إِبْرَٰهِـۧمَ / إِبْرَاهِيمَ | Accept the everyday spelling listed for that word in `recognition-forms.json` (the app already ships this file; the eval script now uses it) |
| Madda alef: Uthmani writes hamza + fatha + alef, Imla'i writes آ with no fatha (≈1,470 harakat flags, nearly all of them) | ءَامَنُوا۟ / آمَنُوا · ٱلْـَٔاخِرَةِ / الْآخِرَةِ · ٱلْقُرْءَانَ / الْقُرْآنَ | `harakat_v2` reads آ as ءَا |
| Marks on one letter in a different order (shadda + vowel) | | `harakat_v2` puts each letter's marks in a fixed order (shadda first) |

What is left after the fixes: 1 letter case (يَبْنَؤُمَّ / يَا ابْنَ أُمَّ, three words in Imla'i,
20:94) and about 70 harakat cases, nearly all where the two editions seat a hamza differently
(يَبْدَؤُا۟ / يَبْدَأُ, رَءَا / رَأَى, ٱلْمَلَؤُا۟ / الْمَلَأُ, ٱلَّٰٓـِٔى / اللَّائِي), plus a few genuine
reading features (مَجْر۪ىٰهَا with imala, ءَا۬عْجَمِىٌّ with tas-heel). The checker should skip
harakat on hamza letters and on these words.

### Marks in the Uthmani file, and how the comparison treats them

Counted over all of `quran-uthmani.json`:

| Mark | Count | Treated as |
|---|---|---|
| fatha / kasra / damma / sukun U+0652 / shadda / tanween | 3,741-123,396 each | harakat |
| **U+06E1 (Uthmani round sukun)** | **0** | This file uses the plain sukun U+0652 throughout, and so does the model (its vocabulary has no U+06E1). No normalisation needed. |
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

## Full run (Mac, `audio --retasy`, scored with `compare_v2`)

Data:
- **Seen**: 6 EveryAyah reciters × 94 ayat = 564 clips.
- **Unseen**: Islam Sobhi and Raad Al-Kurdi, whole-surah files of 1, 103, 108, 112, 113, 114 from
  mp3quran.net (12 files). The third unseen reciter's URL (Abdulrahman Mosad, server16) returned 404.
- **Amateurs**: the first 232 rows of `RetaSy/quranic_audio_dataset` (train split, streamed).
  82 were skipped because their ayah text didn't match any ayah; the other 150 were used. Mostly
  Al-Fatiha (61) and the last short surahs (114: 19, 112: 18, 109: 15, ...), median 3.5 s. RetaSy
  gives the surah as a name and the ayah as Uthmani text, so the ayah is found by its letters.
  Labels: 118 unlabelled, 14 `correct`, 12 `in_correct`, and 2 each of `not_related_quran`,
  `multiple_aya`, `not_match_aya`.

| Group | clips | words | letters-WER | word acc | harakat agree (where written) | words with harakat | sequence acc |
|---|---|---|---|---|---|---|---|
| Seen reciters, mixed | 564 | 4,170 | **8.27%** | 92.0% | 99.84% | 66% | 59.8% |
| Seen reciters, q8 | 564 | 4,170 | **6.64%** | 93.5% | 99.74% | 58% | 65.2% |
| Unseen reciters, mixed | 12 | 222 | **30.63%** | 78.8% | 100% | 89% | 16.7% |
| Amateurs, unlabelled, mixed | 118 | 514 | **55.84%** | 55.6% | 97.85% | 98% | 29.7% |
| Amateurs, labelled correct, mixed | 14 | 49 | 28.57% | 71.4% | 100% | 91% | 42.9% |
| Amateurs, labelled incorrect, mixed | 12 | 53 | 39.62% | 60.4% | 100% | 100% | 41.7% |

(The q8 row is from `padtest` with no padding. The 150-clip q8 subset in the main run gave 8.89%
against mixed's 8.27% on all clips; on the same 564 clips q8 is clearly better. "Sequence acc" =
clips with zero letter errors.)

Letters-WER by seen reciter (mixed): Abdullah Basfar 4.3%, Husary 4.7%, Alafasy 7.3%, Minshawy
8.6%, Ghamadi (40 kbps) 9.8%, Abdul Basit 14.8%. The slower and more melodic the recitation, the worse.

Amateur ayat are short (2-4 words), so one wrong word costs 25-50% of a clip. Results are uneven
rather than uniformly poor: many clips come back perfect (إِنَّ الْإِنْسَانَ لَفِي خُسْرٍ, إِنَّا أَعْطَيْنَاكَ
الْكَوْثَرَ), others are nonsense (113:4 وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ heard as بط نفاتعاب).

**Variants** (mixed model, seen clips):

| Variant | clips | letters-WER | sequence acc |
|---|---|---|---|
| clean, same 60 clips as the rows below | 60 | 8.72% | |
| white noise SNR 20 / 10 / 5 | 60 | 7.83% / 5.37% / 5.37% | 51.7% / 65.0% / 65.0% |
| babble (4 other reciters) SNR 10 / 5 | 60 | 13.20% / 31.10% | 48.3% / 23.3% |
| phone band 300-3400 Hz | 60 | 6.71% | 50.0% |
| tempo 0.9× / 1.15× | 60 | 10.74% / 6.71% | 51.7% / 63.3% |

**Silence and dither** (`padtest`, all 564 seen clips; silence added before and after):

| | mixed | q8 |
|---|---|---|
| as is | 8.27% | 6.64% |
| + 0.25 / 0.5 / 1 s silence | 9.57% / 11.70% / 17.39% | 7.34% / 10.53% / 16.67% |
| + faint noise SNR 40 / 30 | 8.87% / 7.48% | 6.93% / 7.05% |
| + SNR 30 noise and 0.5 s padding | 7.65% | 7.75% |

So the clip ends are not being cut off. Silence hurts, because `per_feature` normalisation
averages over the whole clip. **In the app, trim silence or cut live audio into speech segments
with a voice-activity detector (sherpa-onnx ships Silero VAD) before decoding.**

**Mistake detection** (mixed model, single-ayah clips):

| Group | clips | correct ayah with any letter flag | wrong verse caught (acc < 0.5) | right ayah below 0.5 (false alarm) | skipped word caught | other words flagged per skip test |
|---|---|---|---|---|---|---|
| Seen reciters | 540 | 41.1% | 97.0% | 2.4% | 97.9% of 474 | 0.73 |
| Amateurs, unlabelled | 88 | 69.3% | 93.2% | 40.9% | 97.5% of 79 | 2.42 |
| Amateurs, labelled correct | 14 | 57.1% | 100% | 28.6% | 100% of 14 | 1.00 |
| Amateurs, labelled incorrect | 11 | 54.5% | 81.8% | 18.2% | 100% of 10 | 1.10 |

Harakat false alarms on seen professional audio: **0.16%** of checked words with `compare_v2`
(4 of 2,546), against 49.7% with the original `compare()`.

**Speed** (Apple silicon MacBook Pro CPU, 40 clips, 506 s of audio):

| model | 1 thread RTF | 2 threads RTF |
|---|---|---|
| mixed | 0.033 | 0.020 |
| q8 | 0.018 | 0.010 |

### What the errors look like

Of the 345 letter errors on seen reciters (mixed): 159 heard only the start of the word, 49 doubled
a letter, 34 repeated a piece, 10 lost the start, 61 were other substitutions, 21 words were missed
and 11 were extra. The first word of an ayah fails 5.3% of the time, middle words 6.4%, the last word 19.3%.

| Kind | Expected | Heard | Where |
|---|---|---|---|
| ending dropped | يُنفِقُونَ · يُؤْمِنُونَ · ٱلْمُفْلِحُونَ | يُنْفِق · يُؤْمِن · الْمُفْلِح | Alafasy 2:3, 2:6, 2:5 (all ayah-final) |
| piece repeated | يُؤْمِنُونَ · ٱلْعَٰلَمِينَ | يُؤْمِنُونَُونَ · العالمينِينَ | Husary 2:6, Alafasy 1:2 |
| letter doubled | ٱلدِّينِ · قِيلَ · سَمْعِهِمْ | الددِّّينِ · قيللَ · سمععِهِ | Alafasy 1:4, 2:13, 2:7 |
| start lost | ذَهَبَ · هُمُ · وَإِذَا | هَبَ · مُ · ذَا | Alafasy 2:17, 2:13; Abdul Basit 2:14 |
| mangled | ٱلرَّحْمَٰنِ · لَذَهَبَ | َّح · لهَبَ | Alafasy 1:3, 2:20 |
| unseen, mangled | نَعْبُدُ · نَسْتَعِينُ · ٱلْمُسْتَقِيمَ | نَعُْدُ · نَسْعِين · الْمُسْتَقَ | Islam Sobhi 1:5-6 |
| amateur, ending lost | إِلَٰهِ · يَوْمِ · ٱلْمُسْتَقِيمَ | إِل · يَوِ · الْمُْتَقِيمَ | RetaSy 114:3, 1:4, 1:6 |
| amateur, nonsense | وَمِن شَرِّ ٱلنَّفَّٰثَٰتِ فِى ٱلْعُقَدِ | بط نفاتعاب | RetaSy 113:4 |
| amateur labelled correct | مَٰلِكِ يَوْمِ ٱلدِّينِ | مك ... عيد | RetaSy 1:4 |

Unseen whole-surah files also include things real users do that count as errors: Islam Sobhi repeats
ayat in 112, and both reciters open with a garbled isti'adha and Bismillah (stripped loosely
before scoring, which brought unseen letters-WER from 39.6% to 30.6%).

### Against the go/no-go limits

| Measure | Result | Band |
|---|---|---|
| Amateurs letters-WER | 56% (29% labelled correct) | **don't ship** |
| Unseen reciters letters-WER | 30.6% | **don't ship** |
| Correct ayat (amateur) with any false flag | 69% | **don't ship** |
| Wrong verse caught | 97% pros / 93% amateurs, but 41% false alarms on amateurs | ship for pros only |
| Harakat false alarms | 0.16% pros / 2% amateurs, on words it vowels | ship, as "harakat where heard" |
| RTF, 1 thread | 0.018-0.033 | ship |

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
| q8 vs mixed letters-WER | q8 within 0.5 points means ship q8 (2× faster, though a 166 MB download vs 83 MB) | | |

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
4. ~~List which marks the model can output.~~ Done (`inspect`, 1,025 tokens): it writes only
   fatha, kasra, damma, sukun **U+0652**, shadda, the three tanween and hamza ء, plus Arabic
   punctuation (، . ؟) and its special tokens `<unk>` / `<blk>`. **It never writes U+06E1** or any
   small Qur'anic sign (small high letters, small meem, U+06DF). So the Uthmani text's extra marks
   need no mapping, only ignoring, which the checker already does. The full `inspect` confirms it
   writes no dagger alef (U+0670) and no alef wasla (U+0671). Its letter forms are the everyday ones:
   أ إ آ ى ة ئ ؤ.
5. **Trim silence / use a VAD before decoding** (padding with silence raised letters-WER from 8.3%
   to 17%).

## Files

- `scripts/eval_quran_asr.py`: the evaluation. Modes: `text` (spelling floor, simulated mistakes),
  `audio` (the full run), `padtest` (silence and dither), `rescore` (every table from saved
  transcripts, no model needed), `inspect` (the model's output characters and metadata).
- `docs/research/asr-eval-transcripts.jsonl`: every transcript from the final Mac run (seen, unseen,
  amateurs, noise variants, timings). `python3 scripts/eval_quran_asr.py rescore docs/research/asr-eval-transcripts.jsonl`
- `docs/research/asr-eval-padtest.jsonl`: the silence and dither transcripts (`rescore` works on it too).
- `scripts/try_quran_asr.py`: unchanged; its `letters()`, `harakat()`, `words()`, `compare()` and `expected_words()` are reused.
