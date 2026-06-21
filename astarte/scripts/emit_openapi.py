#!/usr/bin/env python
"""Emit astarte's OpenAPI schema as JSON.

Writes to the path passed as the first arg (defaults to ./openapi.json).
The output is stable and deterministic so CI can diff a regenerated file
against the committed one.
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from astarte.main import app


def main() -> None:
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "openapi.json")
    schema = app.openapi()
    out.write_text(json.dumps(schema, indent=2, sort_keys=True) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
