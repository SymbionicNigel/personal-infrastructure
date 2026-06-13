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

  depends_on = [dokploy_compose.stack]
}
