terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.4.0"
    }
  }
}

locals {
  TAGS = [var.HOSTNAME_TLD, "production"]

  # Transforming hostname into configuration profile username
  hostname_parts = split(".", var.HOSTNAME_TLD)
  config_profile = "${lower(local.hostname_parts[0])}${local.hostname_parts[1]}"
}

provider "linode" {
  config_path    = pathexpand("~/.config/linode-cli")
  config_profile = local.config_profile
}

# TODO: handle restricting network access/VPC

module "dokploy-instance" {
  source = "../../modules/dokploy"

  region       = var.REGION
  HOSTNAME_TLD = var.HOSTNAME_TLD
  TAGS         = local.TAGS
}

module "domain" {
  source = "../../modules/domain"

  EMAIL_ADDRESS       = var.EMAIL_ADDRESS
  HOSTNAME_TLD        = var.HOSTNAME_TLD
  WEBSITE_INSTANCE_IP = module.dokploy-instance.instance_ip
  TAGS                = local.TAGS
}

# TODO: Add a GitLab/GitHub provider resource to manage the chezmoi generic package artifact in the self-hosted GitLab instance (enki).
# TODO: When creating the build runner instance, ensure its cloud-init/user_data script is configured to pull the chezmoi artifact from the self-hosted GitLab package registry.
