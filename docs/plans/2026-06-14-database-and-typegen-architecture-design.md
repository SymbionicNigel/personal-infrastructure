# Database & type-generation architecture

## Context

We need a database tier for the personal-infrastructure stack — none exists yet (only `dokploy-postgres`, which is Dokploy's own state). The goal is the smallest setup that (a) backs our own services and any self-hosted containers that need a DB, (b) feeds a user/dashboard-facing view, and (c) gives end-to-end type safety into TypeScript (iris today, a mobile app later) — without overcomplicating the DB itself.

Guiding constraint throughout: **keep complexity out of the database.** Sync, fan-in, and reactivity live at the API/client boundary, not in Postgres.

## Decisions

- **Engine:** one PostgreSQL instance using the **`timescale/timescaledb`** image — plain Postgres plus an opt-in time-series extension, zero added overhead unless a hypertable is created.
- **Schema ownership:** **astarte owns all schema and migrations** (SQLAlchemy + Alembic). The DB is the single source of truth; everything else is derived.
- **Tenancy:** one shared instance.
  - A single `app` schema for everything we build (astarte today, future custom services), owned by one role.
  - One schema + one scoped login role per third-party container that can use Postgres.
- **TS services never read or write the DB** — TypeScript needs DB-shaped *types* only, for type safety. No TS runtime touches Postgres.
- **Sync stays at the client/API boundary**, never in the DB.

## Architecture

### Data integration — tiered, cheapest tier that works
Sources are heterogeneous (some Postgres-capable, some MySQL/SQLite/ClickHouse-only). The dashboard-facing view is built by reaching each source at the lowest-cost tier:

1. **Default — shared Postgres.** Anything that speaks Postgres writes into the one instance (its own schema). The dashboard reads across schemas via SQL views. No pipeline.
2. **Only when a source is stuck on another engine and the dashboard needs its data** — start with **scheduled ETL** (cron + a small script). Promote a specific source to **FDW** (`postgres_fdw`/`mysql_fdw`) or **native logical replication** only if "live" turns out to matter for it.
3. The **dashboard-facing DB is this same Postgres/Timescale instance** (Timescale earns its keep for rollups/time-series dashboard data).

### Schema & migrations
- astarte defines models (SQLAlchemy; optionally **SQLModel** so one model is both table and Pydantic/OpenAPI schema) and runs **Alembic** migrations into the `app` schema.
- **Timescale specifics:** the ORM maps hypertables like any table. Timescale DDL (`create_hypertable`, continuous aggregates, compression/retention policies) is not in SQLAlchemy — do it as raw SQL inside Alembic migrations (`op.execute("SELECT create_hypertable(...)")`), one-time and confined to migrations. Timescale query functions (`time_bucket`, other hyperfunctions) need no raw SQL: SQLAlchemy's generic `func.*` emitter handles `func.time_bucket('1 hour', Model.ts)` in normal ORM queries.
- Third-party containers run their own migrations, confined to their own schema via their scoped role.

### Type generation — two narrow pipelines
TS never accesses the DB at runtime; both pipelines exist purely to produce types.

| Need | Source of truth | Codegen |
|---|---|---|
| iris / mobile typed against **astarte's API** | FastAPI Pydantic (or SQLModel) models → OpenAPI | **`openapi-typescript`** (+ `openapi-fetch` for a typed client) |
| TS code that needs **DB-shaped types to work off of** (no DB access) | DB schema | **`drizzle-kit pull`** (introspection → types only) |

- Primary path is OpenAPI → TS: astarte writes `openapi.json` (`app.openapi()`), CI runs `openapi-typescript` → a shared types module iris and the mobile app import. Regenerates when Pydantic models change; no drift.
- The Drizzle-pull path introspects the live schema into TS types as a convenience for working against DB shapes — it does **not** imply any TS process connecting to Postgres.

### Mobile sync
- The mobile app uses a client-side reactive store (e.g. **WatermelonDB**) that syncs against a **pull/push sync endpoint implemented in astarte**. The server DB stays plain Postgres/Timescale — no sync engine. WatermelonDB's own schema declaration is generated from the same introspection output via a small adapter, so it stays derived.

### Deployment shape (matches existing patterns)
- A **`postgres` service in `compose/docker-compose.yml`**, following the astarte/iris pattern with DB-specific deviations:
  - **No Traefik labels / no public route** — internal-only on `dokploy-network`. (Remote admin via SSH tunnel or `postgres-saveExternalPort`, never an HTTP router.)
  - **Named volume** for `PGDATA` so data survives redeploys.
  - Image pinned via a new `TF_VAR_POSTGRES_IMAGE_TAG` (`timescale/timescaledb:<pinned>`), substituted by the existing `templatefile()` flow.
  - **Healthcheck** (`pg_isready`) so dependents can gate on `condition: service_healthy`.
  - `compose/docker-compose.override.yml`: expose `5432` locally for dev.
  - Superuser + per-service credentials sourced from chezmoi env templates (`.secrets/compose/dot_env*.tmpl`); never committed plaintext.

### Role/schema provisioning — astarte owns it
The instance is internal-only, so an external Terraform provider (`cyrilgdn/postgresql` run in CI/local) can't reach it and has no readiness signal. Since **astarte already owns schema + migrations, runs in-network with DB access, and handles DB readiness**, it also owns role/schema provisioning — no new component, no exposed port, no external provider.

**Privileges.** astarte provisions over a dedicated least-privilege **`provisioner`** role (`CREATEROLE` + `CREATE` on the database), not the superuser and not its own runtime `app` role. The superuser is used only for first-init.

**Credentials — one source, rendered to two places.** Each service's password is generated once in chezmoi and rendered to exactly the consumers that need it; nothing is invented at runtime. `.secrets/compose/dot_env*.tmpl` holds the superuser password, the `provisioner` password, and one password per service (`MEALIE_DB_PASSWORD`, …). chezmoi renders these into the compose env (Terraform already inlines per container), so each container sees only what it needs:
- **postgres** → `POSTGRES_PASSWORD` (first-init only).
- **astarte** → the `provisioner` DSN **plus** every service's password (to set them).
- **each third-party service** → only its own `*_DB_PASSWORD`.

The same chezmoi value lands in astarte and in the service, so they always match.

**Manifest, not hard-coding.** astarte reads a chezmoi-rendered JSON manifest enumerating what to ensure, e.g. `[{"service":"mealie","schema":"mealie","role":"mealie","password_env":"MEALIE_DB_PASSWORD"}, …]`, pulls each password from its env, and reconciles.

**Idempotent reconcile** (same mechanism that creates astarte's own `app` role/schema, extended over the manifest): create role if missing, always `ALTER ROLE … PASSWORD` to sync, `CREATE SCHEMA IF NOT EXISTS … AUTHORIZATION …`, grants scoped to that schema only.

**Rotation:** change the value in chezmoi → `czm apply` → redeploy. astarte's `ALTER ROLE … PASSWORD` picks up the new value and the service container receives the same new value in its env — both sides move together.

**Ordering caveat:** a third-party service may boot and try to connect before astarte has created its role. Handle via container **restart policy / client retry** (the container restarts until the role exists) rather than coupling every service's `depends_on` to astarte.

### Backups — via Dokploy's automated backups
Dokploy can back up a database that runs as a **service inside a compose stack** (not only native Dokploy DB resources). Integration:

- Add a **Destination** in Dokploy (`/dashboard/settings/destinations`) pointing at our **Linode Object Storage** bucket (S3-compatible is supported), with a backup prefix.
- Attach a **scheduled backup** to the compose `postgres` service: select the service, database name, credentials, and the Destination; set a cron schedule. Dokploy runs `pg_dump` (works fully with Timescale hypertables) to the Destination. Use the **Test** button to verify before relying on it.
- This reuses the same Object Storage backend and operational model as the existing `dokploy-postgres` backups, but through Dokploy's scheduler instead of a custom timer — so no `pg_dump` Terraform module is needed for the app DB.

**As-code caveat:** Destinations/backup schedules are Dokploy state. If the `j0bIT/dokploy` Terraform provider lacks backup/destination resources, configure these once via the Dokploy UI (or the dokploy MCP) and document it; that one-time config is the trade-off for using the native scheduler. (Fallback if as-code is required: clone `linode/modules/dokploy-postgres-backup/` into an `app-postgres-backup` module.)

## Implementation steps (ordered)
1. Add the `postgres` (`timescale/timescaledb`) service to `compose/docker-compose.yml` (internal-only, named volume) + dev `5432` mapping in the override; add `TF_VAR_POSTGRES_IMAGE_TAG` and chezmoi env entries for superuser creds.
2. Wire astarte to the DB: SQLAlchemy/SQLModel models + Alembic, migrating into the `app` schema; add a DB health check.
3. Add astarte-owned provisioning: a `provisioner` role, a chezmoi-rendered service manifest + per-service password env, and the idempotent reconcile (roles/schemas/grants) run on startup — creating astarte's own `app` role/schema first, then manifest entries.
4. Configure Dokploy backups: create the Linode Object Storage Destination, attach a scheduled backup to the `postgres` compose service, run a Test backup, and document the config (and restore procedure).
5. Type-gen pipeline 1 (primary): emit `openapi.json` from astarte in CI → `openapi-typescript` → shared TS types consumed by iris.
6. Type-gen pipeline 2 (types only): add `drizzle-kit pull` to introspect the schema into TS types.
7. (When mobile work starts) implement the WatermelonDB sync endpoint in astarte + generate its schema from the introspection output.
8. (Per-service, as adopted) for each third-party DB-needing container: provision schema + role, point it at the instance; add ETL/FDW/replication only if the dashboard needs that source and it can't co-locate.

## Verification
- `psql` into the instance shows the `app` schema owned by the `app` role; per-service roles cannot read outside their own schema.
- astarte boots, runs Alembic migrations cleanly, passes its DB health check locally (`docker compose up`) and in prod.
- A Dokploy Test backup lands an object in the Linode Object Storage bucket; a restore from it succeeds.
- CI regenerates TS types from `openapi.json`; a deliberate Pydantic model change shows up in the generated types.

## Deferred / open
- Whether the dokploy Terraform provider can declare Destinations/backups (decides if backup config is fully as-code or a one-time UI/MCP step).
- Which specific third-party services get adopted and which need dashboard fan-in — driven by the service catalog (`2026-06-14-dokploy-service-catalog.md`), decided per-service later.
