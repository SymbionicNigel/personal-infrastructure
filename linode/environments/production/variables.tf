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
