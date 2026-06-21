"""Runtime configuration loaded from environment variables.

Astarte connects as the `astarte` role and only the `astarte` role.
Role creation and password sync — including astarte's own — happen in
the postgres container's reconcile-roles.sql; this process never
needs superuser credentials.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from urllib.parse import quote

# Schema astarte owns. Convention: each service that owns a schema names
# it after itself, so ownership is obvious from the schema name.
DEFAULT_APP_SCHEMA = "astarte"


def _require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        msg = f"missing required environment variable: {name}"
        raise RuntimeError(msg)
    return value


def _dsn(*, user: str, password: str, host: str, port: str, db: str) -> str:
    return f"postgresql+asyncpg://{quote(user)}:{quote(password)}@{host}:{port}/{quote(db)}"


@dataclass(frozen=True, slots=True)
class Settings:
    """Process-wide settings."""

    host: str
    port: str
    db: str
    app_schema: str

    astarte_user: str
    astarte_password: str

    @property
    def database_url(self) -> str:
        """Runtime DSN (astarte role)."""
        return _dsn(
            user=self.astarte_user,
            password=self.astarte_password,
            host=self.host,
            port=self.port,
            db=self.db,
        )


def load_settings() -> Settings:
    """Build Settings from the environment. Fails fast on missing values."""
    return Settings(
        host=os.environ.get("POSTGRES_HOST", "postgres"),
        port=os.environ.get("POSTGRES_PORT", "5432"),
        db=_require("POSTGRES_DB"),
        app_schema=os.environ.get("ASTARTE_APP_SCHEMA", DEFAULT_APP_SCHEMA),
        astarte_user=_require("POSTGRES_ASTARTE_USER"),
        astarte_password=_require("POSTGRES_ASTARTE_PASSWORD"),
    )
