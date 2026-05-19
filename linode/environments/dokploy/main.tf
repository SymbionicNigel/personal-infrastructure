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

  # Backend configuration is supplied at init time via
  # `terraform init -backend-config=backend.hcl` (see dokploy.sh).
  backend "s3" {}
}

data "dotenv" "compose" {
  filename = "${path.root}/../../../compose/.env.prod"
}

locals {
  hostname_tld = data.dotenv.compose.entries["HOSTNAME_TLD"]
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

# dokploy_compose requires an environment_id explicitly. Dokploy reserves
# the name "production" for the auto-created per-project environment, so
# this Terraform-managed env uses a different name.
resource "dokploy_environment" "stack" {
  project_id  = dokploy_project.main.id
  name        = "stack"
  description = "Environment owning the Terraform-managed compose stack"
}

resource "dokploy_compose" "stack" {
  project_id           = dokploy_project.main.id
  environment_id       = dokploy_environment.stack.id
  name                 = "main-application-stack"
  source_type          = "raw"
  compose_file_content = local.compose_content
  deploy_on_create     = true
}
