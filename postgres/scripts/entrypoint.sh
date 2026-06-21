#!/usr/bin/env bash
# Wrapper around the upstream postgres/timescaledb entrypoint that runs
# reconcile-roles.sql after the server is accepting connections.
#
# Why a wrapper: the image's /docker-entrypoint-initdb.d/ only fires on
# first boot (empty PGDATA). For ongoing role provisioning — adding
# roles, rotating passwords — we need a hook that runs every start.
#
# Fail-closed: any reconcile error terminates postgres and exits non-zero
# so the container is marked failed by docker / dokploy. The deploy
# fails loudly rather than silently leaving stale role state in place.
# Brief DB downtime on a misconfigured deploy is preferable to a
# half-applied change going out marked green.
#
# Inputs (environment):
#   POSTGRES_USER, POSTGRES_PASSWORD, POSTGRES_DB
#     Standard image variables. Used here for the reconcile psql call.
#   POSTGRES_<NAME>_PASSWORD
#     One per role declared in reconcile-roles.sql. Bound to psql as
#     :<name>_password (lowercased). Add a role = add a binding here
#     and a CREATE/ALTER block in reconcile-roles.sql.

set -euo pipefail

SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"
RECONCILE_SQL="${SCRIPT_DIR}/reconcile-roles.sql"

abort_postgres() {
  if kill -0 "${PG_PID}" 2>/dev/null; then
    kill -TERM "${PG_PID}" 2>/dev/null || true
    wait "${PG_PID}" 2>/dev/null || true
  fi
}

# Start the upstream entrypoint in the background so we can run reconcile
# against the live server before handing control back.
/usr/local/bin/docker-entrypoint.sh "$@" &
PG_PID=$!

# Install signal forwarding before any blocking wait. If `docker stop`
# arrives during pg_isready or reconcile, we want postgres to receive
# SIGTERM and shut down cleanly rather than getting orphaned + SIGKILLed.
trap 'kill -TERM "${PG_PID}" 2>/dev/null || true; wait "${PG_PID}" 2>/dev/null || true' TERM INT

# Wait for postgres to accept connections (up to 60s). Exit non-zero if
# postgres dies during startup or fails to become ready within the window.
tries=0
until PGPASSWORD="${POSTGRES_PASSWORD}" pg_isready \
    --host=localhost \
    --username="${POSTGRES_USER}" \
    --dbname="${POSTGRES_DB}" \
    --quiet; do
  if ! kill -0 "${PG_PID}" 2>/dev/null; then
    echo "reconcile: postgres exited during startup; aborting" >&2
    wait "${PG_PID}" 2>/dev/null || true
    exit 1
  fi
  tries=$((tries + 1))
  if [ "${tries}" -ge 60 ]; then
    echo "reconcile: pg_isready timed out after 60s; aborting" >&2
    abort_postgres
    exit 1
  fi
  sleep 1
done

echo "reconcile: applying roles via reconcile-roles.sql"
if ! PGPASSWORD="${POSTGRES_PASSWORD}" psql \
    --host=localhost \
    --username="${POSTGRES_USER}" \
    --dbname="${POSTGRES_DB}" \
    --set=ON_ERROR_STOP=1 \
    --set=astarte_password="${POSTGRES_ASTARTE_PASSWORD}" \
    --set=iris_ro_password="${POSTGRES_IRIS_RO_PASSWORD}" \
    --file="${RECONCILE_SQL}"; then
  echo "reconcile: FAILED; aborting container" >&2
  abort_postgres
  exit 1
fi
echo "reconcile: applied successfully"

# Wait for postgres to exit; the TERM/INT trap above forwards stop signals.
wait "${PG_PID}"
