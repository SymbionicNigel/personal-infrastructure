# Dokploy Control-Plane Backup & Operational Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Three Dokploy operational improvements, all as-code:

1. Replace the hand-rolled `dokploy-postgres-backup` module with Dokploy's native
   **web-server backup** (dumps the `dokploy-postgres` control-plane DB *and*
   `/etc/dokploy`), and ship the reusable pattern future per-service DB backups use
   (Tasks 0–5).
2. Migrate GHCR pull auth from `null_resource.ghcr_login` to a **Dokploy registry**,
   whose creation runs a host-global `docker login` (Task 6).
3. Enable **Traefik request logging** (JSON) + Dokploy's log-cleanup cron (Task 7).

**Architecture:** None of these three has a Terraform provider resource (v0.4.0
adds only `dokploy_backup_destination` and `dokploy_volume_backup`). Each is
driven over Dokploy's HTTP API from the `linode/environments/dokploy` step —
where the API host + key are already live — using the same `data "http"` +
`local-exec` pattern the repo already uses for `compose.deploy`. Reads use the
tRPC GET contract; writes use the OpenAPI REST mount (`POST /api/<proc>`, plain
JSON). Request logging is the exception: because we own `traefik.yml` via the
`dokploy-dns01` module, the `accessLog` block is baked into that managed config
rather than toggled via API (which would drift on the next module apply).

**Tech Stack:** Terraform (`hashicorp/http`, `j0bIT/dokploy` 0.4.0), Dokploy
HTTP/tRPC API, bash/curl in `local-exec`, Linode Object Storage, Traefik.

**Parent context:** The control-plane backup shares one S3 destination and one
dedicated Object Storage key with the Pelican volume backup
([2026-06-15-mc-cloud-management-plane-pelican-plan.md](./2026-06-15-mc-cloud-management-plane-pelican-plan.md)).
The brainstorming conversation is the spec.

---

## Verified API facts (against Dokploy source)

- **Web-server backup** runs `pg_dump -Fc -U dokploy -d dokploy` of the
  `dokploy-postgres` container **plus** an `rsync` of `/etc/dokploy` (excluding
  `volume-backups/`), zips both, and `rclone copyto`s to the destination. Strictly
  more than the custom module (which never captured `/etc/dokploy`).
- `backup.create` input for a web-server backup needs: `destinationId`,
  `database` (`"dokploy"`), `prefix`, `schedule` (cron), `databaseType:
  "web-server"`, `enabled`, and **`userId`** — web-server backups attach to the
  creating user and are listed only via `user.getBackups`.
- The API user id comes from `user.get` (returns the member; `…json.userId`).
- `backup.create` is a plain insert (random id, no name field, no upsert) → not
  idempotent; dedupe must be done by us, keyed on `databaseType` + `prefix`.
- Reads use the tRPC GET contract proven by `project.one`:
  `GET /api/trpc/<proc>` → parse `.result.data.json`. Writes use the OpenAPI REST
  mount proven by `compose.deploy`: `POST /api/<proc>` with a **plain JSON** body
  (no `{"json":…}` envelope). Both authenticate with the `x-api-key` header.
- `user.getBackups` returns `member.user`, so its backups array is at
  `…json.backups`.
- A one-off run for verification is `backup.manualBackupWebServer` (`{backupId}`).
- Restore is `restoreBackupWithLogs` — a **subscription**, not curl-friendly; it
  is an operator action in the Web Server → Backups UI.
- **Registry:** `createRegistry` runs a host-global `docker login` —
  for a local server it executes `safeDockerLoginCommand` via `execAsync` because
  the API always sets `registryType: "cloud"`. That login lands in
  `/root/.docker/config.json`, which is what compose/`stack deploy` pulls use, so
  it replaces `null_resource.ghcr_login`. `registry.create` input: `registryName`,
  `username`, `password`, `registryUrl`, `registryType: "cloud"`, optional
  `imagePrefix`. No name uniqueness → dedupe on `registryName` via `registry.all`.
  `removeRegistry` runs `docker logout`; `updateRegistry` re-runs the login.
