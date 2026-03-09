# Dokploy Stage 2: Server Configuration via Terraform

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create the Stage 2 Terraform environment (`linode/environments/dokploy/`) that uses the `j0bIT/dokploy` provider to configure Dokploy resources — projects, applications, domains, environment variables — and serve the Dokploy console on a custom subdomain (`dokploy.<HOSTNAME_TLD>`).

**Architecture:** This is the second stage of a two-stage Terraform pipeline. Stage 1 (`linode/environments/production/`) provisions the Linode instance, DNS, and cloud-init (which installs Dokploy and creates an API key). Stage 2 uses that API key to configure what runs *on* Dokploy via the `j0bIT/dokploy` provider (v0.3.0). The Dokploy instance ships its own Traefik that handles container routing and TLS — wildcard DNS (`*.<HOSTNAME_TLD>`) from Stage 1 means any `dokploy_domain` resource automatically resolves.

**Tech Stack:** Terraform, `j0bIT/dokploy` provider v0.3.0, Linode Object Storage (S3-compatible) for state backend

**Prerequisite:** The previous plan (`2026-03-09-dokploy-deploy-plan.md`) must be implemented first — Phase 1 bug fixes, deploy scripts, and the cloud-init API key automation are all dependencies for this plan.

---

## Provider Resource Reference

The `j0bIT/dokploy` provider (source: `j0bit/dokploy`) exposes these resources:

| Resource | Purpose |
|---|---|
| `dokploy_project` | Logical grouping of apps/databases |
| `dokploy_environment` | Sub-environment within a project |
| `dokploy_application` | Docker or git-based app deployment |
| `dokploy_compose` | Docker Compose stack deployment |
| `dokploy_database` | Managed database (postgres, mysql, etc.) |
| `dokploy_domain` | Domain routing + TLS for an app or compose service |
| `dokploy_environment_variables` | App/compose-level env vars |
| `dokploy_project_environment_variables` | Project-level env vars |
| `dokploy_port` | Application port binding |
| `dokploy_ssh_key` | SSH key for private git repos |
| `dokploy_traefik_config` | Global Traefik configuration |
| `dokploy_backup_destination` | S3 backup destination |
| `dokploy_volume_backup` | Scheduled volume backups |

Provider config requires `host` (e.g. `https://dokploy.example.com/api`) and `api_key` (sensitive).

No data sources are available — all state must come from resource outputs or variables.

---

## Task 1: Create Dokploy Environment Scaffold

**Files:**
- Create: `linode/environments/dokploy/main.tf`
- Create: `linode/environments/dokploy/variables.tf`
- Create: `linode/environments/dokploy/outputs.tf`
- Create: `linode/environments/dokploy/backend.hcl`
- Create: `linode/environments/dokploy/.env.example`

### Step 1: Create `variables.tf`

All variables needed for the dokploy stage. These are populated via `.env` (created by `deploy-production.sh` from the previous plan).

```hcl
# linode/environments/dokploy/variables.tf

variable "DOKPLOY_HOST" {
  type        = string
  nullable    = false
  description = "Dokploy API base URL (e.g. https://dokploy.example.com/api)"
}

variable "DOKPLOY_API_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Dokploy API key created during cloud-init bootstrap"
}

variable "HOSTNAME_TLD" {
  type        = string
  nullable    = false
  description = "The hostname.tld used for subdomain routing (e.g. example.com)"
}
```

### Step 2: Create `backend.hcl`

Same S3 bucket as production, different state key.

```hcl
# linode/environments/dokploy/backend.hcl

backend "s3" {
    endpoint                    = "us-ord-1.linodeobjects.com"
    bucket                      = "symbionic-tech-terraform-state"
    key                         = "dokploy.tfstate"
    region                      = "us-ord"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    encrypt                     = true
}
```

**Note:** The `endpoint`, `bucket`, and `region` values here must match what `bootstrap.sh` created. These are currently hardcoded to match the production `backend.hcl`. If the bootstrap output values differ from what's shown, update accordingly. The S3 credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`) are loaded from the `.env` file by `scripts/tf.sh`.

### Step 3: Create `main.tf` with provider and project

