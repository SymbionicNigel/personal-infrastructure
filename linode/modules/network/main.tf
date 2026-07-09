terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.0.0"
    }
  }
}

# Network-layer firewall. Survives instance replacement: the rule set lives on
# the firewall resource; only the `linodes = [...]` attachment is rewritten
# when an attached instance is recreated. UFW on each instance remains as
# defense in depth.
resource "linode_firewall" "this" {
  label = var.label
  tags  = var.tags

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  # HTTP/3 / QUIC. Traefik advertises HTTP/3 on :443 by default; without this
  # rule, HTTP/3-preferring clients (Chrome, mobile) hit a UDP timeout before
  # falling back to TCP, adding 5–10s to the first request.
  inbound {
    label    = "https-quic"
    action   = "ACCEPT"
    protocol = "UDP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  linodes = var.linode_ids
}
