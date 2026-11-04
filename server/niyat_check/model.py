"""Quran Muaalem: what sounds were recited, independent of the text.

Only the phoneme level is decoded; the sifat levels aren't used yet. On a
CPU float32 is several times faster than the bfloat16 the model trained in.
"""

from __future__ import annotations

from typing import Protocol

import numpy as np


class Hearing(Protocol):
    def transcribe(self, wave: np.ndarray) -> tuple[str, float]:
        """Phonemes heard, and the model's average certainty (0...1)."""
        ...


class MuaalemHearing:
    def __init__(self, model_name: str, threads: int = 0) -> None:
        import torch
        from quran_muaalem import Muaalem
        from quran_muaalem.decode import phonemes_level_greedy_decode

        if threads:
            torch.set_num_threads(threads)
        self._torch = torch
        self._decode = phonemes_level_greedy_decode
        self._muaalem = Muaalem(model_name_or_path=model_name, device="cpu", dtype=torch.float32)

    def transcribe(self, wave: np.ndarray) -> tuple[str, float]:
        m = self._muaalem
        with self._torch.no_grad():
            features = m.processor([wave], sampling_rate=16000, return_tensors="pt")
            features = {k: v.to("cpu", dtype=self._torch.float32) for k, v in features.items()}
            logits = m.model(**features, return_dict=False)[0]["phonemes"]
            probs = self._torch.nn.functional.softmax(logits, dim=-1).to(self._torch.float32)
        unit = self._decode(probs, m.multi_level_tokenizer.id_to_vocab["phonemes"])[0]
        certainty = float(np.mean([float(p) for p in unit.probs])) if len(unit.probs) else 0.0
        return unit.text, certainty
