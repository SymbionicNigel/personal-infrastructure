terraform {
  required_providers {
    dokploy = {
      source  = "j0bIT/dokploy"
      version = "0.4.0"
    }
    dotenv = {
      source  = "germanbrew/dotenv"
      version = "~> 1.2"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }

  # Backend configuration is supplied at init time via
  # `terraform init -backend-config=backend.hcl` (see dokploy.sh).
  backend "s3" {}
}

# Compose-level env (hostname, image tags, GHCR owner). Substituted
# into the rendered compose YAML via templatefile().
data "dotenv" "compose" {
  filename = "${path.root}/../../../compose/.env.prod"
}

# Per-service env files, rendered by chezmoi from the per-service
# partials in .secrets/.chezmoitemplates/. Their entries are merged
# into compose_env and pushed to Dokploy's compose-scoped environment
# (consumed at deploy time via compose's ${VAR} substitution).
# See docs/guides/env-wiring.md.
data "dotenv" "postgres" {
  filename = "${path.root}/../../../compose/.env.postgres.prod"
}
data "dotenv" "postgres_roles" {
  filename = "${path.root}/../../../compose/.env.postgres.roles.prod"
}
data "dotenv" "astarte" {
  filename = "${path.root}/../../../compose/.env.astarte.prod"
}
# No iris_typegen here: the typegen DSN is operator/CI-only and never
# pushed to Dokploy (iris has no runtime DB consumer).

locals {
  hostname_tld = data.dotenv.compose.entries["HOSTNAME_TLD"]
  ghcr_owner   = var.GHCR_OWNER
  compose_content = templatefile("${path.root}/../../../compose/docker-compose.yml", {
    HOSTNAME_TLD                     = local.hostname_tld
    GHCR_OWNER                       = local.ghcr_owner
    ASTARTE_IMAGE_TAG                = var.ASTARTE_IMAGE_TAG
    IRIS_IMAGE_TAG                   = var.IRIS_IMAGE_TAG
    TIMESCALE_BOOTSTRAPPED_IMAGE_TAG = var.TIMESCALE_BOOTSTRAPPED_IMAGE_TAG
  })

  # Aggregated env pushed to Dokploy's compose-scoped environment.
  # Key collisions resolve last-source-wins; postgres.entries owns
  # POSTGRES_DB/USER/PASSWORD (superuser), postgres_roles owns the
  # per-role passwords, astarte owns its connection creds. iris_typegen
  # is operator-side only and is intentionally NOT included here — the
  # iris container doesn't read it.
  compose_env = merge(
    data.dotenv.postgres.entries,
    data.dotenv.postgres_roles.entries,
    data.dotenv.astarte.entries,
  )

  # Number of services declared in the rendered compose YAML. Drives
  # the count check in verify-deploy.sh — auto-updates when a new
  # service block is added.
  compose_service_count = length(yamldecode(local.compose_content).services)

  # Dokploy API base. Single source so a future subdomain move is one edit.
  dokploy_api_base = "https://vulcan.${local.hostname_tld}/api"
}

provider "dokploy" {
  host    = local.dokploy_api_base
  api_key = var.DOKPLOY_API_KEY
}

resource "dokploy_project" "main" {
  name        = var.DOKPLOY_PROJECT_NAME
  description = "Primary services managed by Terraform"
}

data "http" "project_one" {
  # tRPC HTTP GET expects input as a urlencoded superjson envelope.
  url    = "${local.dokploy_api_base}/trpc/project.one?input=${urlencode(jsonencode({ json = { projectId = dokploy_project.main.id } }))}"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.DOKPLOY_API_KEY
    "Content-Type" = "application/json"
  }

  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "project.one returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  # Response is wrapped by the superjson transformer: result.data.json.<payload>
  project_envs = jsondecode(data.http.project_one.response_body).result.data.json.environments
  production_env_id = one([
    for env in local.project_envs : env.environmentId if env.name == "production"
  ])
}

resource "dokploy_compose" "stack" {
  project_id           = dokploy_project.main.id
  environment_id       = local.production_env_id
  name                 = "main-application-stack"
  source_type          = "raw"
  compose_file_content = local.compose_content
  deploy_on_create     = false
  # Provider 0.4.0 forces a null value to false mid-apply (resource_compose.go
  # Create/Update), tripping "inconsistent result after apply". Set it
  # explicitly so plan and apply agree.
  delete_volumes_on_destroy = false
}

