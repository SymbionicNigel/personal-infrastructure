"""baseline (empty).

Revision ID: 0001_baseline
Revises:
Create Date: 2026-06-18

Empty baseline. The `astarte` schema and role are created by the
postgres container's reconcile-roles.sql on every start, so this
migration only marks the starting point. Subsequent migrations add
tables inside the `astarte` schema.
"""

from __future__ import annotations

revision: str = "0001_baseline"
down_revision: str | None = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    pass


def downgrade() -> None:
    pass
