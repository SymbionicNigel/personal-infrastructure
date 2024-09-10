terraform {
  required_providers {
    linode = {
        source = "linode/linode"
        version = "2.27.0"
    }
  }
}

provider "linode" {
  config_path = "~/.config/linode-cli"
  config_profile = ""
  token = ""
}

# TODO: Handle creating primary instance
# TODO: handle restricting network access