- **Request logging:** `settings.toggleRequests({enable:true})` writes
  `accessLog: { filePath: /etc/dokploy/traefik/dynamic/access.log, format: json,
  bufferingSize: 100 }` into the main Traefik config. We replicate that block in
  the `dokploy-dns01` module's managed `traefik.yml` instead (API toggle would be
  clobbered on the next module apply). The log-cleanup cron is set with
  `settings.updateLogCleanup({cronExpression})`.

---

## File structure

Created:

```text
linode/modules/dokploy-scheduled-backup/variables.tf   # module inputs (Task 1)
linode/modules/dokploy-scheduled-backup/main.tf         # check-then-create + read-back (Task 1)
linode/modules/dokploy-scheduled-backup/outputs.tf      # backup_id (Task 1)
```

Modified:

```text
linode/environments/dokploy/main.tf        # destination + backup module + registry + log-cleanup (Tasks 0,2,6,7)
linode/environments/dokploy/variables.tf   # destination + GHCR cred vars (Tasks 0,6)
linode/modules/dokploy-dns01/main.tf        # accessLog block in traefik_yaml (Task 7)
linode/environments/production/base.tf      # remove custom backup module + ghcr_login (Tasks 5,6)
linode/environments/production/variables.tf # remove GHCR_USER/GHCR_PAT (moved to dokploy env) (Task 6)
linode/README.md                            # GHCR-via-registry + TLS-cert note (Tasks 6,7)
linode/modules/dokploy-postgres-backup/RESTORE.md  # rewrite for native restore, or fold into README (Task 4)
```

Deleted:

```text
linode/modules/dokploy-postgres-backup/main.tf       # (Task 5)
linode/modules/dokploy-postgres-backup/variables.tf  # (Task 5)
linode/modules/dokploy-postgres-backup/RESTORE.md    # after content moves in Task 4 (Task 5)
```

---

## Task 0: Shared destination prerequisite (skip if Pelican plan already did it)

The `dokploy_backup_destination.linode` resource, the provider `0.4.0` bump, and
the dedicated non-rotating Object Storage key are **shared** with the Pelican
plan (its Task 7 + Task 8 Steps 1 & 3). Only one plan defines them.

- [ ] **Step 1: Check whether the shared destination already exists**

Run:
```bash
grep -n 'dokploy_backup_destination' linode/environments/dokploy/main.tf || echo ABSENT
grep -n 'version = "0.4.0"' linode/environments/dokploy/main.tf || echo PROVIDER_NOT_BUMPED
```
- If both are present (Pelican plan already implemented): **skip the rest of Task
  0** and go to Task 1; the module will reference the existing
  `dokploy_backup_destination.linode`.
- If `ABSENT`/`PROVIDER_NOT_BUMPED`: do Steps 2–4 (these mirror Pelican plan
  Task 7 and Task 8 Steps 1–3; if you implement them here, the Pelican plan must
  reference these resources instead of redefining them).

- [ ] **Step 2: Add the dedicated key + outputs in the production env**

Implement Pelican plan **Task 7** verbatim (a non-rotating
`linode_object_storage_key.dokploy_backups` against
`linode_object_storage_bucket.infra_backups`, plus the
`dokploy_backups_{bucket,endpoint,region,access_key,secret_key}` outputs), then
`bash production.sh` and capture the five outputs.

- [ ] **Step 3: Bump the provider and add the destination cred vars (dokploy env)**

