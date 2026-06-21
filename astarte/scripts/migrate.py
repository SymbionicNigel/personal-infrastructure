#!/usr/bin/env python
"""Standalone migrate.

Same Alembic step as the FastAPI lifespan but without starting the
server, for CI / one-off use. Role provisioning is owned by the
postgres container's reconcile-roles.sql; this script does not touch
roles.
"""

from __future__ import annotations

import subprocess
import sys
from pathlib import Path


def _main() -> None:
    root = Path(__file__).resolve().parent.parent
    subprocess.run(
        [sys.executable, "-m", "alembic", "upgrade", "head"],
        cwd=str(root),
        check=True,
    )


if __name__ == "__main__":
    _main()
