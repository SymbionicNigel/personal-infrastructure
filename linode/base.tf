terraform {
  required_providers {
    linode = {
        source = "linode/linode"
    }
  }
}

provider "linode" {}

# TODO: Handle creating primary instance

resource "linode_instance" "fedora-test" {
  watchdog_enabled = true
}

# TODO: handle restricting network access

resource "linode_firewall" "main_instance_firewall" {}

resource "linode_firewall_device" "main_instance_firewall_devices" {}

