# Pushes /root/.s3cfg + /root/.acme-backup.env + the gpg public key to the
# host AFTER cloud-init completes. Keeping these out of user_data avoids
# exposure via the Linode metadata service.
resource "null_resource" "configure_acme_backup" {
  triggers = {
    instance_ip = local.instance_ip
    recipient   = var.backup.gpg_recipient
    access_key  = var.backup.access_key
    endpoint    = var.backup.endpoint
  }

  lifecycle {
    replace_triggered_by = [linode_instance.dokploy_main.id]
  }

  connection {
    type        = "ssh"
    host        = local.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.s3cfg"
    content     = <<-EOT
      [default]
      access_key = ${var.backup.access_key}
      secret_key = ${var.backup.secret_key}
      host_base = ${var.backup.endpoint}
      host_bucket = %(bucket)s.${var.backup.endpoint}
      use_https = True
      signature_v2 = False
    EOT
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.acme-backup.env"
    content     = "BACKUP_BUCKET=${var.backup.bucket}\nGPG_RECIPIENT=${var.backup.gpg_recipient}\n"
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
      if ! gpg --list-keys "${var.backup.gpg_recipient}" >/dev/null 2>&1; then
        echo "ERROR: gpg public key for '${var.backup.gpg_recipient}' not found in local keyring." >&2
        echo "Import it before applying: gpg --import <pubkey-file>" >&2
        exit 1
      fi
      gpg --export -a "${var.backup.gpg_recipient}" \
        | ssh -o StrictHostKeyChecking=accept-new \
              -o UserKnownHostsFile=/dev/null \
              -i ${path.root}/id_ed25519 \
              ${var.deploy_user}@${local.instance_ip} \
              'sudo gpg --batch --import'
    EOT
  }
}

# Restores acme.json from the encrypted backup if one exists, before any
# per-host LE issuance is triggered. Decrypts on the deploy machine and pipes
# plaintext over SSH directly into install(1) — cert plaintext never lands
# on the deploy disk.
resource "null_resource" "restore_acme" {
  depends_on = [null_resource.configure_acme_backup]

  triggers = {
    instance_ip = local.instance_ip
  }

  lifecycle {
    replace_triggered_by = [linode_instance.dokploy_main.id]
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
      {
        printf '[default]\n'
        printf 'access_key = %s\n' '${var.backup.access_key}'
        printf 'secret_key = %s\n' '${var.backup.secret_key}'
        printf 'host_base = %s\n' '${var.backup.endpoint}'
        printf 'host_bucket = %%(bucket)s.%s\n' '${var.backup.endpoint}'
        printf 'use_https = True\n'
        printf 'signature_v2 = False\n'
      } > "$CFG"
      chmod 600 "$CFG"

      archive="s3://${var.backup.bucket}/acme.json.gpg"
      listing=$(s3cmd -c "$CFG" ls "$archive")
      if [ -z "$listing" ]; then
        echo "[restore_acme] no backup at s3://${var.backup.bucket}/acme.json.gpg — skipping"
        exit 0
      fi

      echo "[restore_acme] restoring acme.json from backup"
      acme=$(s3cmd -c "$CFG" get --force "$archive" - | gpg --batch --decrypt)
      printf '%s' "$acme" \
        | ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new \
              -o UserKnownHostsFile=/dev/null \
              -i ${path.root}/id_ed25519 \
              ${var.deploy_user}@${local.instance_ip} \
              "sudo -n install -m 0600 -o root -g root /dev/stdin /etc/dokploy/traefik/dynamic/acme.json"

      echo "[restore_acme] done"
    EOT
  }
}
