# Evaluating Quran Muaalem (server-side recitation check)

Date: 3 November 2026, on a Mac (M3 Pro, CPU only). The recordings are the same 726 used for the QuranKarim report (`asr-eval-qurankarim.md` on the `research/asr-eval` branch):
- **Professional:** 564 single-ayah clips by 6 professional reciters on EveryAyah.
- **Other reciters:** 12 whole-surah files by 3 reciters the model probably hasn't heard.
- **Learners:** 150 RetaSy clips by non-Arabic speakers.

**Model:** [obadx/muaalem-model-v3_2](https://huggingface.co/obadx/muaalem-model-v3_2). It's a Wav2Vec2-BERT model of about 660M parameters, multi-level CTC, run through the `quran-muaalem` 0.3.0 package. It writes down the *sounds* recited, in quran-transcript's phonetic script, without looking at the expected text, so the same transcript can be scored against any reference.

## Verdict

**Muaalem is good enough for the optional "check after each pause".** It hears professional recitation almost exactly, and its flags on learners are mostly real slips. Once the server allows what correct recitation may do, false alarms on professional reciters are rare.

## Raw model, against one reference per ayah

| | Professional (564) | Learners labelled correct (14) | Learners, unlabelled (118) |
|---|---|---|---|
| Phoneme error rate, median | **0.9%** | 23% | 33% |
| Right ayah picked from the whole surah | 97.9% | 100% | 81% |
| Skipped word caught (offline test) | 100% (540) | 100% | 100% |

- **Other reciters:** they score 24% at first, but almost all of that is the reference. It joined ayat that they stop between, and missed the isti'adha and basmala they start with. The transcripts themselves are nearly perfect.
- **Learners labelled "correct":** they still get flagged. Their errors are real, such as «مَادِك» for «مَالِكِ» and a dropped «قُ» in «قُل». RetaSy's labels mean "the right ayah", not "no mistakes".

## With the server's rules (`server/niyat_check`)

The server accepts:
- stopping on any word, and the next word starting after the stop;
- going back to repeat;
- the madd lengths Hafs allows;
- sounds at the edges of a part.

Vowels and tajweed are shown amber, and red is kept for letters and skipped words. Scored with `eval_server.py` on the saved transcripts:

| | Clips with any red mark | Clips with an amber mark | Words marked red |
|---|---|---|---|
| Professional (564) | **9%** | 7% | **1.3%** |
| Other reciters, whole surahs (12) | 42% | 17% | 2.3% |
| Learners labelled correct (14) | 86% | 50% | 44% |
| Learners, unlabelled (118) | 62% | 32% | 44% |

What's left on professional reciters:
- **Missing sounds (33):** mostly the 40 kbps Ghamadi files.
- **Letters (18):** for example «ضُكم» for «بُكمٌ».
- **Extra sounds (9).**

## Speed

| Setup | Time per second of audio |
|---|---|
| float32, all 11 threads | 0.15–0.16 s |
| float32, 4 threads | 0.14 s |
| bfloat16 (the package default) | about 1.1 s, so float32 on CPU |

- **Examples:** a 10-second ayah takes about 1.5 s, and a 53-second surah took 21 s.
- **Memory:** about 3 GB.
- **Round trip:** a 13.5 s recording to the local server and back took 1.8 s.

A 4-vCPU VPS is expected to be 2–3× slower. That's an estimate, not measured.

## Not tested yet

- Real learners reciting into an iPhone; the team's own voices.
- The live app on a device. On the simulator, the audio went through the app's recorder and client to the server and came back correct, but the simulator's microphone isn't a fair test.
- A VPS's speed.