In `linode/environments/dokploy/main.tf` set the dokploy provider to `0.4.0`:
```hcl
dokploy = {
  source  = "j0bIT/dokploy"
  version = "0.4.0"
}
```
Add to `linode/environments/dokploy/variables.tf`:
```hcl
variable "DOKPLOY_BACKUP_BUCKET" {
  type        = string
  nullable    = false
  description = "Object Storage bucket for Dokploy backups (production dokploy_backups_bucket output)."
}

variable "DOKPLOY_BACKUP_ENDPOINT" {
  type        = string
  nullable    = false
  description = "S3 endpoint host for the backup bucket."
}

variable "DOKPLOY_BACKUP_REGION" {
  type        = string
  nullable    = false
  description = "Region of the backup bucket."
}

variable "DOKPLOY_BACKUP_ACCESS_KEY_ID" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Access key ID for the backup bucket."
}

variable "DOKPLOY_BACKUP_SECRET_ACCESS_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Secret access key for the backup bucket."
}
```
Append the five `TF_VAR_DOKPLOY_BACKUP_*` values (from Step 2) to the dokploy
env's chezmoi-managed `.env`:
```bash
bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --edit \
  linode/environments/dokploy/.env
```

- [ ] **Step 4: Add the shared destination resource to the dokploy env `main.tf`**

```hcl
resource "dokploy_backup_destination" "linode" {
  name              = "linode-object-storage"
  bucket            = var.DOKPLOY_BACKUP_BUCKET
  endpoint          = var.DOKPLOY_BACKUP_ENDPOINT
  region            = var.DOKPLOY_BACKUP_REGION
  access_key_id     = var.DOKPLOY_BACKUP_ACCESS_KEY_ID
  secret_access_key = var.DOKPLOY_BACKUP_SECRET_ACCESS_KEY
}
```

---

## Task 1: Reusable `dokploy-scheduled-backup` module

A module that creates one Dokploy scheduled backup over the API, idempotently,
and returns its `backupId`. Web-server is the only kind wired now; compose-DB
backups reuse it later via `extra_payload_json` (e.g. `composeId`, `serviceName`,
`metadata`).

**Files:**
- Create: `linode/modules/dokploy-scheduled-backup/variables.tf`
- Create: `linode/modules/dokploy-scheduled-backup/main.tf`
- Create: `linode/modules/dokploy-scheduled-backup/outputs.tf`

- [ ] **Step 1: Write `variables.tf`**

```hcl
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
```

- [ ] **Step 2: Write `main.tf`**

```hcl
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
```

- [ ] **Step 3: Write `outputs.tf`**

```hcl
output "backup_id" {
  value       = try(local.matched_ids[0], null)
  description = "backupId of the managed scheduled backup (null if not found)."
}
```

- [ ] **Step 4: Validate the module compiles**

Run:
```bash
terraform -chdir=linode/modules/dokploy-scheduled-backup init -backend=false
terraform -chdir=linode/modules/dokploy-scheduled-backup validate
terraform fmt linode/modules/dokploy-scheduled-backup
```
Expected: `Success! The configuration is valid.`

---

## Task 2: Wire the control-plane web-server backup (dokploy env)

**Files:**
- Modify: `linode/environments/dokploy/main.tf`

- [ ] **Step 1: Add the module call** (after `dokploy_backup_destination.linode`)

```hcl
# Native control-plane backup: dumps the dokploy-postgres DB + /etc/dokploy to
# the shared destination nightly. Replaces the dokploy-postgres-backup module.
module "control_plane_backup" {
  source = "../../modules/dokploy-scheduled-backup"

  api_base       = "https://vulcan.${local.hostname_tld}/api"
  api_key        = var.DOKPLOY_API_KEY
  destination_id = dokploy_backup_destination.linode.id
  database_type  = "web-server"
  database       = "dokploy"
  prefix         = "control-plane/"
  schedule       = "0 4 * * *" # daily 04:00 UTC; offset from Pelican's 03:00
}
```

- [ ] **Step 2: Validate**

Run:
```bash
cd linode/environments/dokploy
terraform fmt && terraform validate
```
Expected: `Success! The configuration is valid.`

---

## Task 3: Apply and verify the backup runs

