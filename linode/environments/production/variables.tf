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
  default     = "v0.31.2"
  description = "Pinned Dokploy release tag for new host provisioning. Override with TF_VAR_DOKPLOY_VERSION. Changing this value does not upgrade an existing installation."
}

variable "GPG_RECIPIENT" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt acme.json backups. Public key must be in the deploy machine's gpg keyring."
}

variable "DEPLOY_USER" {
  type        = string
  nullable    = false
  default     = "deploy"
  description = "Non-root sudoer created by cloud-init and used for SSH-tunneled Dokploy admin calls. Threaded into every module that SSHes back into the host."
}

variable "TAILSCALE_OAUTH_CLIENT_ID" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Tailscale OAuth client ID (scopes: auth keys, dns, policy file, devices)"
}

variable "TAILSCALE_OAUTH_CLIENT_SECRET" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Tailscale OAuth client secret"
}

variable "HOME_LAN_CIDR" {
  type        = string
  nullable    = false
  description = "Home LAN CIDR advertised by the Pi subnet router"
}
