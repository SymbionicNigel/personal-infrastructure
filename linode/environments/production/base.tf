terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.4.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

locals {
  TAGS = [var.HOSTNAME_TLD, "production"]
}

provider "linode" {
  token = var.LINODE_TOKEN
}

# TODO: handle restricting network access/VPC

module "dokploy-instance" {
  source = "../../modules/dokploy"

  region                 = var.REGION
  HOSTNAME_TLD           = var.HOSTNAME_TLD
  TAGS                   = local.TAGS
  DOKPLOY_ADMIN_EMAIL    = var.DOKPLOY_ADMIN_EMAIL
  DOKPLOY_ADMIN_PASSWORD = var.DOKPLOY_ADMIN_PASSWORD
  DOKPLOY_VERSION        = var.DOKPLOY_VERSION
}

module "domain" {
  source = "../../modules/domain"

  EMAIL_ADDRESS       = var.EMAIL_ADDRESS
  HOSTNAME_TLD        = var.HOSTNAME_TLD
  WEBSITE_INSTANCE_IP = module.dokploy-instance.instance_ip
  TAGS                = local.TAGS
}

# Bind the Dokploy dashboard to <DASHBOARD_SUBDOMAIN>.<HOSTNAME_TLD> over HTTPS.
# Runs only after the wildcard A record exists so Traefik's first ACME HTTP-01
# challenge can succeed without retry. The Dokploy admin API is loopback-only,
# so the call is issued from inside the host over SSH using the API key
# materialized by user_data.sh at /root/.dokploy-api-key.
resource "null_resource" "bind_dokploy_domain" {
  depends_on = [module.dokploy-instance, module.domain]

  triggers = {
    instance_ip = module.dokploy-instance.instance_ip
    host        = "${var.DASHBOARD_SUBDOMAIN}.${var.HOSTNAME_TLD}"
    email       = var.EMAIL_ADDRESS
  }

  connection {
    type        = "ssh"
    host        = module.dokploy-instance.instance_ip
    user        = "root"
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/root/.dokploy-bind-domain.json"
    content = jsonencode({
      json = {
        host             = "${var.DASHBOARD_SUBDOMAIN}.${var.HOSTNAME_TLD}"
        https            = true
        certificateType  = "letsencrypt"
        letsEncryptEmail = var.EMAIL_ADDRESS
      }
    })
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -eu
      test -s /root/.dokploy-api-key
      API_KEY=$(cat /root/.dokploy-api-key)
      curl -sf -X POST http://localhost:3000/api/trpc/settings.assignDomainServer \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/root/.dokploy-bind-domain.json
      rm -f /root/.dokploy-bind-domain.json
      EOT
    ]
  }
}

# TODO: Add a GitLab/GitHub provider resource to manage the chezmoi generic package artifact in the self-hosted GitLab instance (enki).
# TODO: When creating the build runner instance, ensure its cloud-init/user_data script is configured to pull the chezmoi artifact from the self-hosted GitLab package registry.
