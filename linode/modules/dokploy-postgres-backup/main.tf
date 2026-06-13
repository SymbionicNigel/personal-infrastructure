terraform {
  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}

# Pushes /root/.dokploy-pg-backup.env, the backup script, and the systemd
# service + timer to the host AFTER cloud-init completes. Reuses /root/.s3cfg
# and the imported GPG public key pushed by the acme-backup module, so this
# module deliberately does NOT create its own object-storage key or push s3cfg.
resource "null_resource" "configure_dokploy_pg_backup" {
  triggers = {
    instance_ip = var.instance_ip
    bucket      = var.bucket_name
    recipient   = var.gpg_recipient
    endpoint    = var.endpoint
  }

  connection {
    type        = "ssh"
    host        = var.instance_ip
    user        = var.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/.dokploy-pg-backup.env"
    content     = "BACKUP_BUCKET=${var.bucket_name}\nGPG_RECIPIENT=${var.gpg_recipient}\n"
  }

  # Backup script: pg_dump → gpg --encrypt → s3cmd put. Runs as root via
  # systemd. pg_dump runs inside the dokploy-postgres container (its postgres
  # client matches the server version); host doesn't need a postgres client
  # installed. PIPESTATUS check ensures a mid-pipe failure (e.g. pg_dump
  # OOMing) exits non-zero rather than uploading a truncated dump.
  provisioner "file" {
    destination = "/home/${var.deploy_user}/dokploy-pg-backup.sh"
    content     = <<-EOT
      #!/usr/bin/env bash
      set -euo pipefail
      # shellcheck disable=SC1091
      source /root/.dokploy-pg-backup.env

      TS=$(date -u +%Y%m%dT%H%M%SZ)
      KEY="dokploy-postgres/$${TS}.sql.gpg"
      MIN_BYTES=1024

      # Dokploy runs postgres as a Swarm service, so the container name has a
      # dynamic .<replica>.<task_id> suffix. Resolve it at run time.
      PG=$(docker ps -q -f name=dokploy-postgres -f status=running | head -1)
      if [ -z "$${PG}" ]; then
        echo "dokploy-pg-backup: no running dokploy-postgres container" >&2
        exit 1
      fi

      WORKDIR=$(mktemp -d)
      trap 'rm -rf "$${WORKDIR}"' EXIT
      ENCRYPTED="$${WORKDIR}/dump.sql.gpg"

      # Materialize the encrypted dump to disk before upload. s3cmd put from a
      # pipe ("put -") silently uploads 0 bytes when it can't determine
      # content-length, so we stage to a file and let s3cmd see the size.
      # --clean --if-exists: emits DROP ahead of each CREATE for psql restore.
      # --trust-model always: pubkey was imported without explicit trust
      # (matches acme-backup's posture).
      docker exec "$${PG}" pg_dump --clean --if-exists -U dokploy -d dokploy \
        | gpg --batch --yes --trust-model always --encrypt --recipient "$${GPG_RECIPIENT}" \
              --output "$${ENCRYPTED}"

      # Floor check: a viable encrypted dump is on the order of tens of KB.
      # Anything under MIN_BYTES is a truncated pipeline that escaped the
      # pipefail net (e.g. pg_dump wrote nothing but exited 0).
      SIZE=$(stat -c %s "$${ENCRYPTED}")
      if [ "$${SIZE}" -lt "$${MIN_BYTES}" ]; then
        echo "dokploy-pg-backup: encrypted dump is $${SIZE}B (< $${MIN_BYTES}B floor) — aborting" >&2
        exit 1
      fi

      s3cmd -c /root/.s3cfg put "$${ENCRYPTED}" "s3://$${BACKUP_BUCKET}/$${KEY}" >/dev/null

      echo "dokploy-pg-backup: uploaded s3://$${BACKUP_BUCKET}/$${KEY} ($${SIZE}B encrypted)"
    EOT
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/dokploy-pg-backup.service"
    content     = <<-EOT
      [Unit]
      Description=Encrypted pg_dump of dokploy-postgres to object storage
      # No-op if acme-backup hasn't populated /root/.s3cfg yet.
      ConditionPathExists=/root/.s3cfg
      ConditionPathExists=/root/.dokploy-pg-backup.env

      [Service]
      Type=oneshot
      ExecStart=/usr/local/sbin/dokploy-pg-backup.sh
    EOT
  }

  provisioner "file" {
    destination = "/home/${var.deploy_user}/dokploy-pg-backup.timer"
    content     = <<-EOT
      [Unit]
      Description=Daily encrypted backup of dokploy-postgres

      [Timer]
      # Daily at 04:00 host time. Picked to fall after typical ACME renewal
      # windows so backup logs don't intermix with cert rotation.
      OnCalendar=*-*-* 04:00:00
      Persistent=true
      RandomizedDelaySec=5m

      [Install]
      WantedBy=timers.target
    EOT
  }

  provisioner "remote-exec" {
    inline = [
      "sudo install -m 0600 -o root -g root /home/${var.deploy_user}/.dokploy-pg-backup.env /root/.dokploy-pg-backup.env",
      "sudo install -m 0755 -o root -g root /home/${var.deploy_user}/dokploy-pg-backup.sh /usr/local/sbin/dokploy-pg-backup.sh",
      "sudo install -m 0644 -o root -g root /home/${var.deploy_user}/dokploy-pg-backup.service /etc/systemd/system/dokploy-pg-backup.service",
      "sudo install -m 0644 -o root -g root /home/${var.deploy_user}/dokploy-pg-backup.timer /etc/systemd/system/dokploy-pg-backup.timer",
      "rm -f /home/${var.deploy_user}/.dokploy-pg-backup.env /home/${var.deploy_user}/dokploy-pg-backup.sh /home/${var.deploy_user}/dokploy-pg-backup.service /home/${var.deploy_user}/dokploy-pg-backup.timer",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable --now dokploy-pg-backup.timer",
    ]
  }
}