- [ ] **Step 1: Apply**

Run:
```bash
cd linode/environments/dokploy
bash dokploy.sh
```
Expected: apply creates `dokploy_backup_destination.linode` (if Task 0 added it)
and `module.control_plane_backup.terraform_data.backup[0]`; the
`module.control_plane_backup.backup_id` output is a non-null id.

- [ ] **Step 2: Confirm exactly one web-server backup exists (idempotency check)**

Re-run `bash dokploy.sh`. Expected: **no** new backup created (the `terraform_data`
resource is gone from the plan because `count` is now 0). Then:
```bash
curl -sf "https://vulcan.${TLD}/api/trpc/user.getBackups" \
  -H "x-api-key: $DOKPLOY_API_KEY" \
  | python3 -c 'import sys,json; b=json.load(sys.stdin)["result"]["data"]["json"]["backups"]; print([x for x in b if x["databaseType"]=="web-server"])'
```
Expected: exactly one web-server backup, prefix `control-plane/`.

- [ ] **Step 3: Trigger a one-off backup and confirm an object lands**

```bash
# TLD = the same hostname suffix used by local.hostname_tld
BID=$(curl -sf "https://vulcan.${TLD}/api/trpc/user.getBackups" -H "x-api-key: $DOKPLOY_API_KEY" \
      | python3 -c 'import sys,json;print(next(x["backupId"] for x in json.load(sys.stdin)["result"]["data"]["json"]["backups"] if x["databaseType"]=="web-server"))')
curl -sf -X POST "https://vulcan.${TLD}/api/backup.manualBackupWebServer" \
  -H "x-api-key: $DOKPLOY_API_KEY" -H "Content-Type: application/json" \
  --data "{\"backupId\":\"$BID\"}"

cd linode/environments/production
s3cmd ls "s3://$(terraform output -raw dokploy_backups_bucket)/" --recursive | grep -i control-plane
```
Expected: a `webserver-backup-<timestamp>.zip` object under the `control-plane/`
prefix.

> If `backup.manualBackupWebServer` returns 404, trigger the backup from the
> panel UI (Web Server → Backups → Run) instead; the schedule itself is already
> active regardless.

---

## Task 4: Document the native restore procedure

Restore is an operator UI action (the API path is a subscription). Replace the
old encrypted-`s3cmd` restore doc.

**Files:**
- Modify/rewrite: `linode/modules/dokploy-postgres-backup/RESTORE.md` (content
  moves to the dokploy env README in the next step) — or write the note directly
  into `linode/README.md` under a "Control-plane backup/restore" subsection.

- [ ] **Step 1: Write the restore note**

Content to capture:
```text
Control-plane backup = Dokploy's native Web Server backup: nightly pg_dump of
dokploy-postgres + /etc/dokploy, zipped to s3://<infra-backups>/<appName>/control-plane/.
Managed by module.control_plane_backup (dokploy env), schedule 0 4 * * * UTC.

Restore (operator, in the panel): Web Server → Backups → select the
webserver-backup-<ts>.zip from the destination → Restore. Dokploy replaces
/etc/dokploy and the dokploy database with the archive contents, then restarts.
No client-side decryption needed (no GPG; rely on bucket-side encryption).
```

- [ ] **Step 2: Lint**

Run: `npx markdownlint-cli linode/README.md`
Expected: no errors.

---

## Task 5: Retire the custom `dokploy-postgres-backup` module

Only after Task 3 verified a native object landed.

**Files:**
- Modify: `linode/environments/production/base.tf` (remove the module block)
- Delete: `linode/modules/dokploy-postgres-backup/` (all files)

- [ ] **Step 1: Remove the module block** from `linode/environments/production/base.tf`

Delete the `module "dokploy_postgres_backup" { … }` block (and its preceding
comment). Leave `var.GPG_RECIPIENT` and `module.acme_backup` untouched — they are
used elsewhere.

