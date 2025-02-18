locals {
  hcp_organization = title(replace(var.HOSTNAME_TLD, ".", "-"))
  hcp_project      = title(replace(var.HOSTNAME_TLD, ".", "_"))
}

terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "2.27.0"
    }
  }

  # TODO: Add in HCP provider, make use of provider to fetch secrets for the app from Vault https://registry.terraform.io/providers/hashicorp/hcp/latest/docs/guides/vault-secrets-data-sources
  # TODO: Remove all secrets and Symbionic-Tech specific naming
  cloud {
    organization = locals.hcp_organization
    token        = var.HCP_TOKEN
    workspaces {
      name    = "${locals.hcp_project}_${var.ENVIRON}"
      project = locals.hcp_project
    }
  }
}

provider "linode" {
  config_path    = "~/.config/linode-cli"
  config_profile = ""
  # Can be sent through ENV Variable
  token = ""
}

# TODO: Handle creating primary instance
# TODO: handle restricting network access

module "domain" {
  source = "../modules/domains"
}
