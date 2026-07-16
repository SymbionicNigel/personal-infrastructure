terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.1.0"
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
      DEPLOY_USER         = var.deploy_user
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
  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || STATUS_RC=$?",
      "test -s /root/.dokploy-api-key",
      "exit $${STATUS_RC:-0}"
    ]
  }

  # Retrieve the API key to a local file for Stage 2
  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = "ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -i ${path.root}/id_ed25519 ${var.deploy_user}@${one(self.ipv4)} sudo cat /root/.dokploy-api-key > ${path.root}/.dokploy-api-key"
  }

  lifecycle {
    ignore_changes = [metadata]
  }
}
