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
  }
}

resource "linode_object_storage_key" "infra_backups" {
  label = "${var.resource_prefix}-infra-backups-rw"

  bucket_access {
    bucket_name = var.bucket_name
    region      = var.region
    permissions = "read_write"
  }
}


# Pushes /root/.s3cfg + /root/.acme-backup.env + the gpg public key to the
# host AFTER cloud-init completes. Keeping these out of user_data avoids
# exposure via the Linode metadata service.
resource "null_resource" "configure_acme_backup" {
  depends_on = [linode_object_storage_key.infra_backups]

  triggers = {
    instance_ip = var.instance_ip
    recipient   = var.gpg_recipient
    access_key  = linode_object_storage_key.infra_backups.access_key
    endpoint    = var.endpoint
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.s3cfg"
    content     = <<-EOT
      [default]
      access_key = ${linode_object_storage_key.infra_backups.access_key}
      secret_key = ${linode_object_storage_key.infra_backups.secret_key}
      host_base = ${var.endpoint}
      host_bucket = %(bucket)s.${var.endpoint}
      use_https = True
      signature_v2 = False
    EOT
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.acme-backup.env"
    content     = "BACKUP_BUCKET=${var.bucket_name}\nGPG_RECIPIENT=${var.gpg_recipient}\n"
  }

  provisioner "remote-exec" {
    inline = [
      "sudo install -m 0600 -o root -g root /home/${var.deploy_user}/.s3cfg /root/.s3cfg",
      "sudo install -m 0600 -o root -g root /home/${var.deploy_user}/.acme-backup.env /root/.acme-backup.env",
      "rm -f /home/${var.deploy_user}/.s3cfg /home/${var.deploy_user}/.acme-backup.env",
    ]
  }

  # Export the public key locally and pipe it over SSH → gpg --import on host.
  # Requires the recipient's public key to be in the deploy machine's keyring.
  # Pre-flight `--list-keys` so a missing key fails on the deploy machine
  # instead of producing a silent zero-byte export and a cryptic host-side
  # failure on the first scheduled backup.
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      if ! gpg --list-keys "${var.gpg_recipient}" >/dev/null 2>&1; then
        echo "ERROR: gpg public key for '${var.gpg_recipient}' not found in local keyring." >&2
        echo "Import it before applying: gpg --import <pubkey-file>" >&2
        exit 1
      fi
      gpg --export -a "${var.gpg_recipient}" \
        | ssh -o StrictHostKeyChecking=accept-new \
              -o UserKnownHostsFile=/dev/null \
              -i ${path.root}/id_ed25519 \
              ${var.deploy_user}@${var.instance_ip} \
              'sudo gpg --batch --import'
    EOT
  }
}

# Restores acme.json from the encrypted backup if one exists, before any
# per-host LE issuance is triggered. Decrypts on the deploy machine and pipes
# plaintext over SSH directly into install(1) — cert plaintext never lands
# on the deploy disk.
#
# Triggers: instance_ip only. Restore does NOT re-run on backup change —
# re-restoring would clobber a live acme.json with stale data.
# To force a restore: terraform apply -replace='module.acme_backup.null_resource.restore_acme'
resource "null_resource" "restore_acme" {
  depends_on = [null_resource.configure_acme_backup]

  triggers = {
    instance_ip = var.instance_ip
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
      {
        printf '[default]\n'
        printf 'access_key = %s\n' '${linode_object_storage_key.infra_backups.access_key}'
        printf 'secret_key = %s\n' '${linode_object_storage_key.infra_backups.secret_key}'
        printf 'host_base = %s\n' '${var.endpoint}'
        printf 'host_bucket = %%(bucket)s.%s\n' '${var.endpoint}'
        printf 'use_https = True\n'
        printf 'signature_v2 = False\n'
      } > "$CFG"
      chmod 600 "$CFG"

      if ! s3cmd -c "$CFG" info "s3://${var.bucket_name}/acme.json.gpg" >/dev/null 2>&1; then
        echo "[restore_acme] no backup at s3://${var.bucket_name}/acme.json.gpg — skipping"
        exit 0
      fi

      echo "[restore_acme] restoring acme.json from backup"
      s3cmd -c "$CFG" get --force "s3://${var.bucket_name}/acme.json.gpg" - \
        | gpg --batch --decrypt \
        | ssh -o StrictHostKeyChecking=accept-new \
              -o UserKnownHostsFile=/dev/null \
              -i ${path.root}/id_ed25519 \
              ${var.deploy_user}@${var.instance_ip} \
              "sudo install -m 0600 -o root -g root /dev/stdin /etc/dokploy/traefik/dynamic/acme.json && sudo docker restart dokploy-traefik >/dev/null"

      echo "[restore_acme] done"
    EOT
  }
}
