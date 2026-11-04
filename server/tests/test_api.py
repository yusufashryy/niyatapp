"""The HTTP layer with a stand-in for the model."""

import io
import wave

import numpy as np
from fastapi.testclient import TestClient

from niyat_check.app import create_app
from niyat_check.audio import AudioError, read_wav
from niyat_check.quran import segment
from niyat_check.settings import Settings

KEY = "test-key-0123456789abcdefghij"


class FakeHearing:
    def __init__(self, heard: str) -> None:
        self.heard = heard

    def transcribe(self, wave):
        return self.heard, 0.95


def wav(seconds: float, rate: int = 16000, channels: int = 1) -> bytes:
    out = io.BytesIO()
    with wave.open(out, "wb") as w:
        w.setnchannels(channels)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(np.zeros(int(seconds * rate) * channels, dtype="<i2").tobytes())
    return out.getvalue()


def client(heard: str = "", per_minute: int = 30) -> TestClient:
    settings = Settings(app_keys=frozenset({KEY}), per_minute=per_minute)
    return TestClient(create_app(settings, FakeHearing(heard)))


def post(c: TestClient, body: bytes, key: str = KEY, query: str = "surah=1&ayah=4&word=0"):
    return c.post(f"/v1/check?{query}", content=body,
                  headers={"Authorization": f"Bearer {key}", "Content-Type": "audio/wav"})


def test_health():
    assert client().get("/health").json()["ok"] is True


def test_needs_the_app_key():
    assert post(client(), wav(1), key="wrong").status_code == 401


def test_checks_a_recording():
    heard = segment(1, 4, 0, 2).phonemes
    answer = post(client(heard), wav(2)).json()
    assert answer["status"] == "checked"
    assert answer["end"] == {"surah": 1, "ayah": 4, "word": 2}
    assert [w["result"] for w in answer["words"]] == ["correct"] * 3


def test_nothing_heard_is_silence():
    assert post(client(""), wav(2)).json()["status"] == "silence"


def test_rejects_other_audio_formats():
    assert post(client(), wav(2, rate=44100)).status_code == 400
    assert post(client(), b"not audio").status_code == 400


def test_rejects_places_outside_the_text():
    assert post(client(), wav(1), query="surah=1&ayah=8&word=0").status_code == 400
    assert post(client(), wav(1), query="surah=115&ayah=1&word=0").status_code == 422


def test_rate_limited_per_address():
    c = client(segment(1, 4, 0, 2).phonemes, per_minute=2)
    assert [post(c, wav(1)).status_code for _ in range(3)] == [200, 200, 429]


def test_wav_limits():
    for data, ok in [(wav(1), True), (wav(0.1), False), (wav(50), False), (wav(1, channels=2), False)]:
        try:
            read_wav(data, 45)
            assert ok
        except AudioError:
            assert not ok


def test_refuses_to_start_without_a_key():
    try:
        Settings(app_keys=frozenset()).validate()
    except SystemExit:
        return
    raise AssertionError("expected SystemExit")


def test_finds_where_a_recording_is():
    from niyat_check.quran import ayah_words, segment
    words = ayah_words(2, 255)
    heard = segment(2, 255, 0, len(words) - 1).phonemes
    answer = client(heard).post("/v1/find", content=wav(2),
                                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "audio/wav"}).json()
    assert answer["status"] == "found"
    assert answer["places"][0]["start"] == {"surah": 2, "ayah": 255, "word": 0}


def test_find_needs_enough_sound():
    answer = client("ءَ").post("/v1/find", content=wav(1),
                                headers={"Authorization": f"Bearer {KEY}", "Content-Type": "audio/wav"}).json()
    assert answer["status"] == "not_found"
    assert answer["places"] == []


def test_find_needs_the_app_key():
    assert client().post("/v1/find", content=wav(1), headers={"Authorization": "Bearer wrong"}).status_code == 401
