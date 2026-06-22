"""SQLModel table registry. Import this module so Alembic sees every model."""

from sqlmodel import SQLModel

metadata = SQLModel.metadata

# Add table classes below. Each `class X(SQLModel, table=True): ...` self-
# registers into `metadata` at import time, so Alembic autogenerate picks
# them up from a single import of this module.
