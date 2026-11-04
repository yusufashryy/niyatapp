"""The recordings the app sends: 16 kHz mono 16-bit WAV, short."""

from __future__ import annotations

import io
import wave

import numpy as np

SAMPLE_RATE = 16000


class AudioError(ValueError):
    """A recording the server won't take (shown to the app as a 400)."""


def read_wav(data: bytes, max_seconds: float) -> np.ndarray:
    try:
        with wave.open(io.BytesIO(data)) as w:
            if w.getnchannels() != 1 or w.getsampwidth() != 2 or w.getframerate() != SAMPLE_RATE:
                raise AudioError("Audio must be 16 kHz mono 16-bit WAV.")
            frames = w.getnframes()
            if frames / SAMPLE_RATE > max_seconds:
                raise AudioError(f"Recordings are limited to {max_seconds:g} seconds.")
            samples = np.frombuffer(w.readframes(frames), dtype="<i2")
    except (wave.Error, EOFError) as e:
        raise AudioError("Not a WAV recording.") from e
    if len(samples) < SAMPLE_RATE // 4:
        raise AudioError("The recording is too short.")
    return samples.astype(np.float32) / 32768.0