- [ ] **Step 2: Apply production to drop the null_resource from state**

Run:
```bash
cd linode/environments/production
bash production.sh
```
Expected: plan shows `module.dokploy_postgres_backup.null_resource.configure_dokploy_pg_backup`
destroyed and nothing else unexpected.

- [ ] **Step 3: Clean the old units off the host** (Terraform won't; the
  provisioner wrote them but has no destroy-time cleanup)

Run (SSH via the existing `dokploy.sshconfig`):
```bash
ssh -F linode/environments/production/dokploy.sshconfig dokploy '
  sudo systemctl disable --now dokploy-pg-backup.timer dokploy-pg-backup.service 2>/dev/null || true
  sudo rm -f /etc/systemd/system/dokploy-pg-backup.timer \
             /etc/systemd/system/dokploy-pg-backup.service \
             /usr/local/sbin/dokploy-pg-backup.sh \
             /root/.dokploy-pg-backup.env
  sudo systemctl daemon-reload
  systemctl list-timers --all | grep -i dokploy-pg-backup || echo "timer gone"'
```
Expected: `timer gone`.

- [ ] **Step 4: Delete the module directory**

Run:
```bash
git rm -r linode/modules/dokploy-postgres-backup/
```

- [ ] **Step 5: Confirm nothing else references it**

Run:
```bash
grep -rn "dokploy-postgres-backup\|dokploy_postgres_backup\|dokploy-pg-backup" linode/ docs/ || echo "no references"
```
Expected: `no references`.

---

## Task 6: Migrate GHCR pull auth to a Dokploy registry

Replace `null_resource.ghcr_login` (production env, SSH `docker login`) with a
Dokploy `registry` created over the API in the dokploy env. Creating/updating the
registry runs a host-global `docker login ghcr.io`, which is what the compose
stack's `image: ghcr.io/...` pulls use. GHCR creds move from the production env to
the dokploy env.

**Files:**
- Modify: `linode/environments/dokploy/variables.tf` (add `GHCR_USER`, `GHCR_PAT`)
- Modify: `linode/environments/dokploy/main.tf` (registry wiring + deploy ordering)
- Modify: `.secrets/linode/environments/dokploy/encrypted_dot_env` (via chezmoi)
- Modify: `linode/environments/production/base.tf` (remove `null_resource.ghcr_login`)
- Modify: `linode/environments/production/variables.tf` (remove `GHCR_USER`, `GHCR_PAT`)

- [ ] **Step 1: Add the GHCR cred vars** to `linode/environments/dokploy/variables.tf`

```hcl
variable "GHCR_USER" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "GitHub username for the Dokploy ghcr.io registry (host docker login)."
}

variable "GHCR_PAT" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Fine-grained PAT (Packages: Read-only) for the ghcr.io registry."
}
```

- [ ] **Step 2: Add the registry wiring** to `linode/environments/dokploy/main.tf`

