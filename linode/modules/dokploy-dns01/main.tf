terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.2.0"
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

locals {
  # Replaces Dokploy's default traefik.yml. The stock file hard-codes
  # httpChallenge on the letsencrypt resolver, which conflicts with the DNS-01
  # env vars pushed by null_resource.configure: lego refuses wildcards (illegal
  # over HTTP-01) and falls back to HTTP-01 for the apex (firewall-blocked).
  traefik_yaml = <<-YAML
    global:
      sendAnonymousUsage: false
    accessLog:
      filePath: /etc/dokploy/traefik/dynamic/access.log
      format: json
      bufferingSize: 100
    providers:
      swarm:
        exposedByDefault: false
        watch: true
      docker:
        exposedByDefault: false
        watch: true
        network: dokploy-network
      file:
        directory: /etc/dokploy/traefik/dynamic
        watch: true
    entryPoints:
      web:
        address: ":80"
      websecure:
        address: ":443"
        http3:
          advertisedPort: 443
        http:
          tls:
            certResolver: letsencrypt
    api:
      insecure: true
    certificatesResolvers:
      letsencrypt:
        acme:
          email: ${var.email}
          storage: /etc/dokploy/traefik/dynamic/acme.json
          dnsChallenge:
            provider: linode
            resolvers:
              - "1.1.1.1:53"
              - "8.8.8.8:53"
  YAML
}

# Rewrite the host's /etc/dokploy/traefik/traefik.yml to use DNS-01.
# writeMainConfig writes to a known absolute path; the file is volume-mounted
# read-only into the traefik container, so a write here changes what traefik
# sees on its next restart. The env push by null_resource.configure triggers
# writeTraefikSetup, which recreates the container — picking up both the new
# YAML and the new env atomically.
resource "null_resource" "configure_main" {
  triggers = {
    instance_ip = var.instance_ip
    yaml_hash   = sha256(local.traefik_yaml)
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.dokploy-traefik-main.yml"
    content     = local.traefik_yaml
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      #!/bin/bash
      set -euo pipefail
      sudo test -s /root/.dokploy-api-key
      API_KEY=$(sudo cat /root/.dokploy-api-key)

      jq -Rn --rawfile yaml /home/${var.deploy_user}/.dokploy-traefik-main.yml \
        '{json: {traefikConfig: $yaml}}' \
        > /home/${var.deploy_user}/.dokploy-traefik-main.json

      curl -sf -X POST "http://localhost:3000/api/trpc/settings.updateTraefikConfig" \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/home/${var.deploy_user}/.dokploy-traefik-main.json

      rm -f /home/${var.deploy_user}/.dokploy-traefik-main.yml \
            /home/${var.deploy_user}/.dokploy-traefik-main.json
      EOT
    ]
  }
}

# Configure Dokploy's Traefik env to use DNS-01 with the linode lego provider.
# Read-merge-write so we don't clobber any other env keys Dokploy or the user
# has set in the dashboard. SSH + curl to localhost (not the public dashboard
# URL) so the call doesn't depend on a valid TLS cert — which is what we're
# trying to issue.
resource "null_resource" "configure" {
  depends_on = [linode_token.dns, null_resource.configure_main]

  triggers = {
    instance_ip = var.instance_ip
    email       = var.email
    token       = sha256(linode_token.dns.token) # hash so the secret isn't in plan output
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  # Stage the new env keys we want set, one per line. The remote-exec merges
  # these with whatever Dokploy already has (preserving other keys) before
  # writing back via settings.writeTraefikEnv.
  provisioner "file" {
    destination = "/home/${var.deploy_user}/.dokploy-traefik-dns01.env"
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
      REPLACE_KEYS=$(awk -F= '{print $1}' /home/${var.deploy_user}/.dokploy-traefik-dns01.env | sort -u)
      KEEP=$(printf '%s\n' "$CURRENT" | awk -F= -v keys="$REPLACE_KEYS" '
        BEGIN { n = split(keys, a, "\n"); for (i=1;i<=n;i++) drop[a[i]]=1 }
        { if (!($1 in drop) && length($0)) print }
      ')
      MERGED=$(printf '%s\n%s' "$KEEP" "$(cat /home/${var.deploy_user}/.dokploy-traefik-dns01.env)")

      # Wrap merged env in the tRPC mutation payload shape: {"json":{"env":"..."}}
      jq -n --arg env "$MERGED" '{json: {env: $env}}' > /home/${var.deploy_user}/.dokploy-traefik-dns01.json

      curl -sf -X POST "http://localhost:3000/api/trpc/settings.writeTraefikEnv" \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/home/${var.deploy_user}/.dokploy-traefik-dns01.json

      # Clean up: token never persists longer than one POST cycle on disk
      shred -u /home/${var.deploy_user}/.dokploy-traefik-dns01.env /home/${var.deploy_user}/.dokploy-traefik-dns01.json 2>/dev/null \
        || rm -f /home/${var.deploy_user}/.dokploy-traefik-dns01.env /home/${var.deploy_user}/.dokploy-traefik-dns01.json
      EOT
    ]
  }
}

locals {
  wildcard_dynamic_yaml = <<-YAML
    tls:
      stores:
        default:
          defaultGeneratedCert:
            resolver: letsencrypt
            domain:
              main: ${var.hostname_tld}
              sans:
                - "*.${var.hostname_tld}"
  YAML
}

# Push Traefik dynamic config that requests a single wildcard cert via the
# default TLS store. Mirrors the env-push pattern above: SSH + tRPC against
# localhost so we don't depend on a valid public cert. Read-merge semantics
# aren't needed here — this YAML is wholly owned by Terraform.
resource "null_resource" "configure_dynamic" {
  depends_on = [null_resource.configure]

  triggers = {
    instance_ip = var.instance_ip
    config_hash = sha256("/etc/dokploy/traefik/dynamic/wildcard-tls.yml:${local.wildcard_dynamic_yaml}")
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.dokploy-traefik-dynamic.yml"
    content     = local.wildcard_dynamic_yaml
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      #!/bin/bash
      set -euo pipefail
      sudo test -s /root/.dokploy-api-key
      API_KEY=$(sudo cat /root/.dokploy-api-key)

      # settings.updateTraefikFile's writeTraefikConfigInPath does NOT prepend
      # MAIN_TRAEFIK_PATH and swallows errors in try/catch — so the path must be
      # absolute. /etc/dokploy/traefik/dynamic/ is bind-mounted into the dokploy
      # container and watched by Traefik's file provider.
      jq -Rn --rawfile yaml /home/${var.deploy_user}/.dokploy-traefik-dynamic.yml \
        '{json: {path: "/etc/dokploy/traefik/dynamic/wildcard-tls.yml", traefikConfig: $yaml}}' \
        > /home/${var.deploy_user}/.dokploy-traefik-dynamic.json

      curl -sf -X POST "http://localhost:3000/api/trpc/settings.updateTraefikFile" \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/home/${var.deploy_user}/.dokploy-traefik-dynamic.json

      rm -f /home/${var.deploy_user}/.dokploy-traefik-dynamic.yml \
            /home/${var.deploy_user}/.dokploy-traefik-dynamic.json
      EOT
    ]
  }
}
