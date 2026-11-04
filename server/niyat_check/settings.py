"""Server settings, from environment variables (see .env.example)."""

from __future__ import annotations

import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    return int(os.environ.get(name, default))


def _float(name: str, default: float) -> float:
    return float(os.environ.get(name, default))


@dataclass(frozen=True)
class Settings:
    # Keys the app sends as "Authorization: Bearer <key>". Several may be set
    # (comma-separated) so a key can be replaced without breaking older builds.
    app_keys: frozenset[str] = field(default_factory=lambda: frozenset(
        k.strip() for k in os.environ.get("NIYAT_APP_KEYS", "").split(",") if k.strip()))
    model: str = os.environ.get("NIYAT_MODEL", "obadx/muaalem-model-v3_2")
    threads: int = _int("NIYAT_THREADS", 0)
    max_seconds: float = _float("NIYAT_MAX_SECONDS", 45)
    max_words: int = _int("NIYAT_MAX_WORDS", 40)
    # Recordings checked at once; more wait in line, up to queue_seconds.
    concurrency: int = _int("NIYAT_CONCURRENCY", 1)
    queue_seconds: float = _float("NIYAT_QUEUE_SECONDS", 20)
    # Per address: a reciter pausing every few seconds sends about 10 a minute.
    per_minute: int = _int("NIYAT_PER_MINUTE", 30)
    # Behind Caddy: take the client address from X-Forwarded-For.
    trust_proxy: bool = os.environ.get("NIYAT_TRUST_PROXY", "0") == "1"

    def validate(self) -> None:
        if not self.app_keys:
            raise SystemExit("Set NIYAT_APP_KEYS (see .env.example): the server refuses to run without a key.")
        if any(len(k) < 24 for k in self.app_keys):
            raise SystemExit("Each key in NIYAT_APP_KEYS must be at least 24 characters.")
