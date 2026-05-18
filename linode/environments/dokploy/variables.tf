variable "DOKPLOY_API_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Dokploy API key generated during cloud-init"
}

variable "HOSTNAME_TLD" {
  type        = string
  nullable    = false
  description = "The Hostname and TLD used to route to services"
}
