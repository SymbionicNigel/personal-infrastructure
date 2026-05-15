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
    time = {
      source  = "hashicorp/time"
      version = "~> 0.11"
    }
  }
}

# Rotate the DNS-scoped Linode token every 365 days. Long cadence because the
# blast radius is bounded (domains:read_write only) and replacing the token
# forces a re-push to the instance via configure.
resource "time_rotating" "dns_token" {
  rotation_days = 365
}

resource "terraform_data" "dns_token_rotation" {
  input = time_rotating.dns_token.rotation_rfc3339
}

# Security note: this token is consumed by Traefik on the dokploy instance and
# lives in Dokploy's Traefik env file under /etc/dokploy. Host root or a
# compromised Dokploy admin credential can read it. Blast radius is bounded —
# the scope is domains:read_write only, so leakage permits DNS manipulation
# for the account's zones but no instance/storage access. Mitigated by:
# annual rotation, narrow scope, and the master TF_VAR_LINODE_TOKEN never
# leaving the deploy machine.
resource "linode_token" "dns" {
  label  = "${var.resource_prefix}-traefik-dns"
  scopes = "domains:read_write"

  lifecycle {
    replace_triggered_by = [terraform_data.dns_token_rotation]
  }
}

# Configure Dokploy's Traefik env to use DNS-01 with the linode lego provider.
# Read-merge-write so we don't clobber any other env keys Dokploy or the user
# has set in the dashboard. SSH + curl to localhost (not the public dashboard
# URL) so the call doesn't depend on a valid TLS cert — which is what we're
# trying to issue.
resource "null_resource" "configure" {
  depends_on = [linode_token.dns]

  triggers = {
    instance_ip = var.instance_ip
    email       = var.email
    token       = sha256(linode_token.dns.token) # hash so the secret isn't in plan output
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = "symbionic_dokploy_user"
    private_key = file("${path.root}/id_ed25519")
  }

  # Stage the new env keys we want set, one per line. The remote-exec merges
  # these with whatever Dokploy already has (preserving other keys) before
  # writing back via settings.writeTraefikEnv.
  provisioner "file" {
    destination = "/home/symbionic_dokploy_user/.dokploy-traefik-dns01.env"
    content     = <<-EOT
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${var.email}
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/etc/dokploy/traefik/dynamic/acme.json
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE=true
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER=linode
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS=1.1.1.1:53,8.8.8.8:53
      LINODE_TOKEN=${linode_token.dns.token}
    EOT
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      #!/bin/bash
      # Shebang forces bash via the kernel; without it, the kernel falls back
      # to /bin/sh (dash on Ubuntu) which rejects `set -o pipefail`.
      set -euo pipefail
      sudo test -s /root/.dokploy-api-key
      API_KEY=$(sudo cat /root/.dokploy-api-key)

      # Read current Traefik env from Dokploy.
      CURRENT=$(curl -sf "http://localhost:3000/api/trpc/settings.readTraefikEnv?input=%7B%22json%22%3A%7B%7D%7D" \
        -H "x-api-key: $API_KEY" | jq -r '.result.data.json')

      # Merge: keep CURRENT lines whose KEY is not in our new set, append all new lines.
      REPLACE_KEYS=$(awk -F= '{print $1}' /home/symbionic_dokploy_user/.dokploy-traefik-dns01.env | sort -u)
      KEEP=$(printf '%s\n' "$CURRENT" | awk -F= -v keys="$REPLACE_KEYS" '
        BEGIN { n = split(keys, a, "\n"); for (i=1;i<=n;i++) drop[a[i]]=1 }
        { if (!($1 in drop) && length($0)) print }
      ')
      MERGED=$(printf '%s\n%s' "$KEEP" "$(cat /home/symbionic_dokploy_user/.dokploy-traefik-dns01.env)")

      # Wrap merged env in the tRPC mutation payload shape: {"json":{"env":"..."}}
      jq -n --arg env "$MERGED" '{json: {env: $env}}' > /home/symbionic_dokploy_user/.dokploy-traefik-dns01.json

      curl -sf -X POST "http://localhost:3000/api/trpc/settings.writeTraefikEnv" \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/home/symbionic_dokploy_user/.dokploy-traefik-dns01.json

      # Clean up: token never persists longer than one POST cycle on disk
      shred -u /home/symbionic_dokploy_user/.dokploy-traefik-dns01.env /home/symbionic_dokploy_user/.dokploy-traefik-dns01.json 2>/dev/null \
        || rm -f /home/symbionic_dokploy_user/.dokploy-traefik-dns01.env /home/symbionic_dokploy_user/.dokploy-traefik-dns01.json
      EOT
    ]
  }
}
