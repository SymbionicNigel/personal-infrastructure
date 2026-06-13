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
