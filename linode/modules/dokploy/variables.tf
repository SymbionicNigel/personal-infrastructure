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

variable "EMAIL_ADDRESS" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Email used by Traefik for certificate issuance."
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
  description = "Dokploy release tag used to select the version-specific installation script."
}

variable "deploy_user" {
  type        = string
  nullable    = false
  description = "Non-root sudoer created by cloud-init and used for SSH-tunneled Dokploy admin calls. Home directory is /home/<deploy_user>."
  default     = "deploy"
}

variable "backup" {
  type = object({
    bucket        = string
    endpoint      = string
    access_key    = string
    secret_key    = string
    gpg_recipient = string
  })
  sensitive   = true
  nullable    = false
  description = "Shared backup destination and ACME encryption recipient."
}
