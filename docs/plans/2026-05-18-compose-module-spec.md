# Compose Module Design

**Status:** Spec — **fully supersedes `2026-05-18-compose-split-plan.md`**. The prior plan should not be implemented; this spec is the sole authoritative design and contains every resource, env, and verification detail an implementing agent needs.

**Goal:** Move all docker-compose orchestration concerns into a self-contained `compose/` module at the repo root. Establish clean separation between compose-level env (routing host, future template vars) and Dokploy-deployment-level env (API keys, backend creds). Terraform reads compose-level values directly from the module rather than carrying them as its own variables.

---

## Why this changes the prior plan

The prior split plan placed `docker-compose.yml`, `docker-compose.override.yml`, and a minimal root `.env` at the repo root, with `HOSTNAME_TLD` defined as a Terraform variable in the Dokploy module. Two problems surfaced during execution:

1. **Concern mixing at the root.** Compose orchestration files alongside Terraform modules, chezmoi sources, and dotfile utilities makes the root cluttered. The `linode/` module structure already demonstrates the cleaner peer-module pattern.
2. **`HOSTNAME_TLD` ownership is ambiguous.** It's a compose-template substitution variable, but it lived in the Dokploy module's `.env` because Terraform happened to need it. Compose locally and Terraform for prod read different sources of truth for the same conceptual value.

The compose-module design resolves both: one directory owns compose orchestration end-to-end, and Terraform reaches into it for the values it needs to render the template.

---

## Target File Layout

```
<repo root>/
├── compose/
│   ├── docker-compose.yml              # plain repo file; prod-shaped base
│   ├── docker-compose.override.yml     # plain repo file; local-only port mappings + network non-external flip
│   ├── .env                            # chezmoi-rendered; mode-shaped (local→localhost vals, prod→prod vals)
│   ├── .env.prod                       # chezmoi-rendered; always prod values regardless of laptop mode
│   └── .env.example                    # plain repo file; documents the variable shape
│
├── .secrets/                           # chezmoi source (existing submodule)
│   ├── .chezmoitemplates/
│   │   └── compose-env                 # shared partial; parameterized by target mode
│   └── compose/
│       ├── dot_env.tmpl                # → compose/.env;       calls partial with .mode
│       └── dot_env.prod.tmpl           # → compose/.env.prod;  calls partial with "production"
│
├── linode/environments/dokploy/
│   ├── main.tf                         # adds germanbrew/dotenv; reads ../../../compose/.env.prod
│   ├── variables.tf                    # HOSTNAME_TLD removed; only DOKPLOY_API_KEY remains
│   ├── outputs.tf                      # (per prior plan: compose_id, environment_id, project_id)
│   ├── backend.hcl                     # unchanged
│   ├── dokploy.sh                      # unchanged (still sources its own .env for TF_VAR_DOKPLOY_API_KEY + AWS creds)
│   └── .env                            # chezmoi-rendered; TF_VAR_HOSTNAME_TLD line removed
│
└── .env                                # unrelated (MODE={{ .mode }}); left alone
```

---

## Components

### `compose/` — orchestration module

Self-contained. The only directory anyone needs to look at for "how services are wired together for Docker."

