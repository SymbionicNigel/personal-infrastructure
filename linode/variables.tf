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

variable "ENVIRON" {
  type = string
  validation {
    condition     = contains(["dev", "test", "prod"], var.ENVIRON)
    error_message = "Only acceptible values are dev, test, and prod."
  }
  description = "The name for the deployment made by this workspace"
}

variable "HCP_TOKEN" {
  type        = string
  nullable    = true
  sensitive   = true
  description = "The user token generated to allow this project to interact with HCP Terraform in the case terraform login is not used."
}

variable "LINODE_TOKEN" {
  type        = string
  description = ""
  nullable    = false
  sensitive   = false
}

variable "TEMPRARY_SITE_INSTANCE_IP" {
  type        = string
  sensitive   = true
  nullable    = false
  default     = ""
  description = "(optional) describe your variable"
}
