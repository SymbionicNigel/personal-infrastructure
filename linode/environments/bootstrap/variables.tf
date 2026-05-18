variable "linode_token" {
  description = "Linode API Token"
  type        = string
  sensitive   = true
}

variable "region" {
  description = "Object Storage region"
  type        = string
}

variable "bucket_name" {
  description = "Name for the state bucket"
  type        = string
}
