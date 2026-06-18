terraform {
  required_providers {
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

# The API key's own user id; required on web-server backup payloads.
data "http" "current_user" {
  url    = "${var.api_base}/trpc/user.get"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.api_key
    "Content-Type" = "application/json"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "user.get returned ${self.status_code}: ${self.response_body}"
    }
  }
}

# Existing backups, read at plan time, to decide whether to create. NOT
# dependent on the create resource, so it reflects pre-apply state.
data "http" "existing" {
  url    = "${var.api_base}/trpc/user.getBackups"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.api_key
    "Content-Type" = "application/json"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "user.getBackups returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  user_id = jsondecode(data.http.current_user.response_body).result.data.json.userId

  backup_payload = merge(
    {
      destinationId = var.destination_id
      database      = var.database
      prefix        = var.prefix
      schedule      = var.schedule
      databaseType  = var.database_type
      enabled       = var.enabled
      userId        = local.user_id
    },
    var.keep_latest_count == null ? {} : { keepLatestCount = var.keep_latest_count },
    jsondecode(var.extra_payload_json),
  )

  existing_ids = [
    for b in jsondecode(data.http.existing.response_body).result.data.json.backups :
    b.backupId if b.databaseType == var.database_type && b.prefix == var.prefix
  ]
  exists = length(local.existing_ids) > 0
}

# Create only when absent (count = 0 when one already matches). Dokploy's
# backup.create is a plain insert, so the count guard is what prevents
# duplicate schedules across re-applies.
resource "terraform_data" "backup" {
  count = local.exists ? 0 : 1

  provisioner "local-exec" {
    environment = { DOKPLOY_API_KEY = var.api_key }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      curl -sf -X POST "${var.api_base}/backup.create" \
        -H "x-api-key: $DOKPLOY_API_KEY" \
        -H "Content-Type: application/json" \
        --data '${jsonencode(local.backup_payload)}' >/dev/null
      echo "dokploy-scheduled-backup: created ${var.database_type} backup at prefix ${var.prefix}"
    EOT
  }
}

# Read the backup id back into state. depends_on defers this to apply, after
# create, so a brand-new backup is captured in the same apply.
data "http" "lookup" {
  url    = "${var.api_base}/trpc/user.getBackups"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.api_key
    "Content-Type" = "application/json"
  }
  depends_on = [terraform_data.backup]
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "user.getBackups returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  matched_ids = [
    for b in jsondecode(data.http.lookup.response_body).result.data.json.backups :
    b.backupId if b.databaseType == var.database_type && b.prefix == var.prefix
  ]
}
