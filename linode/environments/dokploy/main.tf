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

resource "dokploy_application" "janus" {
  project_id = dokploy_project.main.id
  name       = "janus"
  app_name   = "janus"

  source_type  = "docker"
  docker_image = "traefik/whoami:latest"
}

resource "dokploy_domain" "janus" {
  application_id   = dokploy_application.janus.id
  host             = "janus.${var.HOSTNAME_TLD}"
  https            = true
  certificate_type = "letsencrypt"
  port             = 80
  path             = "/"
}
