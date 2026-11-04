"""python -m niyat_check: loads the model once, then serves on port 8080."""

import logging
import os

import uvicorn

from .app import create_app
from .model import MuaalemHearing
from .settings import Settings


def main() -> None:
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
    settings = Settings()
    settings.validate()
    hearing = MuaalemHearing(settings.model, settings.threads)
    app = create_app(settings, hearing)
    uvicorn.run(app, host=os.environ.get("NIYAT_HOST", "0.0.0.0"), port=int(os.environ.get("NIYAT_PORT", 8080)),
                proxy_headers=settings.trust_proxy, forwarded_allow_ips="*" if settings.trust_proxy else None,
                access_log=False)


if __name__ == "__main__":
    main()
