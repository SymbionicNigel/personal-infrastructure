variable "region" {
  type        = string
  nullable    = false
  description = "Linode region for the backup bucket"
}

variable "resource_prefix" {
  type        = string
  nullable    = false
  description = "Sanitized prefix (dots replaced with dashes) used to name the access key"
}

variable "bucket_name" {
  type        = string
  nullable    = false
  description = "Name of the Object Storage bucket to back up into (created by the calling environment)"
}

variable "gpg_recipient" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt backups. Public key must be in the deploy machine's keyring."
}

variable "instance_ip" {
  type        = string
  nullable    = false
  description = "IPv4 address of the Dokploy instance to configure and restore onto"
}

variable "endpoint" {
  type        = string
  nullable    = false
  description = "S3 endpoint hostname for the backups bucket (e.g. us-ord-1.linodeobjects.com). Pass linode_object_storage_bucket.<bucket>.s3_endpoint so cluster naming stays in the provider's hands."
}

variable "deploy_user" {
  type        = string
  nullable    = false
  description = "Non-root sudoer used for SSH-tunneled Dokploy admin calls. Home directory is /home/<deploy_user>."
}
