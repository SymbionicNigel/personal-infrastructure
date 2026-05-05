variable "region" {
  type        = string
  nullable    = false
  description = "The Linode region which all infrastructure will be located"
}

variable "HOSTNAME_TLD" {
  type        = string
  nullable    = false
  description = "The Hostname and TLD used to route to the main application"
}

variable "TAGS" {
  type        = set(string)
  nullable    = false
  description = "A base set of tags to apply to all resources in this module"
}

variable "DOKPLOY_ADMIN_EMAIL" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Email for the auto-created Dokploy admin account"
}

variable "DOKPLOY_ADMIN_PASSWORD" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Password for the auto-created Dokploy admin account"
}

variable "DOKPLOY_VERSION" {
  type        = string
  nullable    = false
  description = "Pinned Dokploy release tag (e.g. v0.27.0). Honored by https://dokploy.com/install.sh via the DOKPLOY_VERSION env var. Pinning here avoids surprise upgrades on rebuild."
}
