#!/usr/bin/env bash
# Post-deploy verification: poll Dokploy for container health after a
# compose redeploy and exit non-zero if the stack doesn't stabilize.
#
# Invoked by terraform_data.deploy_verify in main.tf. Closes the gap
# between Dokploy's `docker compose up -d --build` (which returns when
# containers START, not when healthy) and a deploy actually being
# successful. Without this, a fail-closed container (reconcile error,
# astarte migration error) crashloops silently behind a green deploy.
#
# Inputs (environment):
#   DOKPLOY_API_BASE        e.g. https://vulcan.symbionic.tech/api
#   DOKPLOY_API_KEY
#   COMPOSE_ID              the dokploy_compose resource id
#   EXPECTED_SERVICE_COUNT  number of services declared in the compose
#                           YAML (derived in main.tf via yamldecode)
#
# Pass criteria (all must hold for STREAK_REQUIRED consecutive samples):
#   - Dokploy reports exactly EXPECTED_SERVICE_COUNT containers
#   - Every container's state == "running"
#
# Exit codes:
#   0  stack stabilized
#   1  timed out, wrong container count, or non-running states past the limit

set -euo pipefail

: "${DOKPLOY_API_BASE:?}"
: "${DOKPLOY_API_KEY:?}"
: "${COMPOSE_ID:?}"
: "${EXPECTED_SERVICE_COUNT:?}"

# 60 polls * 5s = 5 minutes total budget. Sized for a cold deploy:
# GHCR pulls of all four images on a fresh node can run 60-90s alone,
# then container start + reconcile + the 15s healthy streak. A healthy
# deploy still exits early, so the extra budget only costs on failure.
POLL_INTERVAL_SECONDS=5
MAX_POLLS=60
STREAK_REQUIRED=3

trpc_get() {
  local route="$1" payload="$2"
  local encoded
  encoded=$(python3 -c 'import json,sys,urllib.parse;print(urllib.parse.quote(json.dumps({"json":json.loads(sys.argv[1])})))' "$payload")
  curl -sf -H "x-api-key: ${DOKPLOY_API_KEY}" "${DOKPLOY_API_BASE}/trpc/${route}?input=${encoded}"
}

echo "verify: fetching compose appName"
compose_json=$(trpc_get "compose.one" "{\"composeId\":\"${COMPOSE_ID}\"}")
app_name=$(python3 -c 'import json,sys;print(json.loads(sys.stdin.read())["result"]["data"]["json"]["appName"])' <<<"$compose_json")

if [ -z "$app_name" ]; then
  echo "verify: failed to resolve appName from compose.one response" >&2
  exit 1
fi

echo "verify: polling container health for appName=${app_name}"
echo "verify: expecting ${EXPECTED_SERVICE_COUNT} running containers"

streak=0
last_report=""
for poll in $(seq 1 "${MAX_POLLS}"); do
  sleep "${POLL_INTERVAL_SECONDS}"

  containers_json=$(trpc_get "docker.getContainersByAppLabel" \
    "{\"appName\":\"${app_name}\",\"type\":\"standalone\"}")

  last_report=$(APP_NAME_FILTER="${app_name}" CONTAINERS_JSON="${containers_json}" python3 - <<'PY'
import json, os
data = json.loads(os.environ["CONTAINERS_JSON"])
containers = data.get("result", {}).get("data", {}).get("json") or []
# Dokploy's filter is a docker `name=` substring match, not exact. Tighten
# to "<appName>-" so a second stack whose name happens to prefix ours
# can't be mistaken for our containers.
prefix = os.environ["APP_NAME_FILTER"] + "-"
containers = [c for c in containers if c.get("name", "").startswith(prefix)]
expected = int(os.environ["EXPECTED_SERVICE_COUNT"])
total = len(containers)
states = [c.get("state", "?") for c in containers]
bad = [(c.get("name", "?"), s) for c, s in zip(containers, states) if s != "running"]
if total != expected:
    print(f"COUNT got={total} want={expected}")
elif bad:
    print("BAD " + ",".join(f"{n}={s}" for n, s in bad))
else:
    print("OK")
PY
)

  case "$last_report" in
    OK)
      streak=$((streak + 1))
      echo "verify: poll ${poll}: all healthy (streak=${streak}/${STREAK_REQUIRED})"
      if [ "${streak}" -ge "${STREAK_REQUIRED}" ]; then
        echo "verify: deploy healthy"
        exit 0
      fi
      ;;
    *)
      streak=0
      echo "verify: poll ${poll}: ${last_report}"
      ;;
  esac
done

echo "verify: TIMED OUT after $((MAX_POLLS * POLL_INTERVAL_SECONDS))s; last report: ${last_report}" >&2
exit 1
