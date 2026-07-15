output "cloud_auth_key" {
  value       = tailscale_tailnet_key.cloud.key
  sensitive   = true
  description = "Auth key for the Linode host (tag:dokploy)"
}

output "compute_auth_key" {
  value       = tailscale_tailnet_key.compute.key
  sensitive   = true
  description = "Auth key for the i7 (tag:mc-compute), for bootstrap.sh"
}

output "gateway_auth_key" {
  value       = tailscale_tailnet_key.gateway.key
  sensitive   = true
  description = "Auth key for the Pi (tag:mc-gateway), for bootstrap.sh"
}
