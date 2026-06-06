"""FastAPI application factory and route handlers."""

from fastapi import FastAPI

app = FastAPI(title="astarte")


@app.get("/health")
def health() -> dict[str, str]:
    """Return service liveness."""
    return {"status": "ok"}
