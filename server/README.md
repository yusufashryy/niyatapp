# Niyat recitation check (server)

The app's optional **recitation check**. While someone recites, the app sends each stretch between pauses here. Quran Muaalem (a 660M-parameter model) writes down the sounds it hears. The server compares them with the text and answers word by word: as written, a letter different or missing, a word skipped, or a vowel or tajweed point to check.

- **No graphics card needed.** It needs about 3 GB of memory and takes about 0.15 s per second of audio on an M3 Pro, so a 10-second ayah takes about 1.5 s. A small VPS will be slower.
- **Recordings are checked in memory and then dropped.** Nothing is written to disk, and nothing is logged except timings and the place checked (surah:ayah:word). There are no access logs.
- **The app needs a key.** It sends the key with each request, and each address is rate-limited.

Measured results are in `docs/research/asr-eval-muaalem.md`.

## The API

```
POST /v1/check?surah=2&ayah=10&word=0
Authorization: Bearer <key>
Content-Type: audio/wav          16 kHz, mono, 16-bit, up to 45 s

200 {"version": 1, "status": "checked", "certainty": 0.96,
     "start": {"surah": 2, "ayah": 10, "word": 0}, "end": {...},
     "words": [{"surah": 2, "ayah": 10, "word": 3, "result": "mistake",
                "notes": [{"kind": "letter", "text": "Heard «د» where «ل» is written."}]}, ...]}
    status: checked, not_found (not the text around that place), silence
    result: correct, unsure, check (vowel/tajweed, amber), mistake, skipped
POST /v1/find                    same audio, no place: where in the Qur'an is this?
200 {"version": 1, "status": "found", "places": [{"start": {...}, "end": {...}}, ...]}
    up to three places, best first (more than one when a phrase is shared)
GET /health
```

The app uses `/v1/find` in two places:
- **The Qur'an list:** the "find by reciting" button opens the surah and ayah it names.
- **While reciting:** when `/v1/check` answers `not_found`, the app sends the same part to `/v1/find` and moves to the other surah, if there's only one place it could be.

On the saved professional transcripts, the right ayah came first 92% of the time.

Words are numbered from 0 within each ayah, the same way the app numbers the Uthmani text it shows. That was checked for all 6,236 ayat. The basmala is a header in the app, not words of the first ayah.

## Run it on your Mac (to try it with the simulator)

```bash
cd server
uv venv --python 3.12 && uv pip install -e . pytest httpx
NIYAT_APP_KEYS=local-test-key-0123456789abcdef NIYAT_HOST=127.0.0.1 .venv/bin/python -m niyat_check
```

The first start downloads the model (about 2.4 GB). Then, in `Config/Local.xcconfig`:

```
RECITATION_SERVER = 127.0.0.1:8080
RECITATION_KEY = local-test-key-0123456789abcdef
```

The app uses plain `http` only for `127.0.0.1`, `localhost` and `.local` addresses, and HTTPS for everything else.

Run the tests (no model needed) with `.venv/bin/python -m pytest`.

## Put it on a VPS (for TestFlight)

These steps are for any Ubuntu 24.04 server with at least 4 vCPU and 8 GB of memory, such as a Contabo Cloud VPS 10.

1. Create the server and note its IP address. Log in with `ssh root@<ip>`.
2. Install Docker and a firewall:
   ```bash
   curl -fsSL https://get.docker.com | sh
   ufw allow OpenSSH && ufw allow 80 && ufw allow 443 && ufw --force enable
   apt-get install -y unattended-upgrades
   ```
3. Copy this folder over from your Mac: `scp -r server root@<ip>:/opt/niyat-check`.
4. On the server:
   ```bash
   cd /opt/niyat-check
   cp .env.example .env
   openssl rand -base64 32      # copy the output
   nano .env                    # NIYAT_APP_KEYS=<that value>; NIYAT_DOMAIN=<ip-with-dashes>.sslip.io
   docker compose up -d --build # 10-15 minutes the first time (downloads PyTorch and the model)
   curl https://<ip-with-dashes>.sslip.io/health
   ```
   `sslip.io` turns the IP address into a name that gets a free HTTPS certificate, so you don't need to buy a domain. If you have a domain, point it at the IP and use that name instead.
5. In the app's `Config/Local.xcconfig` (never `Base.xcconfig`):
   ```
   RECITATION_SERVER = <ip-with-dashes>.sslip.io
   RECITATION_KEY = <the same key>
   ```
   Then archive and upload to TestFlight as usual.

- **Updating:** copy the folder again, then run `docker compose up -d --build`.
- **Logs:** `docker compose logs -f check`.
- **Changing the key:** put the old and new keys in `NIYAT_APP_KEYS`, separated by a comma. Ship the new key in the app, then remove the old one once nobody uses that build any more.

The key ships inside the app, so it isn't a real secret: someone determined could extract it. It keeps out casual traffic, and the rate limit keeps out the rest. If the server gets abused, replace the key and lower `NIYAT_PER_MINUTE`.

## Licences

- **Quran Muaalem** (`quran-muaalem` package and `obadx/muaalem-model-v3_2`): Quran Muaalem License 1.0, which is Apache 2.0 plus conditions. The app shows the required AI notice before first use, keeps it available in settings, has no ads, and offers the check free.
- **quran-transcript:** the Qur'an text and phonetic script used for the comparison.
