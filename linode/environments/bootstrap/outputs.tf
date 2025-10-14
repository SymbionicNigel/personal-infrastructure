output "bucket_name" {
  value = linode_object_storage_bucket.terraform_state.label
}

output "region" {
  value = linode_object_storage_bucket.terraform_state.region
}

output "endpoint" {
  value     = linode_object_storage_bucket.terraform_state.endpoint
  sensitive = true
}

output "access_key" {
  value     = linode_object_storage_key.terraform_state_key.access_key
  sensitive = true
}

output "secret_key" {
  value     = linode_object_storage_key.terraform_state_key.secret_key
  sensitive = true
}
