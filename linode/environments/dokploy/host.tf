locals {
  ssh_config  = file("${path.root}/../production/dokploy.sshconfig")
  instance_id = regex("(?m)^\\s*HostKeyAlias dokploy-([0-9]+)$", local.ssh_config)[0]
  instance_ip = regex("(?m)^\\s*HostName ([0-9.]+)$", local.ssh_config)[0]
}

resource "terraform_data" "host" {
  triggers_replace = {
    instance_id = local.instance_id
    instance_ip = local.instance_ip
    key_hash    = sha256(var.DOKPLOY_API_KEY)
  }

  provisioner "local-exec" {
    environment = {
      API_KEY = var.DOKPLOY_API_KEY
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      printf %s "$API_KEY" | ssh -F ../production/dokploy.sshconfig -o BatchMode=yes dokploy-prod \
        'sudo -n install -m 0600 -o root -g root /dev/stdin /root/.dokploy-api-key.next && sudo -n mv -f /root/.dokploy-api-key.next /root/.dokploy-api-key'
    EOT
  }

  provisioner "local-exec" {
    environment = {
      API_KEY = var.DOKPLOY_API_KEY
      BODY    = jsonencode({ serverIp = local.instance_ip })
    }
    command = "curl -fsS '${local.dokploy_api_base}/settings.updateServerIp' -H \"x-api-key: $API_KEY\" -H 'Content-Type: application/json' --data \"$BODY\" >/dev/null"
  }
}
