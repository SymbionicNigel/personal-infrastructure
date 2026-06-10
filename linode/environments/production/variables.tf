variable "EMAIL_ADDRESS" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Email address in control of the domain below"
}

variable "HOSTNAME_TLD" {
  type        = string
  nullable    = false
  description = "The Hostname and TLD used to route to the main application"
}

variable "REGION" {
  type        = string
  nullable    = false
  description = "The Linode region which all infrastructure will be located"
}

variable "LINODE_TOKEN" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Linode API token"
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

variable "DASHBOARD_SUBDOMAIN" {
  type        = string
  nullable    = false
  default     = "vulcan"
  description = "Subdomain (under HOSTNAME_TLD) where the Dokploy dashboard will be served over HTTPS"
}

variable "DOKPLOY_VERSION" {
  type        = string
  nullable    = false
  default     = "v0.29.4"
  description = "Pinned Dokploy release tag. Defaulted so rebuilds are reproducible — only override (via TF_VAR_DOKPLOY_VERSION) for one-off testing of a different version. To bump the production pin, edit the default here and commit."
}

variable "GPG_RECIPIENT" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt acme.json backups. Public key must be in the deploy machine's gpg keyring."
}

variable "GHCR_USER" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "GitHub username used for `docker login ghcr.io` on the host so Dokploy can pull private images."
}

variable "GHCR_PAT" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Fine-grained PAT (Packages: Read-only) the host uses to authenticate to GHCR for image pulls."
}