```hcl
# Read existing registries so we update-in-place (re-login) rather than create a
# duplicate — registry.create has no upsert and no name uniqueness.
data "http" "registries" {
  url    = "https://vulcan.${local.hostname_tld}/api/trpc/registry.all"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.DOKPLOY_API_KEY
    "Content-Type" = "application/json"
  }
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "registry.all returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  ghcr_registry_name = "ghcr"
  ghcr_registry_id = try(one([
    for r in jsondecode(data.http.registries.response_body).result.data.json :
    r.registryId if r.registryName == local.ghcr_registry_name
  ]), null)
}

# Create-or-update the ghcr registry. Either path runs `docker login ghcr.io` on
# the host (Dokploy sets registryType=cloud → execAsync). triggers_replace on the
# cred hash means a PAT rotation re-runs the login, preserving today's behaviour.
resource "terraform_data" "ghcr_registry" {
  triggers_replace = sha256(join("|", [var.GHCR_USER, var.GHCR_PAT]))

  provisioner "local-exec" {
    environment = {
      DOKPLOY_API_KEY = var.DOKPLOY_API_KEY
      GHCR_USER       = var.GHCR_USER
      GHCR_PAT        = var.GHCR_PAT
    }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      base="https://vulcan.${local.hostname_tld}/api"
      common=$(python3 -c 'import json,os;print(json.dumps({"registryName":"${local.ghcr_registry_name}","username":os.environ["GHCR_USER"],"password":os.environ["GHCR_PAT"],"registryUrl":"ghcr.io","registryType":"cloud"}))')
      rid='${local.ghcr_registry_id == null ? "" : local.ghcr_registry_id}'
      if [ -n "$rid" ]; then
        body=$(python3 -c 'import json,sys; d=json.loads(sys.argv[1]); d["registryId"]=sys.argv[2]; print(json.dumps(d))' "$common" "$rid")
        curl -sf -X POST "$base/registry.update" -H "x-api-key: $DOKPLOY_API_KEY" \
          -H "Content-Type: application/json" --data "$body" >/dev/null
        echo "ghcr registry updated (host re-logged in)"
      else
        curl -sf -X POST "$base/registry.create" -H "x-api-key: $DOKPLOY_API_KEY" \
          -H "Content-Type: application/json" --data "$common" >/dev/null
        echo "ghcr registry created (host logged in)"
      fi
    EOT
  }
}
```

- [ ] **Step 3: Make the compose deploy wait on the registry login**

In `linode/environments/dokploy/main.tf`, add `terraform_data.ghcr_registry` to
the `depends_on` of `terraform_data.redeploy` so the host is authenticated before
images are pulled:
```hcl
  depends_on = [dokploy_compose.stack, terraform_data.ghcr_registry]
```

- [ ] **Step 4: Move the GHCR creds into the dokploy chezmoi `.env`**

