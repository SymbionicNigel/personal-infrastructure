output "instance_ip" {
  value = one(linode_instance.dokploy_main.ipv4)
}

output "api_key_file" {
  value       = "${path.root}/.dokploy-api-key"
  description = "Local path to the retrieved Dokploy API key"
}

output "instance_id" {
  description = "Numeric Linode ID of the dokploy_main instance, used to attach Cloud Firewalls and reserved IPs."
  value       = linode_instance.dokploy_main.id
}

output "deploy_user" {
  description = "Name of the cloud-init sudoer used for SSH-tunneled Dokploy admin calls. Pass to modules that SSH back into the host."
  value       = var.deploy_user
}
