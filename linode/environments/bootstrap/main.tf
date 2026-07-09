terraform {
  required_providers {
    linode = {
      source  = "linode/linode"
      version = "4.0.0"
    }
  }
}

provider "linode" {
  token = var.linode_token
}

resource "linode_object_storage_key" "terraform_bootstrap_key" {
  label   = "terraform-bootstrap-access"
  regions = [var.region]
}

resource "linode_object_storage_bucket" "terraform_state" {
  region     = var.region
  label      = var.bucket_name
  versioning = true
  acl        = "private"

  depends_on = [linode_object_storage_key.terraform_bootstrap_key]

  access_key = linode_object_storage_key.terraform_bootstrap_key.access_key
  secret_key = linode_object_storage_key.terraform_bootstrap_key.secret_key

  lifecycle_rule {
    abort_incomplete_multipart_upload_days = 7
    noncurrent_version_expiration {
      days = 90
    }
    enabled = true
  }
}

resource "linode_object_storage_key" "terraform_state_key" {
  label = "terraform-state-access"

  bucket_access {
    bucket_name = var.bucket_name
    region      = var.region
    permissions = "read_write"
  }
  depends_on = [linode_object_storage_bucket.terraform_state]
}
