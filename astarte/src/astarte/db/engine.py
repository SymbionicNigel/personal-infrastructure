"""Async SQLAlchemy engine + session factory wired to the `app` schema."""

from __future__ import annotations

from functools import lru_cache
from typing import TYPE_CHECKING

from sqlalchemy.ext.asyncio import (
    async_sessionmaker,
    create_async_engine,
)

from astarte.config import load_settings

if TYPE_CHECKING:
    from collections.abc import AsyncIterator

    from sqlalchemy.ext.asyncio import AsyncEngine, AsyncSession

    from astarte.config import Settings


def build_engine(settings: Settings) -> AsyncEngine:
    """Construct the async engine pinned to the configured app schema.

    `search_path` defaults every unqualified identifier into the `app`
    schema so model definitions can stay schema-agnostic.
    """
    return create_async_engine(
        settings.database_url,
        echo=False,
        connect_args={"server_settings": {"search_path": settings.app_schema}},
    )


@lru_cache(maxsize=1)
def _engine() -> AsyncEngine:
    return build_engine(load_settings())


@lru_cache(maxsize=1)
def session_maker() -> async_sessionmaker[AsyncSession]:
    """Process-wide session factory; cached so we share one engine."""
    return async_sessionmaker(_engine(), expire_on_commit=False)


async def get_session() -> AsyncIterator[AsyncSession]:
    """FastAPI dependency that yields a transactional session."""
    async with session_maker()() as session:
        yield session