```bash
bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --edit \
  linode/environments/dokploy/.env
```
Append (and remove the same two from the production env's `.env`):
```dotenv
TF_VAR_GHCR_USER=<github-username>
TF_VAR_GHCR_PAT=<packages-read-pat>
```

- [ ] **Step 5: Apply the dokploy env and verify the registry + a pull**

Run:
```bash
cd linode/environments/dokploy
terraform fmt && terraform validate && bash dokploy.sh
```
Then confirm the host is logged in and the registry exists:
```bash
ssh -F linode/environments/production/dokploy.sshconfig dokploy \
  'sudo jq -r ".auths | keys[]" /root/.docker/config.json' | grep ghcr.io
curl -sf "https://vulcan.${TLD}/api/trpc/registry.all" -H "x-api-key: $DOKPLOY_API_KEY" \
  | python3 -c 'import sys,json;print([r["registryName"] for r in json.load(sys.stdin)["result"]["data"]["json"]])'
```
Expected: `ghcr.io` present in the docker config; `ghcr` in the registry list. A
fresh `compose.deploy` pulls private images without error.

- [ ] **Step 6: Remove `null_resource.ghcr_login` and its production vars**

Delete the `null_resource.ghcr_login` block (and its comment) from
`linode/environments/production/base.tf`, and `variable "GHCR_USER"` /
`variable "GHCR_PAT"` from `linode/environments/production/variables.tf`. Then:
```bash
cd linode/environments/production
bash production.sh
```
Expected: plan destroys `null_resource.ghcr_login` and nothing else unexpected.
(The host stays logged in — Dokploy's registry, not this resource, now owns it.)

- [ ] **Step 7: Document it** in `linode/README.md`

Replace the GHCR `docker login` subsection with: "GHCR pull auth is a Dokploy
`registry` (`ghcr`, dokploy env) — creating it runs a host `docker login`; the PAT
lives in Dokploy's (now backed-up) postgres." Add a one-liner under certificates:
"TLS certs are issued by Traefik's `letsencrypt` DNS-01 resolver into `acme.json`
and do **not** appear in Dokploy's Certificates UI (that section is for manually
imported custom certs only) — expected, not a fault."

---

## Task 7: Enable Traefik request logging (JSON) + cleanup cron

Add the `accessLog` block to the `traefik.yml` we own in the `dokploy-dns01`
module (baking it in, not the API toggle, so it survives module re-applies), then
enable Dokploy's log-cleanup cron.

**Files:**
- Modify: `linode/modules/dokploy-dns01/main.tf` (the `traefik_yaml` local)
- Modify: `linode/environments/dokploy/main.tf` (one-off log-cleanup API call)

- [ ] **Step 1: Add `accessLog` to the `traefik_yaml`** in `dokploy-dns01/main.tf`

Append this top-level block to the heredoc (sibling of `entryPoints`/`providers`),
matching exactly what Dokploy's `toggleRequests` writes so the panel's Requests
view recognises it:
```yaml
    accessLog:
      filePath: /etc/dokploy/traefik/dynamic/access.log
      format: json
      bufferingSize: 100
```

- [ ] **Step 2: Apply production to push the new traefik.yml**

Run:
```bash
cd linode/environments/production
bash production.sh
```
Expected: `null_resource.configure_main` re-runs (yaml_hash changed),
`settings.updateTraefikConfig` is POSTed, and the traefik container is recreated.

- [ ] **Step 3: Enable the log-cleanup cron** — add to `dokploy/main.tf`

```hcl
# Bound access.log growth via Dokploy's built-in cleanup (daily 00:00 UTC).
resource "terraform_data" "log_cleanup" {
  triggers_replace = "0 0 * * *"

  provisioner "local-exec" {
    environment = { DOKPLOY_API_KEY = var.DOKPLOY_API_KEY }
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail
      curl -sf -X POST "https://vulcan.${local.hostname_tld}/api/settings.updateLogCleanup" \
        -H "x-api-key: $DOKPLOY_API_KEY" -H "Content-Type: application/json" \
        --data '{"cronExpression":"0 0 * * *"}' >/dev/null
      echo "log-cleanup cron set"
    EOT
  }
}
```
Then `cd linode/environments/dokploy && terraform validate && bash dokploy.sh`.

- [ ] **Step 4: Verify logging is live**

Generate a request, then check the log file and the panel:
```bash
curl -sf "https://iris.${TLD}/" -o /dev/null
ssh -F linode/environments/production/dokploy.sshconfig dokploy \
  'sudo tail -n 2 /etc/dokploy/traefik/dynamic/access.log'
```
Expected: JSON access-log lines (one object per request). The panel's Web Server →
Requests view also shows entries.

---

## Out of scope (later, using this module)

- astarte app-DB compose backup (`databaseType: postgres`, `backupType: compose`,
  `extra_payload_json` with `composeId`/`serviceName`/`metadata.databaseUser`).
- Per-service volume backups (use `dokploy_volume_backup`, not this module).

## Known limitations

- The module is **create-or-leave**, not update: changing `schedule`/`prefix`
  on an existing backup won't propagate (the `count` guard sees the existing row
  and skips). To change a live backup, delete it in the panel (or via
  `backup.remove`) and re-apply. A future `backup.update` call can lift this.
- `data.http.existing`/`current_user`/`registries` read the Dokploy API at
  **plan** time, so the instance + API key must be reachable to plan — the same
  constraint the `dokploy_*` provider resources already impose.
- The GHCR PAT now lives at rest in Dokploy's postgres (`registry.password`),
  which the control-plane backup captures. Restoring that backup recreates the
  registry row but does not re-run `docker login`; the next dokploy apply's
  create-or-update fixes the host login.
- Request logging is baked into the `dokploy-dns01` `traefik.yml`, so toggling it
  from the panel (Web Server → Requests) is **not** the source of truth — a panel
  toggle is overwritten on the next module apply.
