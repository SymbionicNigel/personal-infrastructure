# Compose Split (No-Local-Proxy) + Stage 2 Smoke Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the current root `docker-compose.yml` (which mixes Hendrix + commented placeholders + a `whoami` service) with a clean, prod-shaped base consumed by Dokploy via `dokploy_compose` in production, plus a tiny `docker-compose.override.yml` that only exposes service ports on `localhost` for local dev. No local reverse proxy. Add `janus` (traefik/whoami) as the first concrete service so Stage 2 has a working smoke target.

**Architecture:**
- Local and prod share **one service definition** (image, env, volumes, healthchecks, networks, Traefik labels). The only thing that differs is *how traffic reaches the service*: locally via a published port on `localhost`, in prod via Dokploy's bundled Traefik consuming the labels.
- `docker-compose.override.yml` is auto-loaded by `docker compose up` — no `-f` flag dance. It adds `ports:` and flips `dokploy-network` to non-external. It does **not** touch Traefik labels (they're inert locally because there's no Traefik to read them).
- Prod deploys via Terraform → `dokploy_compose` resource → `templatefile()` inlines the base compose with `HOSTNAME_TLD` substituted. Dokploy never reads the override file because TF passes raw content, not a path.
- Routing source of truth = Traefik labels on services. No `dokploy_domain` resources, no domain config in the Dokploy UI.

