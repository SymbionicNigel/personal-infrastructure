# Three targets:
#   dev      — full venv + `uvicorn --reload`. Source bind-mounted at runtime.
#   builder  — produces the wheel for the runtime stage. (intermediate)
#   runtime  — slim production image. No uv, no source. (default)
#
# `docker build` (no --target) gives the runtime image. The local compose
# override sets `target: dev` for hot-reload dev.

# Common uv base. Aliasing here so dev and builder both start from the
# same image without inheriting each other's work.
FROM ghcr.io/astral-sh/uv:python3.14-bookworm-slim AS uv-base

# Dev target: install deps + the package (editable) into a venv, then run
# uvicorn with --reload watching /app/src. The compose override
# bind-mounts the host source into /app/src so edits propagate.
FROM uv-base AS dev
WORKDIR /app
ENV UV_LINK_MODE=copy
COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/
RUN uv sync --frozen
EXPOSE 8000
CMD ["uv", "run", "uvicorn", "astarte.main:app", \
     "--host", "0.0.0.0", "--port", "8000", \
     "--reload", "--reload-dir", "/app/src"]

# Builder target: produce the app wheel plus a hashed requirements export from
# uv.lock. Both travel forward; no source, uv, or build tooling ships in runtime.
FROM uv-base AS builder
WORKDIR /build
ENV UV_LINK_MODE=copy \
    UV_COMPILE_BYTECODE=1
COPY pyproject.toml uv.lock README.md ./
COPY src/ ./src/
RUN uv build --wheel --out-dir /wheels \
 && uv export --frozen --no-dev --no-emit-project --output-file /wheels/requirements.txt

# Runtime stage: slim python image with the wheel installed. No uv.
FROM python:3.14-slim AS runtime
WORKDIR /app
COPY --from=builder /wheels/ /tmp/wheels/
# Locked+hashed deps first, then the app wheel --no-deps so pip never
# re-resolves the pyproject ranges against PyPI.
RUN pip install --no-cache-dir -r /tmp/wheels/requirements.txt \
 && pip install --no-cache-dir --no-deps /tmp/wheels/*.whl \
 && rm -rf /tmp/wheels

# Non-root runtime. UID 1000 is conventional and plays well with
# bind-mounted volumes from a typical dev host.
RUN useradd --create-home --uid 1000 app && chown app:app /app
USER app

# uvicorn reads WEB_CONCURRENCY natively. Override at runtime with
# `-e WEB_CONCURRENCY=N`. Default of 2 fits a single small Linode;
# raise it on larger hosts.
ENV WEB_CONCURRENCY=2

# Container-level healthcheck. Uses python stdlib (no curl needed) so
# Docker / Dokploy's container status column reflects health. The
# route-level healthcheck on the Traefik service (compose labels) is
# the source of truth for routing decisions; this one is for visibility.
#
# Python's urlopen timeout (3s) bounds the request before Docker's
# --timeout=5s would kill the process, so a stuck check exits cleanly.
HEALTHCHECK --interval=30s --timeout=5s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health', timeout=3)"

EXPOSE 8000
CMD ["uvicorn", "astarte.main:app", "--host", "0.0.0.0", "--port", "8000"]