Start with the provider block, the project, and a whoami smoke-test app with its domain. The Dokploy console domain is configured here too.

```hcl
# linode/environments/dokploy/main.tf

terraform {
  required_providers {
    dokploy = {
      source  = "j0bit/dokploy"
      version = "0.3.0"
    }
  }
}

provider "dokploy" {
  host    = var.DOKPLOY_HOST
  api_key = var.DOKPLOY_API_KEY
}

# --- Dokploy Console Domain ---
# Serve the Dokploy dashboard at dokploy.<HOSTNAME_TLD> instead of <ip>:3000.
# This uses dokploy_traefik_config to add a Traefik router that forwards
# the subdomain to Dokploy's own web server on port 3000.
#
# The web_server scope configures Dokploy's "Web Server" Traefik settings,
# which control how the Dokploy UI itself is exposed (separate from
# application routing handled by the "main" scope).
resource "dokploy_traefik_config" "console" {
  scope          = "web_server"
  reload_on_apply = true

  config = yamlencode({
    entryPoints = {
      websecure = {
        address = ":443"
        http = {
          tls = {
            certResolver = "letsencrypt"
          }
        }
      }
    }
    http = {
      routers = {
        "dokploy-console" = {
          rule        = "Host(`dokploy.${var.HOSTNAME_TLD}`)"
          entryPoints = ["websecure"]
          service     = "dokploy-console"
          tls = {
            certResolver = "letsencrypt"
          }
        }
      }
      services = {
        "dokploy-console" = {
          loadBalancer = {
            servers = [{ url = "http://127.0.0.1:3000" }]
          }
        }
      }
    }
  })
}

# --- Project ---
resource "dokploy_project" "main" {
  name        = "symbionic-services"
  description = "Production services managed by Terraform"
}

# --- Smoke Test: whoami ---
resource "dokploy_application" "whoami" {
  name           = "whoami"
  project_id     = dokploy_project.main.id
  source_type    = "docker"
  repository_url = "traefik/whoami"
  deploy_on_create = true
}

resource "dokploy_domain" "whoami" {
  application_id       = dokploy_application.whoami.id
  host                 = "whoami.${var.HOSTNAME_TLD}"
  https                = true
  certificate_provider = "letsencrypt"
  port                 = 80
  path                 = "/"
  redeploy_on_update   = true
}
```

**Important note on the Dokploy console domain:** The `dokploy_traefik_config` resource with `scope = "web_server"` configures Traefik's routing for the Dokploy UI itself. This is the mechanism Dokploy provides for serving the dashboard on a custom domain with TLS. Verify during implementation that:
1. The `web_server` scope accepts the entryPoints + router + service config format shown above.
2. Dokploy's built-in Traefik has a `letsencrypt` cert resolver pre-configured (it should — Dokploy sets this up during installation).
3. If the above Traefik config format doesn't work, an alternative is to configure this directly in Dokploy's UI settings and then import the state, or use the Dokploy MCP server's settings endpoints to set the server domain.

### Step 4: Create `outputs.tf`

```hcl
# linode/environments/dokploy/outputs.tf

output "project_id" {
  value       = dokploy_project.main.id
  description = "ID of the main Dokploy project"
}

output "whoami_app_id" {
  value       = dokploy_application.whoami.id
  description = "ID of the whoami smoke-test application"
}

output "console_url" {
  value       = "https://dokploy.${var.HOSTNAME_TLD}"
  description = "URL of the Dokploy console"
}
```

### Step 5: Create `.env.example`

```bash
# linode/environments/dokploy/.env.example
# These are populated automatically by scripts/deploy-production.sh

TF_VAR_DOKPLOY_HOST=https://dokploy.example.com/api
TF_VAR_DOKPLOY_API_KEY=<retrieved-from-cloud-init>
TF_VAR_HOSTNAME_TLD=example.com

# S3 state backend credentials (from bootstrap)
AWS_ACCESS_KEY_ID=<from-bootstrap>
AWS_SECRET_ACCESS_KEY=<from-bootstrap>
```

### Step 6: Verify the scaffold

Run: `cd linode/environments/dokploy && terraform init -backend=false && terraform validate`

Expected: `Success! The configuration is valid.`

