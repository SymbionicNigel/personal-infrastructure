terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "s3" {}
}

locals {
  TAGS            = [var.HOSTNAME_TLD, "production"]
  resource_prefix = replace(var.HOSTNAME_TLD, ".", "-")
}

provider "linode" {
  token = var.LINODE_TOKEN
  # Mint ephemeral Object Storage credentials from the API token for each apply.
  # Needed so resources like linode_object_storage_bucket.infra_backups can
  # authenticate to the S3 endpoint without a long-lived obj key threaded
  # through .env. Revoked when the apply finishes.
  obj_use_temp_keys = true
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
  deploy_user            = var.DEPLOY_USER
}

module "network" {
  source = "../../modules/network"

  label      = "${local.resource_prefix}-dokploy"
  tags       = local.TAGS
  linode_ids = [module.dokploy-instance.instance_id]
}

module "domain" {
  source = "../../modules/domain"

  EMAIL_ADDRESS       = var.EMAIL_ADDRESS
  HOSTNAME_TLD        = var.HOSTNAME_TLD
  WEBSITE_INSTANCE_IP = module.dokploy-instance.instance_ip
  TAGS                = local.TAGS
}

module "dokploy_dns01" {
  source = "../../modules/dokploy-dns01"

  resource_prefix = local.resource_prefix
  instance_ip     = module.dokploy-instance.instance_ip
  email           = var.EMAIL_ADDRESS
  hostname_tld    = var.HOSTNAME_TLD
  deploy_user     = module.dokploy-instance.deploy_user
}

# Bind the Dokploy dashboard to <DASHBOARD_SUBDOMAIN>.<HOSTNAME_TLD> over HTTPS.
# Runs only after the wildcard A record exists so Traefik's first ACME HTTP-01
# challenge can succeed without retry. The Dokploy admin API is loopback-only,
# so the call is issued from inside the host over SSH using the API key
# materialized by user_data.sh at /root/.dokploy-api-key. Depends on
# dokploy_dns01 so the dashboard binding triggers DNS-01, not HTTP-01.
resource "null_resource" "bind_dokploy_domain" {
  depends_on = [module.dokploy-instance, module.domain, module.dokploy_dns01]

  triggers = {
    instance_ip = module.dokploy-instance.instance_ip
    host        = "${var.DASHBOARD_SUBDOMAIN}.${var.HOSTNAME_TLD}"
    email       = var.EMAIL_ADDRESS
  }

  connection {
    type        = "ssh"
    host        = module.dokploy-instance.instance_ip
    user        = module.dokploy-instance.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${module.dokploy-instance.deploy_user}/.dokploy-bind-domain.json"
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
      sudo test -s /root/.dokploy-api-key
      API_KEY=$(sudo cat /root/.dokploy-api-key)
      curl -sf -X POST http://localhost:3000/api/trpc/settings.assignDomainServer \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/home/${module.dokploy-instance.deploy_user}/.dokploy-bind-domain.json
      rm -f /home/${module.dokploy-instance.deploy_user}/.dokploy-bind-domain.json
      EOT
    ]
  }
}

# Long-lived backups bucket. Kept here (not inside acme-backup module) so other
# modules can reference it. prevent_destroy guards against accidental nuking on
# `terraform destroy` — destroys fail loudly until the line is removed.
resource "linode_object_storage_bucket" "infra_backups" {
  region     = var.REGION
  label      = "${local.resource_prefix}-infra-backups"
  versioning = true
  acl        = "private"

  lifecycle {
    prevent_destroy = true
  }

  lifecycle_rule {
    abort_incomplete_multipart_upload_days = 7
    enabled                                = true

    noncurrent_version_expiration {
      days = 7
    }
  }
}

# SSH config snippet for VS Code Remote-SSH and ad-hoc `ssh dokploy-prod`.
# Written next to id_ed25519 so paths resolve on whichever machine ran the
# apply. production.sh idempotently appends an `Include` line to ~/.ssh/config
# pointing at this file. Not gitignored as secret material — it just holds
# the current instance IP plus an absolute IdentityFile path.
#
# TODO: replace HostName ${module.dokploy-instance.instance_ip} with a
# dedicated, non-public SSH endpoint (e.g. ssh.<HOSTNAME_TLD> A record routed
# through a bastion / Tailscale / Cloudflare Tunnel / WireGuard hub) so the
# raw instance IP is no longer embedded in user ssh configs and can rotate
# freely with instance replacement.
resource "local_file" "ssh_config" {
  filename        = "${path.root}/dokploy.sshconfig"
  file_permission = "0600"
  content         = <<-EOT
    Host dokploy-prod
        HostName ${module.dokploy-instance.instance_ip}
        User ${module.dokploy-instance.deploy_user}
        IdentityFile ${abspath(path.root)}/id_ed25519
        IdentitiesOnly yes
        StrictHostKeyChecking accept-new
        UserKnownHostsFile ~/.ssh/known_hosts_dokploy
  EOT
}

module "acme_backup" {
  source = "../../modules/acme-backup"

  region          = var.REGION
  resource_prefix = local.resource_prefix
  bucket_name     = linode_object_storage_bucket.infra_backups.label
  endpoint        = linode_object_storage_bucket.infra_backups.s3_endpoint
  gpg_recipient   = var.GPG_RECIPIENT
  instance_ip     = module.dokploy-instance.instance_ip
  deploy_user     = module.dokploy-instance.deploy_user
}

# TODO: Add a GitLab/GitHub provider resource to manage the chezmoi generic package artifact in the self-hosted GitLab instance (enki).
# TODO: When creating the build runner instance, ensure its cloud-init/user_data script is configured to pull the chezmoi artifact from the self-hosted GitLab package registry.
