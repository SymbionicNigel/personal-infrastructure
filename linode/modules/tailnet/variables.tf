variable "home_lan_cidr" {
  type        = string
  nullable    = false
  description = "Home LAN CIDR the Pi subnet-router advertises, e.g. 192.168.1.0/24"
}

variable "game_port_range" {
  type        = string
  default     = "25565-25600"
  description = "Compute-node port range the cloud host may reach for game traffic"
}

variable "key_expiry_seconds" {
  type        = number
  default     = 7776000 # 90 days, the provider maximum
  description = "Lifetime of generated tagged auth keys"
}
