output "instance_ip" {
  value = one(linode_instance.dokploy_main.ipv4)
}

output "api_key_file" {
  value       = "${path.root}/.dokploy-api-key"
  description = "Local path to the retrieved Dokploy API key"
}
