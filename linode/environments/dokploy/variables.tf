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
