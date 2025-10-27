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

variable "WEBSITE_INSTANCE_IP" {
  type        = string
  nullable    = false
  description = "The IP which A records for HOSTNAME_TLD to point to"
}

variable "TAGS" {
  type        = set(string)
  nullable    = false
  description = "A base set of tags to apply to all resources in this module"
}