This validates syntax without needing real credentials or backend. The `-backend=false` flag skips S3 backend initialization.

### Step 7: Commit

```bash
git add linode/environments/dokploy/
git commit -m "feat: add dokploy stage 2 terraform scaffold

Provider config, project, whoami smoke-test app with domain,
and Dokploy console domain via traefik_config web_server scope."
```

---

## Task 2: Update `deploy-production.sh` for Console Domain

The `deploy-production.sh` script from the previous plan builds the dokploy `.env`. The `DOKPLOY_HOST` variable needs to point to the API endpoint. Before the console domain is configured, the API is at `http://<IP>:3000/api`. After Stage 2 applies the Traefik config, it becomes `https://dokploy.<HOSTNAME_TLD>/api`.

**Files:**
- Modify: `scripts/deploy-production.sh`

### Step 1: Update the .env generation in deploy-production.sh

The host should use the IP initially (since the Traefik config hasn't been applied yet). After Stage 2 runs, subsequent runs can use the domain. Use the IP-based URL for the initial `.env`:

Find and replace the `.env` generation block in `scripts/deploy-production.sh`:

```bash
# Replace this line:
TF_VAR_DOKPLOY_HOST=https://${TF_VAR_HOSTNAME_TLD}:3000

# With:
TF_VAR_DOKPLOY_HOST=http://${INSTANCE_IP}:3000/api
```

The provider `host` field requires the `/api` suffix (per the provider docs: `https://dokploy.example.com/api`). The initial connection uses HTTP + IP since TLS isn't configured until Stage 2 runs.

### Step 2: Commit

```bash
git add scripts/deploy-production.sh
git commit -m "fix: use IP-based URL with /api suffix for initial dokploy host"
```

---

## Task 3: Validate Full Pipeline (Manual)

This task is manual verification after deploying.

### Step 1: Run Stage 1

```bash
bash scripts/deploy-production.sh
```

This provisions the Linode, waits for cloud-init, retrieves the API key, and builds `linode/environments/dokploy/.env`.

### Step 2: Run Stage 2

```bash
bash scripts/tf.sh plan linode/environments/dokploy
```

Review the plan output. It should show creation of:
- `dokploy_traefik_config.console`
- `dokploy_project.main`
- `dokploy_application.whoami`
- `dokploy_domain.whoami`

Then apply:

```bash
bash scripts/tf.sh apply linode/environments/dokploy
```

### Step 3: Verify the whoami app

```bash
curl -sf https://whoami.<HOSTNAME_TLD>
```

Expected: whoami response showing headers/request info.

### Step 4: Verify the Dokploy console domain

```bash
curl -sf https://dokploy.<HOSTNAME_TLD>
```

Expected: HTML response from the Dokploy dashboard.

### Step 5: Update `.env` to use domain-based URL

Now that the console domain is live, update `linode/environments/dokploy/.env`:

```bash
TF_VAR_DOKPLOY_HOST=https://dokploy.<HOSTNAME_TLD>/api
```

Run `bash scripts/tf.sh plan linode/environments/dokploy` — should show no changes (the host is just the provider config, not a resource attribute).

### Step 6: Commit the updated .env handling

If the domain-based URL works, update `deploy-production.sh` to include a post-Stage-2 step that switches the URL, or document the manual step in the README.

---

## Task 4: Add Service Template Pattern to README

**Files:**
- Modify: `linode/README.md`

### Step 1: Add a "Adding a New Service" section

Document the pattern for adding new services to Dokploy via Terraform. This is the primary workflow going forward.

Add to `linode/README.md`:

```markdown
## Adding a New Service to Dokploy

All services are defined in `linode/environments/dokploy/main.tf`. To add a new
service:

1. Add a `dokploy_application` resource:

   ```hcl
   resource "dokploy_application" "my_app" {
     name             = "my-app"
     project_id       = dokploy_project.main.id
     source_type      = "docker"        # or "github", "git"
     repository_url   = "my-image:tag"  # for docker source_type
     deploy_on_create = true
   }
   ```

2. Add a `dokploy_domain` resource for subdomain routing:

   ```hcl
   resource "dokploy_domain" "my_app" {
     application_id       = dokploy_application.my_app.id
     host                 = "my-app.${var.HOSTNAME_TLD}"
     https                = true
     certificate_provider = "letsencrypt"
     port                 = 8080  # container's listening port
     path                 = "/"
     redeploy_on_update   = true
   }
   ```

3. (Optional) Add environment variables:

   ```hcl
   resource "dokploy_environment_variables" "my_app" {
     application_id = dokploy_application.my_app.id
     variables = {
       DATABASE_URL = "postgres://..."
       LOG_LEVEL    = "info"
     }
   }
   ```

4. Apply: `bash scripts/tf.sh apply linode/environments/dokploy`

5. Verify: `curl https://my-app.<HOSTNAME_TLD>`

### Available Resource Types

| Resource | Use For |
|---|---|
| `dokploy_application` | Single-container apps (Docker image or git repo) |
| `dokploy_compose` | Multi-container stacks via docker-compose |
| `dokploy_database` | Managed databases (postgres, mysql) |
| `dokploy_domain` | Subdomain + TLS routing |
| `dokploy_environment_variables` | App-level env vars |
| `dokploy_project_environment_variables` | Project-wide env vars |
| `dokploy_port` | Custom port bindings |
| `dokploy_ssh_key` | SSH keys for private git repos |
| `dokploy_backup_destination` | S3 backup targets |
| `dokploy_volume_backup` | Scheduled volume backups |
| `dokploy_traefik_config` | Global Traefik settings |

### Dokploy Console

The Dokploy dashboard is available at `https://dokploy.<HOSTNAME_TLD>`,
configured via `dokploy_traefik_config.console` in `main.tf`.
```

### Step 2: Commit

```bash
git add linode/README.md
git commit -m "docs: add service template pattern and resource reference to README"
```

---

## Files Summary

| Action | File |
|---|---|
| **Create** | `linode/environments/dokploy/main.tf` |
| **Create** | `linode/environments/dokploy/variables.tf` |
| **Create** | `linode/environments/dokploy/outputs.tf` |
| **Create** | `linode/environments/dokploy/backend.hcl` |
| **Create** | `linode/environments/dokploy/.env.example` |
| **Modify** | `scripts/deploy-production.sh` (fix DOKPLOY_HOST URL) |
| **Modify** | `linode/README.md` (service template docs) |

---

## Verification Checklist

1. `terraform validate` passes in `linode/environments/dokploy/`
2. `terraform init -backend-config=backend.hcl` succeeds with S3 credentials
3. `terraform plan` shows expected resources (traefik_config, project, app, domain)
4. `terraform apply` creates all resources without errors
5. `curl https://whoami.<HOSTNAME_TLD>` returns whoami response
6. `https://dokploy.<HOSTNAME_TLD>` loads the Dokploy dashboard with valid TLS
7. Subsequent `terraform plan` shows no changes (idempotent)

---

## Open Questions / Risks

1. **`dokploy_traefik_config` web_server scope behavior:** The `web_server` scope is documented but the exact config format Dokploy expects may differ from standard Traefik YAML. If the Traefik config shown above doesn't work, alternatives:
   - Use the Dokploy MCP server (`mcp__dokploy-mcp__*`) to inspect/configure the server domain via Dokploy's settings API
   - Configure the console domain manually in the Dokploy UI, then `terraform import` the state
   - Check Dokploy's source code for how `web_server` Traefik config is applied

2. **`source_type = "docker"` for whoami:** The provider docs don't show an example with `source_type = "docker"`. The sandbox example uses `custom_git_url`. Verify that `source_type = "docker"` with `repository_url = "traefik/whoami"` works. If not, use `source_type = "git"` with the whoami GitHub repo, or deploy via a compose stack.

3. **Cert resolver name:** Dokploy's built-in cert resolver may not be named `letsencrypt`. Check Dokploy's Traefik config after installation to confirm the resolver name. It might be `le` or something else.

4. **Initial chicken-and-egg:** The first `terraform apply` connects via `http://<IP>:3000/api`. The Traefik config it applies should make `https://dokploy.<HOSTNAME_TLD>` work. But subsequent runs should use the domain URL. This transition is documented in Task 3, Step 5.
