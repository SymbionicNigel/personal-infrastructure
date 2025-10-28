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
