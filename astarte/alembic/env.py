"""Alembic env.py.

Configured for:
  * async engine (asyncpg)
  * the astarte schema (autogenerate restricts to it; alembic_version lives there)
  * connection settings sourced from astarte.config.load_settings(), the
    single env-reading chokepoint for astarte

Run with `alembic upgrade head` from the astarte/ directory.
"""

from __future__ import annotations

import asyncio
from logging.config import fileConfig
from typing import TYPE_CHECKING

from sqlalchemy import pool
from sqlalchemy.ext.asyncio import async_engine_from_config

if TYPE_CHECKING:
    from sqlalchemy.engine import Connection

from alembic import context
from astarte.config import load_settings
from astarte.db.models import metadata as target_metadata

config = context.config

if config.config_file_name is not None:
    fileConfig(config.config_file_name)

_SETTINGS = load_settings()
APP_SCHEMA = _SETTINGS.app_schema


def _include_object(obj, name, type_, reflected, compare_to):  # noqa: ARG001
    """Restrict autogenerate to astarte's owned schema. Other schemas
    (per-service tenants) are owned by their own roles and migrated separately.
    """
    return not (type_ == "table" and obj.schema is not None and obj.schema != APP_SCHEMA)


def run_migrations_offline() -> None:
    context.configure(
        url=_SETTINGS.database_url,
        target_metadata=target_metadata,
        literal_binds=True,
        dialect_opts={"paramstyle": "named"},
        version_table_schema=APP_SCHEMA,
        include_schemas=True,
        include_object=_include_object,
    )
    with context.begin_transaction():
        context.run_migrations()


def _do_run_migrations(connection: Connection) -> None:
    context.configure(
        connection=connection,
        target_metadata=target_metadata,
        version_table_schema=APP_SCHEMA,
        include_schemas=True,
        include_object=_include_object,
    )
    with context.begin_transaction():
        context.run_migrations()


async def _run_async() -> None:
    section = config.get_section(config.config_ini_section) or {}
    section["sqlalchemy.url"] = _SETTINGS.database_url
    engine = async_engine_from_config(section, prefix="sqlalchemy.", poolclass=pool.NullPool)
    async with engine.connect() as connection:
        await connection.run_sync(_do_run_migrations)
    await engine.dispose()


def run_migrations_online() -> None:
    asyncio.run(_run_async())


if context.is_offline_mode():
    run_migrations_offline()
else:
    run_migrations_online()
