terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
  }
}

resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/acl.hujson", {
    home_lan_cidr   = var.home_lan_cidr
    game_port_range = var.game_port_range
  })
}

resource "tailscale_dns_preferences" "magicdns" {
  magic_dns = true
}

resource "tailscale_tailnet_key" "cloud" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-cloud (Linode host)"
  tags          = ["tag:mc-cloud"]
}

resource "tailscale_tailnet_key" "compute" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-compute (i7 Wings node)"
  tags          = ["tag:mc-compute"]
}

resource "tailscale_tailnet_key" "gateway" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-gateway (Pi subnet router)"
  tags          = ["tag:mc-gateway"]
}
