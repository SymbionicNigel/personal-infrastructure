terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.30"
    }
  }
}

resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/acl.hujson", {
    home_lan_cidr   = var.home_lan_cidr
    game_port_range = var.game_port_range
  })
  # The tailnet's starter policy (and the throwaway tagOwners declared by hand
  # to seed the OAuth client's tag picker) count as "non-default"; this module
  # is the source of truth, so replace whatever is there.
  overwrite_existing_content = true
}

resource "tailscale_dns_preferences" "magicdns" {
  magic_dns = true
}

resource "tailscale_tailnet_key" "cloud" {
  # Keys carry tags, which must be declared in tagOwners first. Without this,
  # a same-apply create can race the policy write and 400 on "invalid tags".
  depends_on    = [tailscale_acl.policy]
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "dokploy Linode host"
  tags          = ["tag:dokploy"]
}

resource "tailscale_tailnet_key" "compute" {
  depends_on    = [tailscale_acl.policy]
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-compute i7 Wings node"
  tags          = ["tag:mc-compute"]
}

resource "tailscale_tailnet_key" "gateway" {
  depends_on    = [tailscale_acl.policy]
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-gateway Pi subnet router"
  tags          = ["tag:mc-gateway"]
}
