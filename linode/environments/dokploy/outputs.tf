output "project_id" {
  value       = dokploy_project.main.id
  description = "ID of the primary Dokploy project"
}

output "environment_id" {
  value       = dokploy_environment.stack.id
  description = "ID of the Terraform-managed environment that owns the compose stack"
}

output "compose_id" {
  value       = dokploy_compose.stack.id
  description = "ID of the deployed compose stack (contains all services)"
}
