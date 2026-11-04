"""The recitation check service.

POST /v1/check?surah=2&ayah=5&word=0   body: 16 kHz mono WAV (audio/wav)
    The app sends what was recited since the last pause, with where the
    reciter was. The answer says which words it covered and how each one
    sounded. Recordings are checked in memory and never stored or logged.
POST /v1/find   body: 16 kHz mono WAV
    Where in the Qur'an the recording is, without a place to start from.
    Up to three places, best first (more than one when a phrase is shared).
GET /health
"""

from __future__ import annotations

import asyncio
import hmac
import logging
import time
import uuid
from collections import defaultdict, deque

from fastapi import FastAPI, HTTPException, Query, Request
from fastapi.concurrency import run_in_threadpool

from .audio import AudioError, read_wav
from .find import find
from .judge import judge
from .model import Hearing
from .quran import Place, is_valid
from .settings import Settings
from .span import find_span

log = logging.getLogger("niyat_check")

API_VERSION = 1
MAX_BODY = 2 * 1024 * 1024  # 45 s of 16 kHz 16-bit mono is 1.4 MB


class RateLimiter:
    def __init__(self, per_minute: int) -> None:
        self.per_minute = per_minute
        self.hits: dict[str, deque[float]] = defaultdict(deque)

    def allow(self, client: str) -> bool:
        now = time.monotonic()
        hits = self.hits[client]
        while hits and now - hits[0] > 60:
            hits.popleft()
        if len(hits) >= self.per_minute:
            return False
        hits.append(now)
        if len(self.hits) > 50_000:  # forget idle clients
            for key in [k for k, v in self.hits.items() if not v]:
                del self.hits[key]
        return True


def create_app(settings: Settings, hearing: Hearing) -> FastAPI:
    app = FastAPI(title="Niyat recitation check", docs_url=None, redoc_url=None, openapi_url=None)
    limiter = RateLimiter(settings.per_minute)
    slots = asyncio.Semaphore(settings.concurrency)

    def client_address(request: Request) -> str:
        if settings.trust_proxy:
            forwarded = request.headers.get("x-forwarded-for", "")
            if forwarded:
                return forwarded.split(",")[0].strip()
        return request.client.host if request.client else "?"

    def authorised(request: Request) -> bool:
        header = request.headers.get("authorization", "")
        key = header.removeprefix("Bearer ").strip()
        return bool(key) and any(hmac.compare_digest(key, k) for k in settings.app_keys)

    @app.get("/health")
    async def health() -> dict:
        return {"ok": True, "version": API_VERSION}

    @app.post("/v1/check")
    async def check(
        request: Request,
        surah: int = Query(ge=1, le=114),
        ayah: int = Query(ge=1, le=286),
        word: int = Query(ge=0, le=200),
    ) -> dict:
        if not authorised(request):
            raise HTTPException(401, "Unknown app key.")
        if not limiter.allow(client_address(request)):
            raise HTTPException(429, "Too many recordings at once. Wait a moment.")
        place = Place(surah, ayah, word)
        if not is_valid(place):
            raise HTTPException(400, "That place isn't in the Qur'an text.")
        body = await request.body()
        if len(body) > MAX_BODY:
            raise HTTPException(413, "The recording is too long.")
        try:
            wave = read_wav(body, settings.max_seconds)
        except AudioError as e:
            raise HTTPException(400, str(e)) from e
        del body

        request_id = uuid.uuid4().hex[:8]
        started = time.monotonic()
        try:
            await asyncio.wait_for(slots.acquire(), timeout=settings.queue_seconds)
        except TimeoutError as e:
            raise HTTPException(503, "The checker is busy. Try again in a moment.") from e
        try:
            heard, certainty = await run_in_threadpool(hearing.transcribe, wave)
            answer = await run_in_threadpool(_answer, heard, certainty, place, settings.max_words)
        finally:
            slots.release()
        flagged = " ".join(f"{w['ayah']}:{w['word']}={w['result']}" for w in answer["words"] if w["result"] != "correct")
        span = f"{answer['start']['ayah']}:{answer['start']['word']}-{answer['end']['ayah']}:{answer['end']['word']}" \
            if "start" in answer else "-"
        log.info("check %s %d:%d:%d %.1fs audio in %.2fs: %s %s %s", request_id, surah, ayah, word,
                 len(wave) / 16000, time.monotonic() - started, answer["status"], span, flagged)
        return answer

    async def _hear(request: Request) -> tuple[str, float, float]:
        """Checks the key, rate and audio, then transcribes it in a slot."""
        if not authorised(request):
            raise HTTPException(401, "Unknown app key.")
        if not limiter.allow(client_address(request)):
            raise HTTPException(429, "Too many recordings at once. Wait a moment.")
        body = await request.body()
        if len(body) > MAX_BODY:
            raise HTTPException(413, "The recording is too long.")
        try:
            wave = read_wav(body, settings.max_seconds)
        except AudioError as e:
            raise HTTPException(400, str(e)) from e
        try:
            await asyncio.wait_for(slots.acquire(), timeout=settings.queue_seconds)
        except TimeoutError as e:
            raise HTTPException(503, "The checker is busy. Try again in a moment.") from e
        try:
            heard, certainty = await run_in_threadpool(hearing.transcribe, wave)
        finally:
            slots.release()
        return heard, certainty, len(wave) / 16000

    @app.post("/v1/find")
    async def find_place(request: Request) -> dict:
        started = time.monotonic()
        heard, certainty, seconds = await _hear(request)
        places = await run_in_threadpool(find, heard)
        status = "found" if places else ("not_found" if heard else "silence")
        log.info("find %.1fs audio in %.2fs: %s %s", seconds, time.monotonic() - started, status,
                 " ".join(f"{f.start.surah}:{f.start.ayah}" for f in places))
        return {"version": API_VERSION, "status": status, "certainty": round(certainty, 3),
                "places": [{"start": _place(f.start), "end": _place(f.end)} for f in places]}

    return app


def _place(p: Place) -> dict:
    return {"surah": p.surah, "ayah": p.ayah, "word": p.word}


def _answer(heard: str, certainty: float, place: Place, max_words: int) -> dict:
    span = find_span(heard, place, max_words)
    if span is None:
        return {"version": API_VERSION, "status": "not_found" if heard else "silence",
                "certainty": round(certainty, 3), "words": []}
    words = judge(heard, certainty, span)
    end = words[-1].place if words else span.end
    return {
        "version": API_VERSION,
        "status": "checked",
        "certainty": round(certainty, 3),
        "start": _place(span.start),
        "end": _place(end),
        "words": [{**_place(w.place), "result": w.result, "notes": w.notes} for w in words],
    }
