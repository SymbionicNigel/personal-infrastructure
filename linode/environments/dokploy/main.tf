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

data "dotenv" "compose" {
  filename = "${path.root}/../../../compose/.env.prod"
}

locals {
  hostname_tld = data.dotenv.compose.entries["HOSTNAME_TLD"]
  ghcr_owner   = var.GHCR_OWNER
  compose_content = templatefile("${path.root}/../../../compose/docker-compose.yml", {
    HOSTNAME_TLD      = local.hostname_tld
    GHCR_OWNER        = local.ghcr_owner
    ASTARTE_IMAGE_TAG = var.ASTARTE_IMAGE_TAG
    IRIS_IMAGE_TAG    = var.IRIS_IMAGE_TAG
  })
}

provider "dokploy" {
  host    = "https://vulcan.${local.hostname_tld}/api"
  api_key = var.DOKPLOY_API_KEY
}

resource "dokploy_project" "main" {
  name        = var.DOKPLOY_PROJECT_NAME
  description = "Primary services managed by Terraform"
}

data "http" "project_one" {
  # tRPC HTTP GET expects input as a urlencoded superjson envelope.
  url    = "https://vulcan.${local.hostname_tld}/api/trpc/project.one?input=${urlencode(jsonencode({ json = { projectId = dokploy_project.main.id } }))}"
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
}

# The provider's Update saves the compose but never redeploys, so a bumped image
# tag wouldn't roll out. Replicate its deploy call whenever the rendered content
# changes -- keyed on a content hash (not the raw compose) for a clean trigger.
resource "terraform_data" "redeploy" {
  triggers_replace = sha256(local.compose_content)

  provisioner "local-exec" {
    environment = {
      DOKPLOY_API_KEY = var.DOKPLOY_API_KEY
    }
    command = <<-EOT
      curl -sf -X POST "https://vulcan.${local.hostname_tld}/api/compose.deploy" \
        -H "Content-Type: application/json" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        --data '{"composeId":"${dokploy_compose.stack.id}"}'
    EOT
  }

  depends_on = [dokploy_compose.stack, terraform_data.ghcr_registry]
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
# the shared destination nightly. Replaces the dokploy-postgres-backup module.
module "control_plane_backup" {
  source = "../../modules/dokploy-scheduled-backup"

  api_base       = "https://vulcan.${local.hostname_tld}/api"
  api_key        = var.DOKPLOY_API_KEY
  destination_id = dokploy_backup_destination.linode.id
  database_type  = "web-server"
  database       = "dokploy"
  prefix         = "control-plane/"
  schedule       = "0 4 * * *" # daily 04:00 UTC; offset from Pelican's 03:00
}

# Bound access.log growth via Dokploy's built-in cleanup (daily 00:00 UTC).
resource "terraform_data" "log_cleanup" {
  triggers_replace = "0 0 * * *"

  provisioner "local-exec" {
    environment = { DOKPLOY_API_KEY = var.DOKPLOY_API_KEY }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      curl -sf -X POST "https://vulcan.${local.hostname_tld}/api/settings.updateLogCleanup" \
        -H "x-api-key: $DOKPLOY_API_KEY" -H "Content-Type: application/json" \
        --data '{"cronExpression":"0 0 * * *"}' >/dev/null
      echo "log-cleanup cron set"
    EOT
  }
}

# Read existing registries so we update-in-place (re-login) rather than create a
# duplicate — registry.create has no upsert and no name uniqueness.
data "http" "registries" {
  url    = "https://vulcan.${local.hostname_tld}/api/trpc/registry.all"
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
      base="https://vulcan.${local.hostname_tld}/api"
      common=$(python3 -c 'import json,os;print(json.dumps({"registryName":"${local.ghcr_registry_name}","username":os.environ["GHCR_USER"],"password":os.environ["GHCR_PAT"],"registryUrl":"ghcr.io","registryType":"cloud"}))')
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
