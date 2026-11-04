# Niyat recitation check. CPU only: about 3 GB of memory, no graphics card.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PIP_NO_CACHE_DIR=1 HF_HOME=/models

# The CPU build of PyTorch is far smaller than the default (CUDA) one.
RUN pip install "torch>=2.7" --index-url https://download.pytorch.org/whl/cpu

WORKDIR /app
COPY pyproject.toml ./
COPY niyat_check ./niyat_check
RUN pip install .

# The model is downloaded while building, so the server starts quickly and
# never reaches out to Hugging Face while running.
RUN python -c "from huggingface_hub import snapshot_download; snapshot_download('obadx/muaalem-model-v3_2')"

RUN useradd --system --no-create-home app && chown -R app /models
USER app
ENV HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1
EXPOSE 8080
HEALTHCHECK --interval=30s --timeout=5s --start-period=120s \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/health', timeout=4)"
CMD ["python", "-m", "niyat_check"]
