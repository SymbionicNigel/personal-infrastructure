# Compose Split + Stage 2 Smoke Test Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Split the existing root `docker-compose.yml` into a prod-shaped base (consumed by Dokploy in production via `dokploy_compose`) and a local override that adds Hendrix for development. Add `janus` (traefik/whoami) as the first concrete service so Stage 2 has a working smoke target. Routing lives in Traefik labels in the base compose so both environments consume one source of truth.

**Architecture:**
- `docker-compose.yml` — prod-shaped base, contains every service that runs in either env, with explicit Traefik labels using `${VAR}` references for environment-specific values (host suffix, TLS settings).
- `docker-compose.local.yml` — adds Hendrix (local Traefik) and per-service overrides for HTTP-only local routing.
- `linode/environments/dokploy/main.tf` — switches from `dokploy_application` (which doesn't support Docker images at provider v0.3.0) to `dokploy_compose` driven by `templatefile()` reading the root compose with TF-supplied env values inlined.
- No `dokploy_domain` resources for app routing — labels are the source of truth.

**Tech Stack:**
- Docker Compose v2.20+ (for `include:` and modern multi-file merge semantics)
- Traefik v3.x (Hendrix locally, Dokploy's bundled instance in prod)
- Dokploy v0.29.2
- j0bIT/dokploy provider v0.3.0
- Terraform 1.x

---

## File Structure

| File | Responsibility |
|---|---|
| `docker-compose.yml` (rewrite) | Base service definitions + Traefik labels using `${VAR}` substitutions. Declares `dokploy-network` as external. Contains: `janus` only at end of plan; future services append here. No Hendrix, no version field, no commented vault/gitlab/etc. (those move to a reference comment block). |
| `docker-compose.local.yml` (create) | Adds `hendrix` service. Overrides `dokploy-network` to non-external (Compose creates it). Overrides per-service Traefik label env vars for HTTP-only local routing. |
| `.env.example` (modify) | Document every variable consumed by Compose interpolation: `HOSTNAME_TLD`, `TRAEFIK_ENTRYPOINTS`, `TRAEFIK_TLS`, `TRAEFIK_CERT_RESOLVER`, plus existing `HTTPS_EMAIL`, `TLS_LINODE_TOKEN`. |
| `linode/environments/dokploy/main.tf` (rewrite) | Replace `dokploy_application` + `dokploy_domain` with `dokploy_environment.production` + `dokploy_compose.stack`. Compose content via `templatefile()` reading `../../../docker-compose.yml` with prod values. |
| `linode/environments/dokploy/outputs.tf` (modify) | Replace `janus_application_id` with `compose_id`. Keep `project_id`. |
| `linode/environments/dokploy/variables.tf` (no change) | `HOSTNAME_TLD` already present. |

---

## Task 1: Rewrite root `docker-compose.yml` as prod-shaped base

**Files:**
- Modify: `docker-compose.yml` (full rewrite)

- [ ] **Step 1: Replace file content with prod-shaped base + janus**

Write to `docker-compose.yml`:

```yaml
# Base compose used in both environments.
#   - Production: consumed by Dokploy via `dokploy_compose` in
#     linode/environments/dokploy/main.tf. Dokploy's bundled Traefik picks up
#     the labels below and routes accordingly.
#   - Local: combine with docker-compose.local.yml (which adds Hendrix and
#     per-service env overrides for HTTP-only local routing):
#       docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
#
# Routing source of truth: Traefik labels on each service. ${VAR} placeholders
# are substituted by Compose at deploy time from the surrounding env (.env
# locally; values inlined by Terraform's templatefile() in prod).
#
# To add a new service:
#   1. Append a service block following the janus pattern below.
#   2. Add Traefik labels using the same ${VAR} envs.
#   3. In docker-compose.local.yml, add an env-var override block if the
#      service needs different routing locally (HTTP vs HTTPS, etc.).

services:
  janus:
    image: traefik/whoami:latest
    networks:
      - dokploy-network
    labels:
      traefik.enable: "true"
      traefik.http.routers.janus.rule: "Host(`janus.${HOSTNAME_TLD}`)"
      traefik.http.routers.janus.entrypoints: "${TRAEFIK_ENTRYPOINTS}"
      traefik.http.routers.janus.tls: "${TRAEFIK_TLS}"
      traefik.http.routers.janus.tls.certresolver: "${TRAEFIK_CERT_RESOLVER}"
      traefik.http.services.janus.loadbalancer.server.port: "80"

networks:
  dokploy-network:
    external: true
    name: dokploy-network
```

- [ ] **Step 2: Validate the file parses with prod values**

```bash
HOSTNAME_TLD=symbionic.tech \
TRAEFIK_ENTRYPOINTS=websecure \
TRAEFIK_TLS=true \
TRAEFIK_CERT_RESOLVER=letsencrypt \
  docker compose -f docker-compose.yml config
```

Expected: prints the rendered compose with `Host(\`janus.symbionic.tech\`)` and `entrypoints: websecure`. No errors. (The `dokploy-network` "external" warning may print — that's expected; the network exists in prod, not on the local docker daemon yet.)

- [ ] **Step 3: Commit**

```bash
git add docker-compose.yml
git commit -m "refactor: rewrite docker-compose.yml as prod-shaped base with janus"
```

---

## Task 2: Create `docker-compose.local.yml`

**Files:**
- Create: `docker-compose.local.yml`

- [ ] **Step 1: Write the local override file**

Write to `docker-compose.local.yml`:

```yaml
# Local-only overrides on top of docker-compose.yml.
# Usage:
#   docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
#
# Adds Hendrix (local Traefik) and flips per-service Traefik label env vars
# so routing is HTTP-only locally. The base file's ${VAR} references resolve
# from the `environment:` blocks below at compose-up time.
#
# HOSTNAME_TLD is supplied via the root .env (docker.localhost works because
# the .localhost TLD always resolves to 127.0.0.1, no DNS needed).

services:
  hendrix:
    image: traefik:${TRAEFIK_VERSION:-v3.1}
    container_name: hendrix
    restart: unless-stopped
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080" # dashboard
    environment:
      HOSTNAME_TLD: "${HOSTNAME_TLD:?err}"
      HTTPS_EMAIL: "${HTTPS_EMAIL:?err}"
      LINODE_TOKEN: "${TLS_LINODE_TOKEN:?err}"
      TLS_MODE: "${TLS_MODE:-local}"
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./traefik/config/traefik.yml:/etc/traefik/traefik.yml:ro
      - ./traefik/config/dynamic.yml:/etc/traefik/dynamic.yml:ro
      - ./traefik/letsencrypt:/letsencrypt:rw
      - ./traefik/local_certs:/certs:ro
    networks:
      - dokploy-network
    labels:
      traefik.enable: "true"
      traefik.http.routers.hendrix.rule: "Host(`hendrix.${HOSTNAME_TLD}`)"
      traefik.http.routers.hendrix.entrypoints: "web"
      traefik.http.routers.hendrix.service: "api@internal"

  # Per-service overrides: flip routing env vars so labels in the base file
  # render with HTTP-only values locally.
  janus:
    environment:
      TRAEFIK_ENTRYPOINTS: "web"
      TRAEFIK_TLS: "false"
      TRAEFIK_CERT_RESOLVER: ""

networks:
  # Override base's external: true so Compose creates this network locally.
  dokploy-network:
    external: false
    name: dokploy-network
```

- [ ] **Step 2: Validate the merged file parses**

```bash
HOSTNAME_TLD=docker.localhost \
HTTPS_EMAIL=test@example.com \
TLS_LINODE_TOKEN=placeholder \
TRAEFIK_ENTRYPOINTS=websecure \
TRAEFIK_TLS=true \
TRAEFIK_CERT_RESOLVER=letsencrypt \
  docker compose -f docker-compose.yml -f docker-compose.local.yml config
```

Expected: rendered output shows `hendrix` service plus `janus` with `entrypoints: web`, `tls: false`, empty `certresolver`. The local override of `dokploy-network` shows `external: false`.

- [ ] **Step 3: Commit**

```bash
git add docker-compose.local.yml
git commit -m "feat: add docker-compose.local.yml for local stack"
```

---

## Task 3: Update `.env.example` to document the new variables

**Files:**
- Modify: `.env.example`

- [ ] **Step 1: Replace `.env.example` content**

Write to `.env.example`:

```bash
# Used by Compose interpolation for both base and local files.
# Copy to .env (local) or set via Dokploy env management (prod).

# --- Required ---

# Routing host suffix. Local default is docker.localhost (always resolves to
# 127.0.0.1 in modern OSes). Prod is your real TLD (e.g. symbionic.tech).
HOSTNAME_TLD="docker.localhost"

# Traefik label values, prod-shaped here. docker-compose.local.yml flips
# these per-service for HTTP-only local routing, so leave the prod values
# in your local .env as the safe defaults for any service that doesn't
# define a local override.
TRAEFIK_ENTRYPOINTS="websecure"
TRAEFIK_TLS="true"
TRAEFIK_CERT_RESOLVER="letsencrypt"

# Hendrix (local-only Traefik) wants these. Not used by the prod compose.
HTTPS_EMAIL="you@example.com"
TLS_LINODE_TOKEN=""
TLS_MODE="local"

# --- Optional version pins ---
TRAEFIK_VERSION=""
```

- [ ] **Step 2: Commit**

```bash
git add .env.example
git commit -m "docs: document new compose env vars in .env.example"
```

---

## Task 4: Smoke-test the local stack runs end-to-end

**Files:**
- No file changes

- [ ] **Step 1: Ensure your local `.env` has the required variables**

Run:

```bash
grep -E '^(HOSTNAME_TLD|TRAEFIK_ENTRYPOINTS|TRAEFIK_TLS|TRAEFIK_CERT_RESOLVER|HTTPS_EMAIL|TLS_LINODE_TOKEN|TLS_MODE)=' .env
```

Expected: all seven variables present and non-empty (except `TRAEFIK_CERT_RESOLVER` which can be empty for local; the value is overridden per-service anyway).

If anything is missing, copy from `.env.example` and adjust. `TLS_LINODE_TOKEN` only needs a real value if you want LE certs locally via DNS-01 — for the smoke test, any non-empty placeholder is fine because janus's local override sets `TRAEFIK_TLS=false`.

- [ ] **Step 2: Bring the stack up**

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml up -d
```

Expected: `dokploy-network` created, `hendrix` and `janus` containers start. No errors in `docker compose ps` (both `Up`).

- [ ] **Step 3: Verify Hendrix sees janus and routing works**

```bash
curl -s -H "Host: janus.docker.localhost" http://127.0.0.1/ | head -20
```

Expected: traefik/whoami text output (Hostname, IP, Headers). If this fails, check `docker logs hendrix` for label-parsing errors.

- [ ] **Step 4: Tear the stack down**

```bash
docker compose -f docker-compose.yml -f docker-compose.local.yml down
```

Expected: containers stopped and removed; the manually-created `dokploy-network` removed.

- [ ] **Step 5: Commit any incidental fixes**

If the test exposed a label or env-var issue, fix it in the relevant compose file, re-run Step 2-3, and:

```bash
git add docker-compose.yml docker-compose.local.yml
git commit -m "fix: <whatever the issue was>"
```

---

## Task 5: Rewrite Stage 2 TF to use `dokploy_compose`

**Files:**
- Modify: `linode/environments/dokploy/main.tf` (full rewrite of resource section)
- Modify: `linode/environments/dokploy/outputs.tf`

- [ ] **Step 1: Rewrite `main.tf`**

Replace `linode/environments/dokploy/main.tf` content with:

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
  host    = var.DOKPLOY_HOST
  api_key = var.DOKPLOY_API_KEY
}

resource "dokploy_project" "main" {
  name        = "symbionic-services"
  description = "Primary services managed by Terraform"
}

# `dokploy_compose` requires an environment_id explicitly (unlike
# dokploy_application which auto-binds to the project's production env).
resource "dokploy_environment" "production" {
  project_id  = dokploy_project.main.id
  name        = "production"
  description = "Default production environment"
}

# Inline compose content. We use templatefile() to substitute the prod values
# for ${VAR} placeholders in docker-compose.yml at apply time. This lets the
# same file work for `docker compose up` locally (Compose substitutes from
# .env) and in Dokploy (Terraform substitutes here), with Dokploy never
# needing env-var management for the compose itself.
locals {
  compose_content = templatefile("${path.root}/../../../docker-compose.yml", {
    HOSTNAME_TLD           = var.HOSTNAME_TLD
    TRAEFIK_ENTRYPOINTS    = "websecure"
    TRAEFIK_TLS            = "true"
    TRAEFIK_CERT_RESOLVER  = "letsencrypt"
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

Replace `linode/environments/dokploy/outputs.tf` content with:

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

```bash
cd linode/environments/dokploy
set -a; source .env; set +a
terraform validate
```

Expected: `Success! The configuration is valid.` If `templatefile()` complains about a missing variable, it means a `${...}` reference exists in `docker-compose.yml` that wasn't supplied in the templatefile call — add it to the locals map.

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

```bash
cd linode/environments/dokploy
set -a; source .env; set +a
terraform plan
```

Expected: plans to *destroy* `dokploy_application.janus` and `dokploy_domain.janus` (the broken old resources), and *create* `dokploy_environment.production` and `dokploy_compose.stack`. `dokploy_project.main` stays as-is. Review the diff for anything unexpected before applying.

- [ ] **Step 2: Apply**

```bash
terraform apply -auto-approve
```

Expected: clean apply. Outputs include `project_id`, `environment_id`, `compose_id`. No errors.

- [ ] **Step 3: Verify Dokploy created the stack and started it**

In a browser, log into `https://vulcan.symbionic.tech`, navigate to the `symbionic-services` project, find the `stack` compose. The UI should show `janus` as a service in `Running` state. If it's `Failed`, click into logs.

Alternatively from the Linode shell:

```bash
ssh -i linode/environments/production/id_ed25519 root@<instance-ip> \
  'docker stack ps $(docker stack ls --format "{{.Name}}" | grep -v dokploy) --no-trunc'
```

Expected: a Dokploy-managed stack containing `janus` in state `Running`.

- [ ] **Step 4: End-to-end smoke test from outside**

```bash
curl -s https://janus.symbionic.tech/ | head -10
```

Expected: traefik/whoami text output (Hostname, IP, Headers). The first request after deploy may take a few seconds while Traefik issues the LE cert. If it returns a TLS error or default cert briefly, retry after 30s.

- [ ] **Step 5: Verify HTTP redirects to HTTPS**

```bash
curl -sI http://janus.symbionic.tech/
```

Expected: `301` or `308` redirect to `https://janus.symbionic.tech/`. (Dokploy's Traefik adds this automatically when `tls=true` is set on a router.)

- [ ] **Step 6: Commit any post-apply state changes**

If `terraform apply` updated `terraform.tfstate` (it lives in the S3 backend so this is a no-op locally), and if `chezmoi diff` shows drift on the encrypted `dokploy/.env`, reconcile:

```bash
chezmoi --config ./.chezmoi.toml diff
# If changes, re-encrypt:
source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt ./linode/environments/dokploy/.env
```

No commit if no diff.

---

## Verification (whole-plan smoke)

After all tasks complete:

| Check | Command | Expected |
|---|---|---|
| Local stack up | `docker compose -f docker-compose.yml -f docker-compose.local.yml up -d` | hendrix + janus running |
| Local routing | `curl -H "Host: janus.docker.localhost" http://127.0.0.1/` | whoami output |
| Local stack down | `docker compose -f docker-compose.yml -f docker-compose.local.yml down` | clean teardown |
| Prod TF clean | `cd linode/environments/dokploy && terraform plan` | "No changes." |
| Prod end-to-end | `curl -s https://janus.symbionic.tech/` | whoami output, real LE cert |
| Prod redirect | `curl -sI http://janus.symbionic.tech/` | 301/308 to https |

If all six pass, the split is done and Stage 2 is unblocked for adding more services — each new service is one block in `docker-compose.yml` (mirroring the janus shape) plus an optional override block in `docker-compose.local.yml` if local routing differs.