**Tech Stack:**
- Docker Compose v2.20+
- Traefik v3.x (Dokploy's bundled instance in prod only)
- Dokploy v0.29.2
- j0bIT/dokploy provider v0.3.0
- Terraform 1.x

---

## File Structure

| File | Responsibility |
|---|---|
| `docker-compose.yml` (rewrite) | Prod-shaped base. Service definitions + Traefik labels with **only `HOSTNAME_TLD` parameterized** (other label values are hardcoded prod values; they're inert locally). Declares `dokploy-network` as external. Contains `janus` only at end of plan; future services append here. No Hendrix, no `whoami`, no `version:`, no commented vault/gitlab/postgres blocks. |
| `docker-compose.override.yml` (create) | Auto-loaded local override. Adds `ports:` per service to expose them on `localhost`. Flips `dokploy-network` to non-external so Compose creates it. Does not redefine images, env, volumes, or labels. |
| `.env.example` (modify) | Document the **minimal** set of variables: `HOSTNAME_TLD` (the only one Compose interpolates) + the Dokploy/Linode/Bitwarden vars used elsewhere. Drop stale entries (`GITLAB_HOME`, `VAULT_VERSION`, `GITLAB_VERSION`, `TLS_LINODE_TOKEN`, `HTTPS_EMAIL`, `TRAEFIK_VERSION`). |
| `linode/environments/dokploy/main.tf` (rewrite) | Replace `dokploy_application` + `dokploy_domain` with `dokploy_environment.production` + `dokploy_compose.stack`. Compose content via `templatefile()` reading `../../../docker-compose.yml` with `HOSTNAME_TLD` substituted. |
| `linode/environments/dokploy/outputs.tf` (modify) | Replace `janus_application_id` with `compose_id`. Add `environment_id`. Keep `project_id`. |
| `linode/environments/dokploy/variables.tf` (no change) | `HOSTNAME_TLD` already present. |

The `traefik/` directory becomes unused after this plan but is left in place — cleanup is a follow-up task, not part of this plan.

---

## Task 1: Rewrite root `docker-compose.yml` as a prod-shaped base

**Files:**
- Modify: `docker-compose.yml` (full rewrite)

- [ ] **Step 1: Replace file content**

Write to `docker-compose.yml`:

```yaml
# Base compose: prod-shaped, the single source of truth for service
# definitions across both environments.
#
#   Production: consumed by Dokploy via `dokploy_compose` in
#     linode/environments/dokploy/main.tf. Terraform inlines this file
#     via templatefile() and substitutes ${HOSTNAME_TLD} at apply time.
#     Dokploy's bundled Traefik picks up the labels below and routes
#     accordingly.
#
#   Local: `docker compose up` auto-loads docker-compose.override.yml
#     alongside this file. The override adds `ports:` per service so
#     each is reachable at http://localhost:<port>. There is no local
#     Traefik; the labels below are metadata only when run locally.
#
# To add a service:
#   1. Append a service block following the `janus` pattern.
#   2. Add Traefik labels (hardcoded prod values; only ${HOSTNAME_TLD}
#      is interpolated).
#   3. In docker-compose.override.yml, add a `ports:` mapping so the
#      service is reachable locally.

services:
  janus:
    image: traefik/whoami:latest
    networks:
      - dokploy-network
    labels:
      traefik.enable: "true"
      traefik.http.routers.janus.rule: "Host(`janus.${HOSTNAME_TLD}`)"
      traefik.http.routers.janus.entrypoints: "websecure"
      traefik.http.routers.janus.tls: "true"
      traefik.http.routers.janus.tls.certresolver: "letsencrypt"
      traefik.http.services.janus.loadbalancer.server.port: "80"

networks:
  dokploy-network:
    external: true
    name: dokploy-network
```

- [ ] **Step 2: Validate the file parses against prod-style env**

Run:

```bash
HOSTNAME_TLD=symbionic.tech docker compose -f docker-compose.yml config
```

Expected: prints the rendered compose with `Host(\`janus.symbionic.tech\`)`. No errors. A warning about the external `dokploy-network` not existing on the local Docker daemon is expected and can be ignored — Step 2 of Task 4 covers the local-merged validation that doesn't trip it.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "refactor: rewrite docker-compose.yml as prod-shaped base with janus"
```

---

## Task 2: Create `docker-compose.override.yml`

**Files:**
- Create: `docker-compose.override.yml`

- [ ] **Step 1: Write the override file**

Write to `docker-compose.override.yml`:

```yaml
# Local-only override on top of docker-compose.yml. Auto-loaded by
# `docker compose up` — no -f flag needed. Not consumed in prod
# because Terraform inlines docker-compose.yml via templatefile() and
# passes raw content to Dokploy.
#
# Responsibilities:
#   - Expose each service on a host port so localhost works without
#     a reverse proxy.
#   - Flip dokploy-network to non-external so Compose creates it
#     locally (in prod, Dokploy creates it before stack deploy).
#
# To wire up a new service locally, add a `ports:` mapping here that
# matches the container port in the service's loadbalancer label.

services:
  janus:
    ports:
      - "8080:80"

networks:
  dokploy-network:
    external: false
    name: dokploy-network
```

- [ ] **Step 2: Validate the auto-merged file parses**

Run:

```bash
HOSTNAME_TLD=docker.localhost docker compose config
```

Expected: rendered output shows the `janus` service with `image: traefik/whoami:latest`, the original labels (including `Host(\`janus.docker.localhost\`)`), AND a `ports:` block mapping `8080:80`. The `networks.dokploy-network` section shows `external: false`.

If `docker compose config` does NOT pick up the override automatically, confirm the file is named exactly `docker-compose.override.yml` in the same directory as `docker-compose.yml`.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.override.yml
git commit -m "feat: add docker-compose.override.yml for local port exposure"
```

---

## Task 3: Update `.env.example`

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Replace `.env.example` content**

Write to `.env.example`:

```bash
# Variables consumed by the root docker-compose.yml interpolation.
# Copy to .env (local) — in prod these are supplied by Terraform's
# templatefile() call, not by a .env file on the server.

# --- Required ---

# Routing host suffix. Local default is docker.localhost (resolves to
# 127.0.0.1 on all modern OSes; no DNS or hosts file needed for the
# *.docker.localhost wildcard). Prod is the real TLD (e.g. symbionic.tech).
# Note: locally there is no Traefik, so this is metadata-only — services
# are reached at http://localhost:<port>. The variable is still required
# because `docker compose config` substitutes it into the labels.
HOSTNAME_TLD="docker.localhost"
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: simplify .env.example for compose split"
```

---

## Task 4: Local smoke test (verify the stack works end-to-end without Traefik)

**Files:**
- No file changes

- [ ] **Step 1: Ensure your local `.env` has `HOSTNAME_TLD`**

Run:

```bash
grep -E '^HOSTNAME_TLD=' .env
```

Expected: `HOSTNAME_TLD="docker.localhost"` (or another value you've picked). If missing, copy from `.env.example`.

- [ ] **Step 2: Bring the stack up**

Run:

```bash
docker compose up -d
```

Expected: `dokploy-network` created, `janus` container starts. `docker compose ps` shows `janus` as `Up`.

- [ ] **Step 3: Hit the service directly on localhost**

Run:

```bash
curl -s http://localhost:8080/ | head -20
```

Expected: traefik/whoami text output containing `Hostname:`, `IP:`, and `Headers:` lines. This proves the service is running and the port mapping works without any reverse proxy.

- [ ] **Step 4: Confirm the Traefik labels render correctly (without using them)**

Run:

```bash
docker inspect $(docker compose ps -q janus) \
  --format '{{ index .Config.Labels "traefik.http.routers.janus.rule" }}'
```

Expected: `Host(\`janus.docker.localhost\`)` (with backticks, exactly as it would appear in prod with the prod TLD substituted). This confirms the substitution path works; in prod the same machinery yields `Host(\`janus.symbionic.tech\`)`.

- [ ] **Step 5: Tear down**

Run:

```bash
docker compose down
```

Expected: container stopped and removed; `dokploy-network` removed (since the override marks it non-external locally).

- [ ] **Step 6: Commit any incidental fixes**

If the test exposed a label or port issue, fix it in the relevant compose file, re-run Steps 2-3, and:

```bash
git add docker-compose.yml docker-compose.override.yml
git commit -m "fix: <whatever the issue was>"
```

---

## Task 5: Rewrite Stage 2 Terraform to use `dokploy_compose`

**Files:**
- Modify: `linode/environments/dokploy/main.tf` (full rewrite of resource section)
- Modify: `linode/environments/dokploy/outputs.tf`

- [ ] **Step 1: Rewrite `main.tf`**

Replace the contents of `linode/environments/dokploy/main.tf` with:

```hcl
terraform {
  required_providers {
    dokploy = {
      source  = "j0bIT/dokploy"
      version = "0.3.0"
    }
  }
}

provider "dokploy" {
  host    = "https://vulcan.${var.HOSTNAME_TLD}/api"
  api_key = var.DOKPLOY_API_KEY
}

resource "dokploy_project" "main" {
  name        = "symbionic-services"
  description = "Primary services managed by Terraform"
}

# dokploy_compose requires an environment_id explicitly (unlike
# dokploy_application which auto-binds to the project's production env).
resource "dokploy_environment" "production" {
  project_id  = dokploy_project.main.id
  name        = "production"
  description = "Default production environment"
}

# Inline the root compose file with HOSTNAME_TLD substituted. This keeps
# the same docker-compose.yml usable for `docker compose up` locally
# (Compose substitutes from .env) and for Dokploy in prod (Terraform
# substitutes here). Only HOSTNAME_TLD is templated; all other Traefik
# label values are hardcoded prod values in the compose file itself.
locals {
  compose_content = templatefile("${path.root}/../../../docker-compose.yml", {
    HOSTNAME_TLD = var.HOSTNAME_TLD
  })
}

resource "dokploy_compose" "stack" {
  project_id           = dokploy_project.main.id
  environment_id       = dokploy_environment.production.id
  name                 = "stack"
  source_type          = "raw"
  compose_file_content = local.compose_content
  deploy_on_create     = true
}
```

- [ ] **Step 2: Rewrite `outputs.tf`**

Replace the contents of `linode/environments/dokploy/outputs.tf` with:

```hcl
output "project_id" {
  value       = dokploy_project.main.id
  description = "ID of the primary Dokploy project"
}

output "environment_id" {
  value       = dokploy_environment.production.id
  description = "ID of the project's production environment"
}

output "compose_id" {
  value       = dokploy_compose.stack.id
  description = "ID of the deployed compose stack (contains all services)"
}
```

- [ ] **Step 3: Validate Terraform parses both files**

Run:

```bash
cd linode/environments/dokploy
set -a; source .env; set +a
terraform validate
```

Expected: `Success! The configuration is valid.`

If `templatefile()` complains about a missing variable, a `${...}` reference exists in `docker-compose.yml` that wasn't supplied. Since only `${HOSTNAME_TLD}` is meant to be templated, any other `${...}` in the compose file is a bug — either add the value to the locals map (if it really should be templated) or hardcode it in the compose file (preferred for everything except `HOSTNAME_TLD`).

- [ ] **Step 4: Commit**

```bash
git add linode/environments/dokploy/main.tf linode/environments/dokploy/outputs.tf
git commit -m "feat: deploy services via dokploy_compose with templatefile"
```

---

## Task 6: Apply Stage 2 against the live Dokploy instance

**Files:**
- No file changes

- [ ] **Step 1: Plan and review**

Run:

```bash
cd linode/environments/dokploy
set -a; source .env; set +a
terraform plan
```

Expected: plans to **destroy** `dokploy_application.janus` and `dokploy_domain.janus` (the old, broken resources from before this plan), and **create** `dokploy_environment.production` and `dokploy_compose.stack`. `dokploy_project.main` should remain in place (no change). Outputs change: `janus_application_id` removed, `environment_id` and `compose_id` added.

Review the diff. If anything beyond those changes appears, stop and investigate before applying.

- [ ] **Step 2: Apply**

Run:

```bash
terraform apply -auto-approve
```

Expected: clean apply. Outputs include `project_id`, `environment_id`, `compose_id`. No errors.

- [ ] **Step 3: Verify Dokploy received the stack and started it**

Open `https://vulcan.symbionic.tech` in a browser, log in, navigate to the `symbionic-services` project, find the `stack` compose. The UI should show `janus` in the `Running` state. If `Failed`, open the logs panel for the failing service.

Alternatively, from a shell with SSH access to the Linode instance:

```bash
ssh -i linode/environments/production/id_ed25519 root@<instance-ip> \
  'docker stack ls'
```

Expected: a Dokploy-managed stack named something like `symbionic-services-stack-<hash>` is listed.

- [ ] **Step 4: End-to-end smoke test from outside**

Run:

```bash
curl -s https://janus.symbionic.tech/ | head -10
```

Expected: traefik/whoami text output (`Hostname:`, `IP:`, `Headers:`). The first request after deploy may take a few seconds while Dokploy's Traefik issues the Let's Encrypt cert. If it returns a TLS error or the Traefik default cert briefly, retry after 30 seconds.

- [ ] **Step 5: Verify HTTP redirects to HTTPS**

Run:

```bash
curl -sI http://janus.symbionic.tech/
```

Expected: `301` or `308` redirect to `https://janus.symbionic.tech/`. Dokploy's Traefik adds this automatically when `tls=true` is set on a router.

- [ ] **Step 6: Reconcile any chezmoi drift**

The Stage 2 secrets file is chezmoi-managed. After a successful apply, check for drift:

```bash
czm diff
```

If `linode/environments/dokploy/.env` shows changes, re-encrypt the source:

```bash
source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt ./linode/environments/dokploy/.env
```

No commit if no diff.

---

## Verification (whole-plan smoke)

After all tasks complete:

| Check | Command | Expected |
|---|---|---|
| Local stack up | `docker compose up -d` | `janus` running |
| Local direct hit | `curl -s http://localhost:8080/` | whoami output |
| Local label render | `docker inspect $(docker compose ps -q janus) --format '{{ index .Config.Labels "traefik.http.routers.janus.rule" }}'` | `Host(\`janus.docker.localhost\`)` |
| Local stack down | `docker compose down` | clean teardown |
| Prod TF clean | `cd linode/environments/dokploy && terraform plan` | "No changes." |
| Prod end-to-end | `curl -s https://janus.symbionic.tech/` | whoami output, valid LE cert |
| Prod redirect | `curl -sI http://janus.symbionic.tech/` | 301/308 to https |

If all seven pass, the split is done. Adding a new service from here on is:
1. One service block in `docker-compose.yml` (mirroring `janus`, with hardcoded prod label values and `${HOSTNAME_TLD}` in the Host rule).
2. One `ports:` mapping in `docker-compose.override.yml` if you want it reachable locally.
3. `terraform apply` — Terraform re-inlines the compose and Dokploy redeploys the stack.
