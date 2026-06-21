# astarte

Public-facing FastAPI backend. Reached at `astarte.<HOSTNAME_TLD>` in
production, `http://localhost:8000` locally.

## Local development

Generate the lockfile once (needed by the dev image's `uv sync --frozen`):

```bash
cd astarte && uv sync && cd ..
```

Then start the stack from the `compose/` directory:

```bash
cd compose
docker compose up astarte
# in another shell:
curl http://localhost:8000/health
```

The local override targets the Dockerfile's `dev` stage, which runs
`uvicorn --reload` over a bind-mounted `astarte/src`. Edits to source
files trigger an in-container reload — no rebuild needed.

Rebuild only when dependencies change:

```bash
docker compose up --build astarte
```

## Tests

Run with uv (faster than rebuilding the container for each test loop):

```bash
uv run pytest
```

## Code quality

```bash
uv run ruff check         # lint
uv run ruff format        # format in place
uv run pip-licenses       # preview the CI license audit
```

CI runs the same three commands plus `pytest` on every PR touching
`astarte/**`. Lint or license failures stop the pipeline before the
image is built.

## Generated artifacts

`openapi.json` is committed and consumed by iris (see `iris/README.md`). It is
emitted from the running FastAPI app's schema, so it changes whenever a
Pydantic model or route signature does. Regenerate after such changes:

```bash
uv run python scripts/emit_openapi.py openapi.json
```

CI's `typegen` job runs the same command and fails on diff.

## Container (standalone)

To build the production image without the rest of the stack:

```bash
docker build -t astarte:local astarte/
docker run --rm -p 8000:8000 astarte:local
```

`docker build` with no `--target` builds the `runtime` stage by default.
That image is multi-stage: a `uv` builder stage produces a wheel; a slim
`python:3.13-slim` runtime stage installs that wheel as a non-root user.
Source code and build tooling do not ship in the published image.

## Production deploy

The image is built and pushed by `.github/workflows/astarte.yml` on every
push to `master` that touches `astarte/**`. The workflow then runs
`terraform apply` in `linode/environments/dokploy/` with the new git SHA
as `TF_VAR_ASTARTE_IMAGE_TAG`, which updates the compose stack and
triggers Dokploy to pull the new image.
