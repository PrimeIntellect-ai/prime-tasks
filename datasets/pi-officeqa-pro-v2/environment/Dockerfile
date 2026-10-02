FROM python:3.12-slim-bookworm
COPY --from=ghcr.io/astral-sh/uv:0.12.17 /uv /usr/local/bin/uv
RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl ripgrep poppler-utils tesseract-ocr \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /opt/officeqa
COPY pyproject.toml uv.lock ./
RUN uv sync --locked --no-dev --no-cache
ENV PATH="/opt/officeqa/.venv/bin:${PATH}"
ADD corpus.tar.gz /workspace/
WORKDIR /workspace
CMD ["sleep", "infinity"]
