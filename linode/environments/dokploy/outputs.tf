output "project_id" {
  value       = dokploy_project.main.id
  description = "ID of the primary Dokploy project"
}

output "janus_application_id" {
  value       = dokploy_application.janus.id
  description = "ID of the janus (whoami) smoke-test application"
}
