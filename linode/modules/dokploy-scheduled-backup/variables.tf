variable "api_base" {
  type        = string
  nullable    = false
  description = "Dokploy API base URL, e.g. https://vulcan.<tld>/api"
}

variable "api_key" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Dokploy API key (x-api-key). Must belong to an admin user."
}

variable "destination_id" {
  type        = string
  nullable    = false
  description = "ID of the dokploy_backup_destination to upload to."
}

variable "database_type" {
  type        = string
  nullable    = false
  description = "Dokploy databaseType: web-server | postgres | mysql | mariadb | mongo | libsql."
}

variable "database" {
  type        = string
  nullable    = false
  description = "Database name field. For web-server backups this is \"dokploy\"."
}

variable "prefix" {
  type        = string
  nullable    = false
  description = "S3 key prefix namespacing this backup (the shared-destination directory)."
}

variable "schedule" {
  type        = string
  nullable    = false
  description = "Cron schedule, e.g. \"0 4 * * *\"."
}

variable "enabled" {
  type        = bool
  default     = true
  description = "Whether the schedule is enabled."
}

variable "keep_latest_count" {
  type        = number
  default     = null
  description = "Optional retention: keep only the N most recent backups."
}

variable "extra_payload_json" {
  type        = string
  default     = "{}"
  description = "JSON object of extra backup.create fields for non-web-server kinds (composeId, serviceName, metadata). Merged into the payload."
}
