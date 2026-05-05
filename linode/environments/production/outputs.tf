output "instance_ip" {
  value       = module.dokploy-instance.instance_ip
  description = "Public IPv4 address of the Dokploy instance"
}

output "api_key_file" {
  value       = module.dokploy-instance.api_key_file
  description = "Local path to the retrieved Dokploy API key"
}
