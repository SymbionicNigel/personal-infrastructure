terraform {
  required_providers {
    linode = {
        source = "linode/linode"
    }
  }
}

provider "linode" {}

resource "linode_instance" "fedora-test" {
  watchdog_enabled = true
}

resource "linode_domain" "name" {}