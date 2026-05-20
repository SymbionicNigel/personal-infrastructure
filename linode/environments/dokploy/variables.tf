variable "DOKPLOY_API_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Dokploy API key generated during cloud-init"
}
