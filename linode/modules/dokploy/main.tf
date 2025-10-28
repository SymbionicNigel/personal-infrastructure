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
  ssh_key = chomp("${path.root}/id_es25519.pub")
}

resource "linode_instance" "dokploy_main" {
  booted           = true
  watchdog_enabled = true
  region           = var.region
  type             = "g6-nanode-1"
  label            = "dokploy-main"
  backups_enabled  = false
  image            = "linode/ubuntu22.04"
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
      HOSTNAME_TLD : var.HOSTNAME_TLD
    }))
  }
}
