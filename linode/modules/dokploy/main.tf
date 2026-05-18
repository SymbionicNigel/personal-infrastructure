terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "3.4.0"
    }
  }
}

resource "random_password" "dokploy_main_root_pass" {
  length           = 20
  min_lower        = 3
  min_upper        = 3
  min_numeric      = 3
  min_special      = 3
  override_special = "!#$%&*()-_=+[]{}<>:?"
}

resource "linode_sshkey" "dokploy_linode_ssh" {
  label   = "dokploy-ssh"
  ssh_key = chomp(file("${path.root}/id_ed25519.pub"))
}

resource "terraform_data" "user_data_hash" {
  input = sha256(templatefile("${path.module}/user_data.sh", {
    HOSTNAME_TLD           = var.HOSTNAME_TLD
    DOKPLOY_ADMIN_EMAIL    = var.DOKPLOY_ADMIN_EMAIL
    DOKPLOY_ADMIN_PASSWORD = var.DOKPLOY_ADMIN_PASSWORD
    DOKPLOY_VERSION        = var.DOKPLOY_VERSION
  }))
}

resource "linode_instance" "dokploy_main" {
  booted           = true
  watchdog_enabled = true
  region           = var.region
  type             = "g6-standard-1" # minimum size to handle dokploy startup
  label            = "dokploy-main"
  backups_enabled  = false
  image            = "linode/ubuntu22.04"
  tags             = tolist(var.TAGS)
  alerts {
    cpu            = 90
    network_in     = 5
    network_out    = 5
    transfer_quota = 80
    io             = 10000
  }
  root_pass       = random_password.dokploy_main_root_pass.result
  authorized_keys = [linode_sshkey.dokploy_linode_ssh.ssh_key]

  metadata {
    user_data = base64encode(templatefile("${path.module}/user_data.sh", {
      HOSTNAME_TLD        = var.HOSTNAME_TLD
      DOKPLOY_ADMIN_EMAIL = var.DOKPLOY_ADMIN_EMAIL
      # TODO: See what we can do to remove the admin password from the file created here and stored in the linode's metadata permanently
      DOKPLOY_ADMIN_PASSWORD = var.DOKPLOY_ADMIN_PASSWORD
      DOKPLOY_VERSION        = var.DOKPLOY_VERSION
    }))
  }

  connection {
    type        = "ssh"
    host        = one(self.ipv4)
    user        = "root"
    private_key = file("${path.root}/id_ed25519")
  }

  # Block until cloud-init finishes and the Dokploy API key sentinel exists.
  # Tails /var/log/cloud-init-output.log in the background so every line of
  # user_data.sh streams into `terraform apply` output in real time —
  # otherwise this step is a silent ~5-minute black box.
  provisioner "remote-exec" {
    inline = [
      "touch /var/log/cloud-init-output.log",
      "tail -n +1 -F /var/log/cloud-init-output.log & TAIL_PID=$!",
      "cloud-init status --wait || STATUS_RC=$?",
      "sleep 1",
      "kill $TAIL_PID >/dev/null 2>&1 || true",
      "test -s /root/.dokploy-api-key",
      "exit $${STATUS_RC:-0}"
    ]
  }

  # Retrieve the API key to a local file for Stage 2
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -i ${path.root}/id_ed25519 symbionic_dokploy_user@${one(self.ipv4)} sudo cat /root/.dokploy-api-key > ${path.root}/.dokploy-api-key"
  }

  lifecycle {
    replace_triggered_by = [terraform_data.user_data_hash]
  }
}
