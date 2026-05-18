variable "label" {
  type        = string
  description = "Firewall label as displayed in the Linode UI."
}

variable "tags" {
  type    = list(string)
  default = []
}

variable "linode_ids" {
  type        = list(number)
  description = "Linode IDs to attach the firewall to."
}
