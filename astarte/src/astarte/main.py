"""FastAPI application factory and route handlers."""

from __future__ import annotations

import asyncio
import logging
import sys
from contextlib import asynccontextmanager
from pathlib import Path
from typing import TYPE_CHECKING, Annotated

from fastapi import Depends, FastAPI
from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncSession,  # noqa: TC002  (FastAPI Depends needs runtime resolution)
)

from astarte.db import get_session

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

log = logging.getLogger(__name__)

_ASTARTE_ROOT = Path(__file__).resolve().parent.parent.parent


async def _alembic_upgrade_head() -> None:
    """Apply migrations up to head, in a subprocess.

    Alembic's async env.py calls `asyncio.run`, which doesn't compose with
    the running lifespan loop. A subprocess sidesteps that and surfaces a
    clean exit code. Alembic env.py reads its connection settings from
    astarte.config.load_settings(), inheriting our process env.
    """
    proc = await asyncio.create_subprocess_exec(
        sys.executable,
        "-m",
        "alembic",
        "upgrade",
        "head",
        cwd=str(_ASTARTE_ROOT),
    )
    rc = await proc.wait()
    if rc != 0:
        msg = f"alembic upgrade exited with code {rc}"
        raise RuntimeError(msg)


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    """Apply migrations against the astarte-owned schema, then serve."""
    log.info("astarte: applying Alembic migrations")
    await _alembic_upgrade_head()
    log.info("astarte: ready")
    yield


app = FastAPI(title="astarte", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    """Return service liveness. Cheap, no DB hit."""
    return {"status": "ok"}


@app.get("/health/db")
async def health_db(session: Annotated[AsyncSession, Depends(get_session)]) -> dict[str, str]:
    """Return DB readiness. A failed query surfaces as a 500 to the caller."""
    await session.execute(text("SELECT 1"))
    return {"status": "ok"}
