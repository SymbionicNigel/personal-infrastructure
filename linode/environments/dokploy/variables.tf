variable "DOKPLOY_API_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Dokploy API key generated during cloud-init"
}

variable "ASTARTE_IMAGE_TAG" {
  type        = string
  nullable    = false
  description = "Image tag (git SHA in CI, 'latest' for manual applies) for the astarte image on GHCR."
  default     = "latest"
}

variable "IRIS_IMAGE_TAG" {
  type        = string
  nullable    = false
  description = "Image tag (git SHA in CI, 'latest' for manual applies) for the iris image on GHCR."
  default     = "latest"
}

variable "GHCR_OWNER" {
  type        = string
  nullable    = false
  description = "GHCR namespace (lowercased repo owner) for service image paths. Supplied by dokploy.sh from the repo owner."
}

variable "DOKPLOY_PROJECT_NAME" {
  type        = string
  nullable    = false
  description = "Name of the Dokploy project that holds the managed services stack."
  default     = "services"
}

variable "DOKPLOY_BACKUP_BUCKET" {
  type        = string
  nullable    = false
  description = "Object Storage bucket for Dokploy backups (production dokploy_backups_bucket output)."
}

variable "DOKPLOY_BACKUP_ENDPOINT" {
  type        = string
  nullable    = false
  description = "S3 endpoint host for the backup bucket."
}

variable "DOKPLOY_BACKUP_REGION" {
  type        = string
  nullable    = false
  description = "Region of the backup bucket."
}

variable "DOKPLOY_BACKUP_ACCESS_KEY_ID" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Access key ID for the backup bucket."
}

variable "DOKPLOY_BACKUP_SECRET_ACCESS_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Secret access key for the backup bucket."
}

variable "GHCR_PAT" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Fine-grained PAT (Packages: Read-only) for the ghcr.io registry."
}