- **`docker-compose.yml`** — prod-shaped service definitions with Traefik labels. Only `${HOSTNAME_TLD}` is substituted; all other label values are hardcoded prod values (inert metadata locally because there's no local Traefik).
- **`docker-compose.override.yml`** — adds `ports:` entries so each service is reachable at `http://localhost:<port>` locally; flips `dokploy-network` to non-external so Compose creates it on `docker compose up`.
- **`.env`** — chezmoi-rendered. Auto-loaded by `docker compose up` from inside the `compose/` directory. Values shaped by the laptop's chezmoi `.mode`: local-mode laptops get `HOSTNAME_TLD=docker.localhost`; production-mode machines get `HOSTNAME_TLD=symbionic.tech`. This is the file `docker compose` reads.
- **`.env.prod`** — chezmoi-rendered. Always contains production values regardless of laptop mode. **Not auto-loaded by Compose** and not used by `docker compose up`. Exists solely so Terraform has a stable, mode-independent source of prod compose-template values.
- **`.env.example`** — plain committed file documenting the variable shape (one entry per variable, no values). Reference material; not consumed by any tool.

### `.secrets/.chezmoitemplates/compose-env` — shared partial

Single source of truth for compose-level env variable definitions. Parameterized by target mode passed in by the caller.

```gotemplate
{{- /*
  Shared partial for compose-level env files. Caller passes the target
  mode ("local" or "production") as the data context.
  Add new compose-templated variables here; both .env and .env.prod
  pick them up automatically.
*/ -}}
{{- $mode := . -}}
HOSTNAME_TLD={{ if eq $mode "local" -}}
docker.localhost
{{- else if eq $mode "production" -}}
symbionic.tech
{{- else -}}
{{ fail (printf "compose-env: unknown mode %q" $mode) }}
{{- end }}
```

Failing on unknown modes is intentional — it prevents silent rendering of an empty value if a future mode (e.g., `testing`) is added without a case here.

### `.secrets/compose/dot_env.tmpl` — local-active file

```gotemplate
{{ template "compose-env" .mode -}}
```

Renders to `compose/.env`. Picks up whatever mode the laptop is configured for.

### `.secrets/compose/dot_env_prod.tmpl` — Terraform-source file

```gotemplate
{{ template "compose-env" "production" -}}
```

Renders to `compose/.env.prod`. Always production values; ignores laptop mode.

### `linode/environments/dokploy/main.tf` — Terraform integration

Adds `germanbrew/dotenv` as a provider. Reads `compose/.env.prod` via the provider's `dotenv` data source. Exposes values as a map.

```hcl
terraform {
  required_providers {
    dokploy = {
      source  = "j0bIT/dokploy"
      version = "0.3.0"
    }
    dotenv = {
      source  = "germanbrew/dotenv"
      version = "~> 1.2"
    }
  }
}

data "dotenv" "compose" {
  filename = "${path.root}/../../../compose/.env.prod"
}

locals {
  hostname_tld    = data.dotenv.compose.entries["HOSTNAME_TLD"]
  compose_content = templatefile("${path.root}/../../../compose/docker-compose.yml", {
    HOSTNAME_TLD = local.hostname_tld
  })
}

provider "dokploy" {
  host    = "https://vulcan.${local.hostname_tld}/api"
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

resource "dokploy_compose" "stack" {
  project_id           = dokploy_project.main.id
  environment_id       = dokploy_environment.production.id
  name                 = "stack"
  source_type          = "raw"
  compose_file_content = local.compose_content
  deploy_on_create     = true
}
```

`variables.tf` drops `variable "HOSTNAME_TLD"` entirely (only `DOKPLOY_API_KEY` remains). `dokploy.sh` is unchanged — still sources `linode/environments/dokploy/.env` for `TF_VAR_DOKPLOY_API_KEY` and AWS backend creds.

### `linode/environments/dokploy/outputs.tf` — full content after refactor

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

Removes `janus_application_id` from prior output set (the `dokploy_application.janus` resource is destroyed by this refactor).

---

## Data Flow

### Local dev — `docker compose up` from `compose/`

```
chezmoi (.mode="local") renders .secrets/compose/dot_env.tmpl
  → calls template "compose-env" "local"
  → emits HOSTNAME_TLD=docker.localhost
  → written to compose/.env
docker compose up (from compose/)
  → auto-loads compose/.env
  → auto-merges docker-compose.yml + docker-compose.override.yml
  → starts services with localhost-shaped labels (metadata-only) and localhost port mappings
```

### Prod deploy — `terraform apply` (from any-mode laptop)

```
chezmoi renders .secrets/compose/dot_env_prod.tmpl
  → calls template "compose-env" "production"
  → emits HOSTNAME_TLD=symbionic.tech
  → written to compose/.env.prod (always, regardless of laptop mode)
terraform apply (from linode/environments/dokploy/)
  → germanbrew/dotenv data source reads ../../../compose/.env.prod
  → exposes data.dotenv.compose.entries["HOSTNAME_TLD"]
  → templatefile() substitutes HOSTNAME_TLD into compose/docker-compose.yml content
  → result inlined as dokploy_compose.compose_file_content
Dokploy receives raw content
  → bundled Traefik reads labels and routes accordingly
```

Key property: the Terraform path is mode-independent. A local-mode laptop can `terraform apply` correctly because `.env.prod` is always production-shaped.

---

## Migration Plan (high-level — full step-by-step in the implementation plan)

| # | Action |
|---|---|
| 1 | Create `compose/` directory; move the existing rewritten `docker-compose.yml` and `docker-compose.override.yml` from repo root into it. |
| 2 | Write `compose/.env.example` documenting the variable shape. |
| 3 | Delete root `.env.example` (the manually-edited one from the prior plan). Restore root `.gitignore` for compose-style `.env` if anything changed. |
| 4 | Revert manual edit to root `.env` (the `HOSTNAME_TLD="docker.localhost"` line added during the paused execution); chezmoi remains the only authority for that file. |
| 5 | In `.secrets/`: create `.chezmoitemplates/compose-env`, `compose/dot_env.tmpl`, `compose/dot_env_prod.tmpl` with contents above. |
| 6 | `czm apply` — verify `compose/.env` and `compose/.env.prod` render correctly under current laptop mode. |
| 7 | Add `germanbrew/dotenv` provider to `linode/environments/dokploy/main.tf`; replace `var.HOSTNAME_TLD` references with `local.hostname_tld` sourced from the dotenv data source; point `templatefile()` at `compose/docker-compose.yml`. |
| 8 | Remove `variable "HOSTNAME_TLD"` from `linode/environments/dokploy/variables.tf`. |
| 9 | Edit `linode/environments/dokploy/.env` (via chezmoi source) to remove the `TF_VAR_HOSTNAME_TLD=symbionic.tech` line. Re-encrypt and `czm apply`. |
| 10 | `terraform init -upgrade` to pick up the new provider. `terraform validate` from inside the module. |
| 11 | Local smoke: from `compose/`, run `docker compose up -d`, hit `http://localhost:8080/`, verify whoami output. `docker compose down`. |
| 12 | Prod smoke (see "Prod smoke procedure" below — explicit user approval required before `terraform apply`). |

### Prod smoke procedure (migration step 12)

Gated: do not run any step in this section without explicit user approval. The `terraform apply` here destroys the existing `dokploy_application.janus` and `dokploy_domain.janus` resources and creates `dokploy_environment.production` + `dokploy_compose.stack` in their place.

1. **Plan and review** — from `linode/environments/dokploy/`:

   ```bash
   set -a; source .env; set +a
   terraform plan
   ```

   Expected diff: destroy `dokploy_application.janus` and `dokploy_domain.janus`; create `dokploy_environment.production` and `dokploy_compose.stack`; `dokploy_project.main` unchanged. Outputs: `janus_application_id` removed; `environment_id` and `compose_id` added. If anything beyond those changes appears, stop and investigate.

2. **Apply:**

   ```bash
   terraform apply -auto-approve
   ```

3. **Verify Dokploy received the stack** — open `https://vulcan.symbionic.tech`, log in, find the `symbionic-services` project, confirm `janus` shows `Running` in the `stack` compose. Or from a shell with SSH access:

   ```bash
   ssh -i linode/environments/production/id_ed25519 root@<instance-ip> 'docker stack ls'
   ```

   Expected: a Dokploy-managed stack named like `symbionic-services-stack-<hash>`.

4. **End-to-end external smoke:**

   ```bash
   curl -s https://janus.symbionic.tech/ | head -10
   ```

   Expected: traefik/whoami output (`Hostname:`, `IP:`, `Headers:`). First request post-deploy may take a few seconds while Let's Encrypt issues the cert. Retry after 30 s if the response is a TLS error or the Traefik default cert.

5. **HTTP-to-HTTPS redirect check:**

   ```bash
   curl -sI http://janus.symbionic.tech/
   ```

   Expected: `301` or `308` redirect to `https://janus.symbionic.tech/`.

6. **Chezmoi drift reconciliation** — the Stage 2 secrets file is chezmoi-managed and may show drift after the apply:

   ```bash
   czm diff
   ```

   If `linode/environments/dokploy/.env` shows changes, re-encrypt the source:

   ```bash
   source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt ./linode/environments/dokploy/.env
   ```

   No commit needed if no diff.

---

## Error Handling & Edge Cases

- **Unknown chezmoi mode** — the shared partial fails loudly via `{{ fail }}` rather than emitting an empty `HOSTNAME_TLD=` line. A missing/empty value would silently render the compose template with `Host(\`janus.\`)` — invalid Traefik rule — and the failure mode would only surface at deploy time. Better to fail at template-render time.
- **Adding a new compose-template variable** — edit `.chezmoitemplates/compose-env` only. Both `.env` and `.env.prod` pick it up automatically. Terraform reads it via `data.dotenv.compose.entries["NEW_VAR"]`.
- **`compose/.env.prod` missing at `terraform apply`** — the `dotenv` provider raises a file-not-found error. Cleanly diagnosed: re-run `czm apply` to render the file.
- **Future per-machine variation in local values** — if a developer needs `HOSTNAME_TLD=foo.local` instead of `docker.localhost`, add a chezmoi data variable (e.g., `.compose.local_hostname_tld`) and reference it from the partial's `local` branch. Mode-conditional structure already supports this; only the partial changes.
- **Future secrets in compose env** — rename the relevant template file with `encrypted_` prefix, re-encrypt via the existing `chezmoi-add-secret.sh` helper. No structural changes required.

---

## Testing

- **Render check** — after `czm apply`, `cat compose/.env` and `cat compose/.env.prod`. The first should reflect the laptop's mode; the second must always show production values.
- **Compose merge check** — from `compose/`, run `docker compose config` and verify the merged output substitutes `HOSTNAME_TLD` correctly and includes the override's port mappings.
- **Terraform validate** — from `linode/environments/dokploy/`, `terraform init -upgrade && terraform validate` should succeed.
- **Local end-to-end** — `docker compose up -d`, curl `localhost:8080`, expect whoami output. Inspect the running container's labels to confirm `${HOSTNAME_TLD}` substituted into `Host(\`janus.docker.localhost\`)`.
- **Prod end-to-end** — see the "Prod smoke procedure" section above (gated, explicit user approval required).

---

## Out of Scope

- Cleanup of the now-unused `traefik/` directory at repo root. Tracked separately; not part of this design.
- Per-service environment file handling. Services that need build-time or runtime secrets (e.g., a future Postgres password) introduce their own env files under their service directory. The compose module's env is strictly orchestration-level.
- Wrapper scripts or Makefile targets for running compose from the repo root. `cd compose/` is the convention; if friction becomes real, add tooling as a separate change.
- Migration of `dokploy.sh` patterns. The script keeps its current role of sourcing Terraform-specific env. If we later want plain `terraform apply` without the wrapper, that's a separate cleanup.

---

## Open Questions

None at spec-write time. Ready for plan generation.
