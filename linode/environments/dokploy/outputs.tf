output "project_id" {
  value       = dokploy_project.main.id
  description = "ID of the primary Dokploy project"
}

output "compose_id" {
  value       = dokploy_compose.stack.id
  description = "ID of the deployed compose stack (contains all services)"
}
