variable "instance_ip" {
  type        = string
  nullable    = false
  description = "IPv4 address of the Dokploy instance hosting the dokploy-postgres container"
}

variable "bucket_name" {
  type        = string
  nullable    = false
  description = "Name of the Object Storage bucket to back up into"
}

variable "endpoint" {
  type        = string
  nullable    = false
  description = "S3 endpoint hostname for the backups bucket"
}

variable "gpg_recipient" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt backups. Public key must already be on the host (pushed by acme-backup)."
}
