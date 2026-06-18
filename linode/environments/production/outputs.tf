output "instance_ip" {
  value       = module.dokploy-instance.instance_ip
  description = "Public IPv4 address of the Dokploy instance"
}

output "api_key_file" {
  value       = module.dokploy-instance.api_key_file
  description = "Local path to the retrieved Dokploy API key"
}

output "dokploy_backups_bucket" {
  value       = linode_object_storage_bucket.infra_backups.label
  description = "Bucket for Dokploy native backups; copy into the dokploy env .env"
}

output "dokploy_backups_endpoint" {
  value       = linode_object_storage_bucket.infra_backups.s3_endpoint
  description = "S3 endpoint host for Dokploy native backups"
}

output "dokploy_backups_region" {
  value       = linode_object_storage_bucket.infra_backups.region
  description = "Bucket region for Dokploy native backups"
}

output "dokploy_backups_access_key" {
  value       = module.acme_backup.access_key
  sensitive   = true
  description = "Access key ID for Dokploy native backups"
}

output "dokploy_backups_secret_key" {
  value       = module.acme_backup.secret_key
  sensitive   = true
  description = "Secret access key for Dokploy native backups"
}
