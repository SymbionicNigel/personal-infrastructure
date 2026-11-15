FROM ghcr.io/astral-sh/uv:0.13.8@sha256:5cc1805e2426484abca4ad46ea783bab281fdb225fd82d8ce6d66a81254bac85 AS uv
FROM python:3.14.9-slim-trixie@sha256:35caba83af2fe6da9a5d922f9b0156f21d1246a48278c58a08bd253303ba42e8 AS python-base
RUN apt-get update \
 && apt-get upgrade -y --no-install-recommends \
 && rm -rf /var/lib/apt/lists/*

FROM python-base AS uv-base
COPY --from=uv /uv /uvx /bin/
ENV UV_LINK_MODE=copy

FROM uv-base AS dev
WORKDIR /app
COPY pyproject.toml uv.lock README.md alembic.ini ./
COPY src/ ./src/
COPY alembic/ ./alembic/
RUN uv sync --frozen
EXPOSE 8000
CMD ["uv", "run", "uvicorn", "astarte.main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--reload", "--reload-dir", "/app/src"]

FROM uv-base AS builder
WORKDIR /build
ENV UV_COMPILE_BYTECODE=1
COPY pyproject.toml uv.lock README.md alembic.ini ./
COPY src/ ./src/
COPY alembic/ ./alembic/
RUN uv build --wheel --out-dir /wheels \
 && uv export --frozen --no-dev --no-emit-project --output-file /wheels/requirements.txt

FROM python-base AS runtime
WORKDIR /app
COPY --from=builder /wheels/ /tmp/wheels/
RUN pip install --no-cache-dir --require-hashes -r /tmp/wheels/requirements.txt \
 && pip install --no-cache-dir --no-deps /tmp/wheels/*.whl \
 && pip uninstall --yes pip \
 && rm -rf /tmp/wheels
COPY --from=builder /build/alembic.ini ./
COPY --from=builder /build/alembic/ ./alembic/
RUN useradd --create-home --uid 1000 app && chown app:app /app
USER app
ENV WEB_CONCURRENCY=2
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3)"
EXPOSE 8000
CMD ["uvicorn", "astarte.main:app", "--host", "0.0.0.0", "--port", "8000"]
