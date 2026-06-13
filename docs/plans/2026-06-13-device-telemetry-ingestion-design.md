# Design: Device Telemetry Ingestion (sub-project 1)

Date: 2026-06-13
Status: Approved design, pre-implementation

## Context

The goal is a personal-data platform that warehouses, dashboards, automates
on, and analyzes data from the maintainer's own life — pulling from whatever
sources are technically reachable. The reachable landscape was surveyed and
the work decomposed into sub-projects, each with its own spec → plan → build
cycle:

1. **Device telemetry ingestion** (this doc) — PrusaLink 3D printer +
   Masterbuilt Gravity smoker.
2. Health & fitness — Garmin, Android Health Connect.
3. Finance & productivity — YNAB API, Google Calendar/Gmail, Obsidian.
4. Dashboard surfaces + automation/alerts in iris.

This sub-project builds the **ingestion core** inside the existing `astarte`
FastAPI service and proves it end-to-end with two physically-on-hand devices
that share a data shape: temperature + progress over time, with discrete
completion/threshold events.

### Decisions and rejected alternatives

- **Ingestion lives inside `astarte`, not a new service.** astarte is already
  the FastAPI backend;
- **PrusaLink over OctoPrint / Prusa Connect.** PrusaLink runs on the printer
  itself (local REST API, API-key auth), needs no extra hardware, and is
  poll-only. The Masterbuilt is also poll-only, so both first connectors share
  one shape — poll on an interval, derive events from state transitions. This
  makes a webhook receiver *optional* rather than core. OctoPrint (Pi +
  webhooks) and Prusa Connect (cloud) are left as future options behind the
  same connector abstraction.
- **TimescaleDB, long-format telemetry.** A new dedicated Postgres+Timescale
  instance. Long/narrow telemetry rows let heterogeneous metrics from
  different sources coexist with zero schema churn when connectors are added.
- Dropped from the overall roadmap during brainstorming: media & habits
  (Spotify/Last.fm/app-usage), Strava, n8n, self-hosted Firefly III.

## Architecture

A new `src/astarte/ingestion/` package. The core knows nothing about any
specific device; all device-specifics live in connector modules.

```
ingestion/
  models.py         # normalized Pydantic types: Device, Reading, Event
  connectors/
    base.py         # Connector protocol + shared state-transition helper
    prusalink.py    # PrusaLink: poll local REST API, derive print events
    masterbuilt.py  # Masterbuilt Gravity: poll via community lib, derive cook events
  scheduler.py      # AsyncIOScheduler (APScheduler), started in FastAPI lifespan
  repository.py     # persistence over TimescaleDB (the ONLY module touching SQL)
  router.py         # /devices, /telemetry, /events read API
```

### Connector protocol (the key boundary)

Each connector exposes `poll() -> list[Reading | Event]` returning **normalized**
objects. The scheduler and repository never branch on device type. Adding a
future connector (Garmin, YNAB, …) is one new file implementing the protocol —
no core changes.

- **Scheduler**: per-connector poll intervals; poll frequently (~10s) only
  while a device is active, back off when idle. A failing poll is isolated —
  it logs and is skipped, never crashing the loop or other connectors.
- **State-transition → events**: a small shared helper tracks each device's
  last state in memory and emits events on transitions. Identical logic for
  both connectors, so it is not duplicated.
- **Reads**: `router.py` exposes the read API that iris will consume in
  sub-project 4. A webhook receiver is explicitly out of scope for v1 (would
  only matter if OctoPrint is added later).

## Storage (TimescaleDB)

A dedicated Postgres+Timescale instance (new `compose/` service). Three tables,
written **only** through `repository.py`:

- **`device`** — registry: id, `kind` (`printer` | `smoker`), `source`
  (`prusalink` | `masterbuilt`), human name, `metadata` jsonb.
- **`telemetry`** — Timescale **hypertable**, long/narrow format:
  `time`, `device_id`, `metric`, `value`, `unit`. Metrics are source-defined
  strings (`temp_tool`, `temp_bed`, `progress_pct`, `temp_grate`, `setpoint`,
  `temp_probe1`…). New metrics need no schema change; Timescale
  `time_bucket`/continuous aggregates serve the dashboard later.
- **`event`** — sparse (not a hypertable): `time`, `device_id`, `type`
  (`print_started`, `print_done`, `print_failed`, `target_reached`,
  `cook_done`), `payload` jsonb.

Driver stack: **SQLAlchemy 2.0 async + asyncpg**; a migration calls
`create_hypertable('telemetry', 'time')`. Exact columns/indexes are finalized
at implementation.

## Connectors

- **PrusaLink** — poll the local REST API (`/api/v1/status`, `/api/v1/job`)
  with API-key auth. Map → `temp_tool`, `temp_bed`, `progress_pct`,
  `time_remaining` readings. On state flip `PRINTING → FINISHED`/`ERROR`, emit
  `print_done` / `print_failed` (and `print_started` on entry to printing).
- **Masterbuilt Gravity (560/800/1050)** — poll via the community library.
  The exact auth/data surface (cloud vs. BLE, session handling) is verified by
  cloning the pinned upstream into `/tmp` at plan time. Map → `temp_grate`,
  `setpoint`, `temp_probe1..N`. Derive `target_reached` when grate crosses
  setpoint, `cook_done` on a probe threshold. Treated as fragile/unofficial —
  failures are contained and logged.

## Config & secrets

Per-connector settings — PrusaLink host + API key, Masterbuilt cloud
credentials — via env, sourced from the chezmoi-managed `.env` that flows from
Bitwarden. New keys are added to `.env.example` as well (all `.env` files are
chezmoi-managed in this repo, even before secrets land).

## Error handling

- Each poll is wrapped so a flaky source (especially the unofficial Masterbuilt
  lib) logs and skips without affecting the scheduler or other connectors.
- A device is marked **stale** after N consecutive missed polls.
- The unofficial Masterbuilt client is wrapped behind the connector boundary so
  upstream breakage is contained to one module.

## Testing (TDD)

- **Connector normalization** tested against **recorded sample payloads**
  (fixtures captured from the real PrusaLink and Masterbuilt devices) — verifies
  raw → normalized `Reading`/`Event` mapping and state-transition event
  derivation.
- **Repository** tested against a Timescale test container.
- External HTTP is mocked; no live device required in CI.
- New dependencies: `sqlalchemy[asyncio]`, `asyncpg`, `apscheduler`. Code must
  satisfy astarte's existing strict ruff ruleset (type annotations, google-style
  docstrings, timezone-aware datetimes, no `print`).

## Out of scope (v1)

- Webhook/push receivers (PrusaLink and Masterbuilt are poll-only).
- iris dashboard surfaces and alerting (sub-project 4).
- Any health, finance, or productivity connector (later sub-projects).
