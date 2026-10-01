# Recitation checking: roadmap

Goal: follow a reciter word by word and flag real mistakes, with few false
alarms. Keep the layers separate:

1. **Speech recognition**: what was said.
2. **Alignment**: where the reciter is in the mushaf.
3. **Mistake detection**: did it differ from what should have been said.
4. **Tajwid** (later): was each sound pronounced correctly.

## What "95%" means

Measure three things separately, on recordings labelled by hand:

| Measure | Target |
|---|---|
| Tracking (highlight on the right word) | 98-99% |
| False alarms (correct word flagged) | under 2% |
| Mistake recall (real mistakes caught) | 85-95% |

Most transcript-vs-text differences in real recordings are not mistakes:
repetitions after a breath, instant self-corrections, opening formulas and
spelling variants (Al Mdfaa et al., *What Counts as a Mistake?*,
arXiv:2609.12085; a plain diff scored F1 0.53). Labelling those is worth more
than a better model.

## Candidate model

[TheGreatQuran/QuranKarim-SpeechToText-onnxModel](https://huggingface.co/TheGreatQuran/QuranKarim-SpeechToText-onnxModel):
NVIDIA FastConformer CTC fine-tuned on tarteel-ai/everyayah, output with
harakat, CC-BY-4.0 (credit in About). 87 MB mixed 4/8-bit ONNX; runs with
sherpa-onnx (Swift API on iOS). Whole-clip decoding, so live use means
re-running on the last few seconds every ~0.5 s.

Its claimed 0.14% WER is unverified and was measured on professional
reciters: test it on ordinary voices first with `scripts/try_quran_asr.py`.
Models trained on EveryAyah reach ~23% WER on crowd-sourced recitation
(arXiv:2606.19747).

## Phases (all $0: on-device, free tools)

0. **No model**: voice-activity detection, the microphone's voice-processing
   mode, a repair window (judge a word only after two more), labels for
   repetition / repair / opening formula / spelling variant, and a labelled
   test set with a scoring harness.
1. **Model as an optional download** (GitHub Release), Apple speech as the
   fallback. Word tracking on its output.
2. **Constrained alignment**: CTC forced alignment against the next ~20
   expected words with a "something else" token; per-word confidence from
   the expected word's score against the free transcription. Harakat check
   from the model's tashkeel.
3. **Fine-tune for ordinary voices** if needed: EveryAyah + Tarteel v1 +
   noise and room augmentation, test reciters and verses held out (Kaggle's
   free GPU hours).
4. **Tajwid**: phone-level checking against an expected pronunciation, e.g.
   Quran Muaalem (arXiv:2509.00094) with the Quran-Lab tajweed phonetics.
   Quran-Lab's data is under a no-profit licence: ask them in writing whether
   a free app with optional tips may use it before relying on it.

## Privacy

Testing on real users' recitations means recording them, which the app and
privacy policy currently rule out. Any collection needs its own opt-in and a
policy update.
