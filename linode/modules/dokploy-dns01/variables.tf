variable "resource_prefix" {
  type        = string
  description = "Prefix used to label the Linode token (e.g., 'example-com')."
}

variable "instance_ip" {
  type        = string
  description = "Public IPv4 of the dokploy instance to configure."
}

variable "email" {
  type        = string
  description = "Email address registered with Let's Encrypt."
}

variable "hostname_tld" {
  type        = string
  description = "Apex domain the wildcard certificate is issued for (main + *.<hostname_tld>)."
}

variable "deploy_user" {
  type        = string
  description = "Non-root sudoer used for SSH-tunneled Dokploy admin calls. Home directory is /home/<deploy_user>."
}
