variable "resource_prefix" {
  type        = string
  description = "Prefix used to label the Linode token (e.g., 'symbionic-tech')."
}

variable "instance_ip" {
  type        = string
  description = "Public IPv4 of the dokploy instance to configure."
}

variable "email" {
  type        = string
  description = "Email address registered with Let's Encrypt."
}