# Push the aggregated per-service env to Dokploy's compose-scoped
# environment. Provider 0.4.0 has no `env` attribute on dokploy_compose,
# so we hit the tRPC endpoint directly. `compose.saveEnvironment` is the
# dedicated endpoint for env-only updates ({composeId, env}); using the
# generic `compose.update` here would null out other compose fields
# because it expects the full apiUpdateCompose payload.
# Keying triggers_replace on the env hash means any partial change re-pushes.
resource "terraform_data" "compose_env" {
  triggers_replace = sha256(jsonencode(local.compose_env))

  provisioner "local-exec" {
    environment = {
      DOKPLOY_API_KEY = var.DOKPLOY_API_KEY
      COMPOSE_ID      = dokploy_compose.stack.id
      ENV_CONTENT     = join("\n", [for k, v in local.compose_env : "${k}=${v}"])
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      body=$(python3 -c 'import json,os;print(json.dumps({"composeId":os.environ["COMPOSE_ID"],"env":os.environ["ENV_CONTENT"]}))')
      curl -sf -X POST "${local.dokploy_api_base}/compose.saveEnvironment" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        --data "$body" >/dev/null
      echo "compose env pushed (${length(local.compose_env)} keys)"
    EOT
  }

  depends_on = [dokploy_compose.stack]
}

# The provider's Update saves the compose but never redeploys, so a bumped image
# tag or env change wouldn't roll out. Replicate its deploy call whenever the
# rendered content OR the pushed env changes -- keyed on a combined hash.
resource "terraform_data" "redeploy" {
  triggers_replace = sha256("${local.compose_content}\n${jsonencode(local.compose_env)}")

  provisioner "local-exec" {
    environment = {
      DOKPLOY_API_KEY = var.DOKPLOY_API_KEY
    }
    command = <<-EOT
      curl -sf -X POST "${local.dokploy_api_base}/compose.deploy" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        --data '{"composeId":"${dokploy_compose.stack.id}"}'
    EOT
  }

  depends_on = [dokploy_compose.stack, terraform_data.compose_env, terraform_data.ghcr_registry]
}

# Dokploy's compose deploy queues `docker compose up -d --build`, which
# returns when containers START -- not when healthy. A fail-closed
# container (reconcile error, astarte migration error) crashloops
# behind a green deploy status. verify-deploy.sh closes that gap by
# polling Dokploy's docker.getContainersByAppLabel after redeploy and
# requiring every expected service to hold "running" state for a few
# consecutive samples. Failure here fails the apply, making "deploy
# success" mean what it says.
#
# Keyed on the same trigger as redeploy so the verify runs exactly
# once per deploy attempt.
resource "terraform_data" "deploy_verify" {
  triggers_replace = terraform_data.redeploy.triggers_replace

  provisioner "local-exec" {
    environment = {
      COMPOSE_ID             = dokploy_compose.stack.id
      DOKPLOY_API_BASE       = local.dokploy_api_base
      DOKPLOY_API_KEY        = var.DOKPLOY_API_KEY
      EXPECTED_SERVICE_COUNT = tostring(local.compose_service_count)
    }
    command = "${path.module}/verify-deploy.sh"
  }

  depends_on = [terraform_data.redeploy]
}

# Shared S3 destination for Dokploy's native backups. Credentials are the
# infra-backups bucket key surfaced by the production env (dokploy_backups_*
# outputs), supplied via the chezmoi-managed .env as TF_VAR_DOKPLOY_BACKUP_*.
resource "dokploy_backup_destination" "linode" {
  name              = "linode-object-storage"
  bucket            = var.DOKPLOY_BACKUP_BUCKET
  endpoint          = var.DOKPLOY_BACKUP_ENDPOINT
  region            = var.DOKPLOY_BACKUP_REGION
  access_key_id     = var.DOKPLOY_BACKUP_ACCESS_KEY_ID
  secret_access_key = var.DOKPLOY_BACKUP_SECRET_ACCESS_KEY
}

# Native control-plane backup: dumps the dokploy-postgres DB + /etc/dokploy to
# the shared destination nightly.
module "control_plane_backup" {
  source = "../../modules/dokploy-scheduled-backup"

  api_base       = local.dokploy_api_base
  api_key        = var.DOKPLOY_API_KEY
  destination_id = dokploy_backup_destination.linode.id
  database_type  = "web-server"
  database       = "dokploy"
  prefix         = "control-plane/"
  schedule       = "0 4 * * *" # daily 04:00 UTC; offset from Pelican's 03:00
}

# Application Postgres backup: pg_dump of the compose `postgres` service to the
# shared destination nightly. composeId + serviceName tell Dokploy to exec
# pg_dump inside the running container (works fully with Timescale hypertables).
module "app_db_backup" {
  source = "../../modules/dokploy-scheduled-backup"

  api_base       = local.dokploy_api_base
  api_key        = var.DOKPLOY_API_KEY
  destination_id = dokploy_backup_destination.linode.id
  database_type  = "postgres"
  database       = data.dotenv.postgres.entries["POSTGRES_DB"]
  prefix         = "app-postgres/"
  schedule       = "0 3 * * *" # daily 03:00 UTC; offset from control-plane's 04:00
  extra_payload_json = jsonencode({
    composeId   = dokploy_compose.stack.id
    serviceName = "postgres"
  })
}

# Bound access.log growth via Dokploy's built-in cleanup (daily 00:00 UTC).
resource "terraform_data" "log_cleanup" {
  triggers_replace = "0 0 * * *"

  provisioner "local-exec" {
    environment = { DOKPLOY_API_KEY = var.DOKPLOY_API_KEY }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      curl -sf -X POST "${local.dokploy_api_base}/settings.updateLogCleanup" \
        -H "x-api-key: $DOKPLOY_API_KEY" -H "Content-Type: application/json" \
        --data '{"cronExpression":"0 0 * * *"}' >/dev/null
      echo "log-cleanup cron set"
    EOT
  }
}

# Read existing registries so we update-in-place (re-login) rather than create a
# duplicate — registry.create has no upsert and no name uniqueness.
data "http" "registries" {
  url    = "${local.dokploy_api_base}/trpc/registry.all"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.DOKPLOY_API_KEY
    "Content-Type" = "application/json"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "registry.all returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  ghcr_registry_url  = "ghcr.io"
  ghcr_registry_name = "ghcr"
  ghcr_registry_id = try(one([
    for r in jsondecode(data.http.registries.response_body).result.data.json :
    r.registryId if r.registryUrl == local.ghcr_registry_url
  ]), null)
}

# Create-or-update the ghcr registry. Either path runs `docker login ghcr.io` on
# the host (Dokploy sets registryType=cloud → execAsync). triggers_replace on the
# cred hash means a PAT rotation re-runs the login, preserving today's behaviour.
resource "terraform_data" "ghcr_registry" {
  triggers_replace = sha256(join("|", [var.GHCR_OWNER, var.GHCR_PAT]))

  provisioner "local-exec" {
    environment = {
      DOKPLOY_API_KEY = var.DOKPLOY_API_KEY
      GHCR_USER       = var.GHCR_OWNER
      GHCR_PAT        = var.GHCR_PAT
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      base="${local.dokploy_api_base}"
      common=$(python3 -c 'import json,os;print(json.dumps({"registryName":"${local.ghcr_registry_name}","username":os.environ["GHCR_USER"],"password":os.environ["GHCR_PAT"],"registryUrl":"ghcr.io","registryType":"cloud","imagePrefix":None}))')
      rid='${local.ghcr_registry_id == null ? "" : local.ghcr_registry_id}'
      if [ -n "$rid" ]; then
        body=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["registryId"]=sys.argv[2]; print(json.dumps(d))' "$common" "$rid")
        curl -sf -X POST "$base/registry.update" -H "x-api-key: $DOKPLOY_API_KEY" \
          -H "Content-Type: application/json" --data "$body" >/dev/null
        echo "ghcr registry updated (host re-logged in)"
      else
        curl -sf -X POST "$base/registry.create" -H "x-api-key: $DOKPLOY_API_KEY" \
          -H "Content-Type: application/json" --data "$common" >/dev/null
        echo "ghcr registry created (host logged in)"
      fi
    EOT
  }
}
