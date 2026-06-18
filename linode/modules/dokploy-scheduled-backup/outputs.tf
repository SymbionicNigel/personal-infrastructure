output "backup_id" {
  value       = try(local.matched_ids[0], null)
  description = "backupId of the managed scheduled backup (null if not found)."
}
