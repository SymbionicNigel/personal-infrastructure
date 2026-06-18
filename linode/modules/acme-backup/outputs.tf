output "access_key" {
  value       = linode_object_storage_key.infra_backups.access_key
  sensitive   = true
  description = "Access key ID for the infra-backups bucket key."
}

output "secret_key" {
  value       = linode_object_storage_key.infra_backups.secret_key
  sensitive   = true
  description = "Secret access key for the infra-backups bucket key."
}
