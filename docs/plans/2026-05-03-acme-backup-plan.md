# Dokploy `acme.json` Backup & Restore Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Hourly off-host backup of Dokploy's `/etc/dokploy/traefik/dynamic/acme.json` to a Linode Object Storage bucket (gpg-encrypted), with Terraform-driven restore on instance bootstrap so cert reissuance is avoided after rebuilds.

**Architecture:** A second Object Storage bucket (`infra-backups`) and a scoped read_write key are provisioned **inside the production stack** (not bootstrap — it's production infra) with `prevent_destroy = true` on the bucket so a `terraform destroy` of production fails loudly rather than nuking the cert backups. The dokploy module receives bucket/key values as direct resource references — zero new credentials in `.env` (only `TF_VAR_GPG_RECIPIENT` is added). On the dokploy host, an hourly systemd timer runs a backup script (inlined directly in `user_data.sh` via a quoted heredoc — no separate script file) that asymmetrically encrypts `acme.json` with a gpg public key (only the public key lives on the host) and uploads via `s3cmd` with five guardrails (size floor, JSON validity, regression check vs remote, atomic temp-key swap, non-zero exit on guard failure). On `terraform apply`, two `null_resource`s run after cloud-init completes: `configure_acme_backup` SSH-pushes the s3cmd config + gpg public key + env file (so no secrets land in cloud-init user_data), and `restore_acme` checks for the backup object via inline `s3cmd info` and, if present, uses a local `gpg --decrypt | ssh ... cat > ...` pipe so the decrypted cert plaintext never touches disk on the deploy machine. Restore is gated on instance replacement (instance_id), not on backup change, so a live `acme.json` is never clobbered by a stale backup.

**Tech Stack:** Terraform (linode/linode 3.4.0), bash, gpg (asymmetric, recipient by fingerprint), `s3cmd`, systemd timer, Linode Object Storage (S3-compatible).

---

## File Structure

**Create:** none.

**Modify:**

- `linode/modules/dokploy/variables.tf` — add `BACKUP_BUCKET`, `BACKUP_BUCKET_REGION`, `BACKUP_BUCKET_ENDPOINT`, `BACKUP_ACCESS_KEY`, `BACKUP_SECRET_KEY`, `GPG_RECIPIENT`
- `linode/modules/dokploy/outputs.tf` — expose `restore_acme_id` for cross-resource ordering
- `linode/modules/dokploy/main.tf` — add `null_resource "configure_acme_backup"` and `null_resource "restore_acme"` (s3cfg rendered inline; existence check inline)
- `linode/modules/dokploy/user_data.sh` — install `s3cmd`/`gpg`; inline-write `backup_acme.sh` (with five guardrails) to `/usr/local/bin/`; install systemd timer + service units (no credentials, no keys); add TODO comment about admin password metadata exposure
- `linode/environments/production/base.tf` — add `linode_object_storage_bucket.infra_backups` with `prevent_destroy = true`, `linode_object_storage_key.infra_backups` scoped read_write to that bucket, pass new vars into module, add `restore_acme_id` reference to `bind_dokploy_domain`'s triggers
- `linode/environments/production/variables.tf` — add only `GPG_RECIPIENT` (bucket vars come from resource refs, not env)
- `linode/environments/production/.env.example` — document `TF_VAR_GPG_RECIPIENT`
- `linode/environments/bootstrap/bootstrap.sh` — add `prompt_if_missing` for `TF_VAR_GPG_RECIPIENT`

---

## Pre-flight (do once, by hand)

- [ ] Verify the gpg keypair you intend to reuse has both halves available locally: `gpg --list-secret-keys --keyid-format=long` shows the recipient ID/fingerprint you'll pass as `TF_VAR_GPG_RECIPIENT`.
- [ ] Verify `s3cmd` and `jq` are installed on the deploy machine: `which s3cmd jq`.
- [ ] Confirm Linode Object Storage subscription is active (the existing TF state bucket implies it is, but sanity-check the dashboard).

---

## Task 1: Add new variables to the dokploy module

**Files:**

- Modify: `linode/modules/dokploy/variables.tf`

- [ ] **Step 1: Append the six new variables**

Append to `linode/modules/dokploy/variables.tf`:

```hcl
variable "BACKUP_BUCKET" {
  type        = string
  nullable    = false
  description = "Linode Object Storage bucket name where acme.json.gpg is stored"
}

variable "BACKUP_BUCKET_REGION" {
  type        = string
  nullable    = false
  description = "Region of the BACKUP_BUCKET"
}

variable "BACKUP_BUCKET_ENDPOINT" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "S3 endpoint for the BACKUP_BUCKET (e.g. us-ord-1.linodeobjects.com)"
}

variable "BACKUP_ACCESS_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Object Storage access key scoped read_write to BACKUP_BUCKET"
}

variable "BACKUP_SECRET_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Object Storage secret key for BACKUP_ACCESS_KEY"
}

variable "GPG_RECIPIENT" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt acme.json backups. Public key must be present in the deploy machine's gpg keyring."
}
```

- [ ] **Step 2: Commit**

```
git add linode/modules/dokploy/variables.tf
git commit -m "infra: add backup + gpg variables to dokploy module"
```

---

## Task 2: Update user_data.sh

**Files:**

- Modify: `linode/modules/dokploy/user_data.sh`

This task does three things: (a) adds the admin-password TODO at the top, (b) installs `s3cmd` + `gnupg` via apt, and (c) inserts a self-contained acme-backup section that writes `backup_acme.sh` (with all five guardrails inline) and installs the systemd timer + service. **Critical templatefile escape rule**: `user_data.sh` is rendered through Terraform's `templatefile()`, so every `${...}` and `%{...}` inside the heredoc body is evaluated. Use `$${...}` to emit a literal `${...}`.

- [ ] **Step 1: Add the admin-password TODO at the top**

In `linode/modules/dokploy/user_data.sh`, after line 10 (`APT_OPTS=...`) and before line 12 (`apt-get update`), insert:

```bash
# TODO(infra-security): DOKPLOY_ADMIN_PASSWORD is templated into this user_data
# script and therefore lives in Linode's metadata service for the lifetime of
# the instance, queryable from inside the box. Replace by bootstrapping with a
# strong random password (Terraform-generated, never logged) then SSH-pushing
# the real admin password via a null_resource provisioner — same pattern as
# null_resource.configure_acme_backup in linode/modules/dokploy/main.tf.
# DOKPLOY_ADMIN_EMAIL has the same exposure (lower-stakes; just an address).
```

- [ ] **Step 2: Add s3cmd + gnupg to apt install**

Find:

```bash
apt-get install "$${APT_OPTS[@]}" curl jq ufw
```

Replace with:

```bash
apt-get install "$${APT_OPTS[@]}" curl jq ufw s3cmd gnupg
```

- [ ] **Step 3: Insert the acme-backup section before the firewall block**

Just before the `# Configure firewall with ufw` line near the bottom (around line 147), insert the block below verbatim. **All `${...}` references inside the backup script body are escaped as `$${...}` because user_data.sh goes through templatefile** — at runtime on the host these will appear (and behave) as ordinary bash `${...}`.

```bash
# --- acme.json backup tooling ---------------------------------------------
# Inlined backup script, systemd units, and timer. The gpg public key,
# /root/.s3cfg, and /root/.acme-backup.env are SSH-pushed by Terraform's
# null_resource.configure_acme_backup AFTER cloud-init completes — keeps
# credentials out of the Linode metadata service. The systemd service has
# ConditionPathExists guards on those files, so the timer is safe to enable
# now; until Terraform pushes them, the service fires and skips silently.

cat > /usr/local/bin/backup_acme.sh <<'BACKUP_SCRIPT_EOF'
#!/usr/bin/env bash
# Backs up /etc/dokploy/traefik/dynamic/acme.json to ${BACKUP_BUCKET} as acme.json.gpg.
# Asymmetric gpg using the public key imported into root's keyring (recipient = GPG_RECIPIENT).
# Five guardrails — see GUARDS in-line. Exits non-zero on any failure so systemd surfaces it.

set -euo pipefail

ACME_PATH="/etc/dokploy/traefik/dynamic/acme.json"
BUCKET="$${BACKUP_BUCKET:?BACKUP_BUCKET must be set}"
RECIPIENT="$${GPG_RECIPIENT:?GPG_RECIPIENT must be set}"
KEY="acme.json.gpg"
TMP_KEY="acme.json.gpg.tmp"
MIN_BYTES=200             # GUARD 1 floor
REGRESSION_RATIO=50       # GUARD 3 — abort if new < 50% of remote

log() { printf '[backup_acme] %s\n' "$$*" >&2; }

# GUARD 1: source exists and above floor
if [ ! -s "$$ACME_PATH" ]; then log "ABORT: $$ACME_PATH missing or empty"; exit 1; fi
LOCAL_BYTES=$$(stat -c %s "$$ACME_PATH")
if [ "$$LOCAL_BYTES" -lt "$$MIN_BYTES" ]; then
    log "ABORT: $$ACME_PATH is $$LOCAL_BYTES bytes (< $$MIN_BYTES floor)"; exit 1
fi

# GUARD 2: source parses as JSON
if ! jq empty "$$ACME_PATH" >/dev/null 2>&1; then
    log "ABORT: $$ACME_PATH is not valid JSON"; exit 1
fi

# GUARD 3: regression check vs remote (skip if remote missing)
REMOTE_BYTES=""
if s3cmd info "s3://$${BUCKET}/$${KEY}" >/dev/null 2>&1; then
    REMOTE_BYTES=$$(s3cmd info "s3://$${BUCKET}/$${KEY}" | awk '/File size/ {print $$3}')
fi
if [ -n "$$REMOTE_BYTES" ] && [ "$$REMOTE_BYTES" -gt 0 ]; then
    THRESHOLD=$$(( REMOTE_BYTES * REGRESSION_RATIO / 100 ))
    NEW_ENCRYPTED_EST=$$(( LOCAL_BYTES * 105 / 100 ))   # gpg overhead ~5%
    if [ "$$NEW_ENCRYPTED_EST" -lt "$$THRESHOLD" ]; then
        log "ABORT: new encrypted size ~$${NEW_ENCRYPTED_EST}B < $${REGRESSION_RATIO}% of remote $${REMOTE_BYTES}B"
        exit 1
    fi
fi

WORKDIR=$$(mktemp -d)
trap 'rm -rf "$$WORKDIR"' EXIT
ENCRYPTED="$${WORKDIR}/$${KEY}"

gpg --batch --yes --trust-model always \
    --recipient "$$RECIPIENT" \
    --output "$$ENCRYPTED" \
    --encrypt "$$ACME_PATH"

# GUARD 4 (atomic write): upload to .tmp key, then s3cmd mv (server-side rename)
s3cmd put "$$ENCRYPTED" "s3://$${BUCKET}/$${TMP_KEY}" >/dev/null
s3cmd mv "s3://$${BUCKET}/$${TMP_KEY}" "s3://$${BUCKET}/$${KEY}" >/dev/null

# GUARD 5: any failure above triggers `set -e` → non-zero exit. systemd surfaces it.

log "OK: uploaded $${LOCAL_BYTES}B plaintext / $$(stat -c %s "$$ENCRYPTED")B encrypted"
BACKUP_SCRIPT_EOF
chmod 0755 /usr/local/bin/backup_acme.sh

mkdir -p /var/log/acme-backup
chmod 700 /var/log/acme-backup

cat > /etc/systemd/system/acme-backup.service <<'UNIT_EOF'
[Unit]
Description=Encrypt and upload Dokploy acme.json
ConditionPathExists=/root/.s3cfg
ConditionPathExists=/root/.acme-backup.env

[Service]
Type=oneshot
EnvironmentFile=/root/.acme-backup.env
ExecStart=/usr/local/bin/backup_acme.sh
StandardOutput=append:/var/log/acme-backup/backup.log
StandardError=append:/var/log/acme-backup/backup.log
UNIT_EOF

cat > /etc/systemd/system/acme-backup.timer <<'UNIT_EOF'
[Unit]
Description=Hourly acme.json backup

[Timer]
OnBootSec=10min
OnUnitActiveSec=1h
Persistent=true

[Install]
WantedBy=timers.target
UNIT_EOF

systemctl daemon-reload
systemctl enable acme-backup.timer
systemctl start acme-backup.timer
```

- [ ] **Step 4: Verify templatefile rendering locally**

This is critical because of the `$${...}` escape rules. Run a one-off render to confirm the output is what's expected:

```
cd linode/environments/production
terraform console <<<"templatefile(\"../../modules/dokploy/user_data.sh\", { HOSTNAME_TLD = \"x\", DOKPLOY_ADMIN_EMAIL = \"x\", DOKPLOY_ADMIN_PASSWORD = \"x\", DOKPLOY_VERSION = \"x\" })" \
  | sed -n '/cat > \/usr\/local\/bin\/backup_acme.sh/,/BACKUP_SCRIPT_EOF/p'
```

Expected: the rendered backup script body shows `${BACKUP_BUCKET:?...}`, `$(stat -c %s ...)`, etc. — single `$` everywhere, no `$$` left over. If you see `$$` in the output, an escape was missed.

- [ ] **Step 5: Commit**

```
git add linode/modules/dokploy/user_data.sh
git commit -m "infra: inline acme-backup script + systemd units in user_data, add admin-password TODO"
```

---

## Task 3: Add `configure_acme_backup` null_resource

**Files:**

- Modify: `linode/modules/dokploy/main.tf`

- [ ] **Step 1: Append the resource**

Append to `linode/modules/dokploy/main.tf`. The s3cfg is rendered inline (only 7 lines — no separate template file).

```hcl
# Pushes /root/.s3cfg + /root/.acme-backup.env + the gpg public key to the host
# AFTER cloud-init completes. Keeping these out of user_data avoids exposure
# via the Linode metadata service.
#
# Triggers: instance_id (re-runs only on instance replacement) + recipient
# (re-runs if the gpg recipient changes).
resource "null_resource" "configure_acme_backup" {
  depends_on = [linode_instance.dokploy_main]

  triggers = {
    instance_id = linode_instance.dokploy_main.id
    recipient   = var.GPG_RECIPIENT
  }

  connection {
    type        = "ssh"
    host        = one(linode_instance.dokploy_main.ipv4)
    user        = "root"
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    destination = "/root/.s3cfg"
    content     = <<-EOT
      [default]
      access_key = ${var.BACKUP_ACCESS_KEY}
      secret_key = ${var.BACKUP_SECRET_KEY}
      host_base = ${var.BACKUP_BUCKET_ENDPOINT}
      host_bucket = %(bucket)s.${var.BACKUP_BUCKET_ENDPOINT}
      use_https = True
      signature_v2 = False
    EOT
  }

  provisioner "file" {
    destination = "/root/.acme-backup.env"
    content     = "BACKUP_BUCKET=${var.BACKUP_BUCKET}\nGPG_RECIPIENT=${var.GPG_RECIPIENT}\n"
  }

  provisioner "remote-exec" {
    inline = ["chmod 600 /root/.s3cfg /root/.acme-backup.env"]
  }

  # Export the public key locally and pipe it in via SSH stdin → gpg --import.
  # Requires the recipient's public key to be in the deploy machine's keyring.
  provisioner "local-exec" {
    command = <<-EOT
      set -euo pipefail
      gpg --export -a "${var.GPG_RECIPIENT}" \
        | ssh -o StrictHostKeyChecking=no -i ${path.root}/id_ed25519 \
              root@${one(linode_instance.dokploy_main.ipv4)} \
              'gpg --batch --import'
    EOT
  }
}
```

- [ ] **Step 2: Commit**

```
git add linode/modules/dokploy/main.tf
git commit -m "infra: add configure_acme_backup null_resource"
```

---

## Task 4: Add `restore_acme` null_resource and module output

**Files:**

- Modify: `linode/modules/dokploy/main.tf`
- Modify: `linode/modules/dokploy/outputs.tf`

The existence check is done inline in the local-exec script (one `s3cmd info` call), so no `external` data source is needed.

- [ ] **Step 1: Append the resource**

Append to `linode/modules/dokploy/main.tf`:

```hcl
# Restores acme.json from the encrypted backup if one exists, before any
# per-host LE issuance is triggered (bind_dokploy_domain references this
# resource's id in its triggers, creating an ordering edge in the calling
# environment). Decrypts on the deploy machine and pipes plaintext over SSH
# directly into install(1) — cert plaintext never lands on the deploy disk.
#
# Triggers: instance_id only. Restore does NOT re-run on backup change —
# re-restoring would clobber a live, working acme.json with stale data.
# To force a restore (e.g. after corrupting the live file in place):
#   terraform apply -replace='module.dokploy-instance.null_resource.restore_acme'
resource "null_resource" "restore_acme" {
  depends_on = [null_resource.configure_acme_backup]

  triggers = {
    instance_id = linode_instance.dokploy_main.id
  }

  provisioner "local-exec" {
    interpreter = ["bash", "-c"]
    command     = <<-EOT
      set -euo pipefail

      CFG=$(mktemp); trap 'rm -f "$CFG"' EXIT
      cat > "$CFG" <<CFG_EOF
      [default]
      access_key = ${var.BACKUP_ACCESS_KEY}
      secret_key = ${var.BACKUP_SECRET_KEY}
      host_base = ${var.BACKUP_BUCKET_ENDPOINT}
      host_bucket = %(bucket)s.${var.BACKUP_BUCKET_ENDPOINT}
      use_https = True
      CFG_EOF

      if ! s3cmd -c "$CFG" info "s3://${var.BACKUP_BUCKET}/acme.json.gpg" >/dev/null 2>&1; then
        echo "[restore_acme] no backup at s3://${var.BACKUP_BUCKET}/acme.json.gpg — skipping"
        exit 0
      fi

      echo "[restore_acme] restoring acme.json from backup"
      s3cmd -c "$CFG" get --force "s3://${var.BACKUP_BUCKET}/acme.json.gpg" - \
        | gpg --batch --decrypt \
        | ssh -o StrictHostKeyChecking=no -i ${path.root}/id_ed25519 \
              root@${one(linode_instance.dokploy_main.ipv4)} \
              "install -m 0600 -o root -g root /dev/stdin /etc/dokploy/traefik/dynamic/acme.json && docker service update --force dokploy-traefik >/dev/null"

      echo "[restore_acme] done"
    EOT
  }
}
```

- [ ] **Step 2: Expose restore_acme via module output**

Append to `linode/modules/dokploy/outputs.tf`:

```hcl
output "restore_acme_id" {
  value       = null_resource.restore_acme.id
  description = "ID of restore_acme — reference from the calling environment to enforce ordering before any per-host LE issuance"
}
```

- [ ] **Step 3: Commit**

```
git add linode/modules/dokploy/main.tf linode/modules/dokploy/outputs.tf
git commit -m "infra: add restore_acme null_resource and expose its id"
```

---

## Task 5: Wire production environment

**Files:**

- Modify: `linode/environments/production/variables.tf`
- Modify: `linode/environments/production/base.tf`
- Modify: `linode/environments/production/.env.example`
- Modify: `linode/environments/bootstrap/bootstrap.sh`

- [ ] **Step 1: Add only `GPG_RECIPIENT` to production vars**

Append to `linode/environments/production/variables.tf`:

```hcl
variable "GPG_RECIPIENT" {
  type        = string
  nullable    = false
  description = "GPG recipient (key id, fingerprint, or email) used to encrypt acme.json backups. Public key must be in the deploy machine's gpg keyring."
}
```

- [ ] **Step 2: Add the bucket + key resources to base.tf**

Append to `linode/environments/production/base.tf`:

```hcl
# Long-lived backups primitive (acme.json today, possibly more later). Lives
# in production because nothing in `terraform init` needs it. prevent_destroy
# guards against accidental nuking on `terraform destroy` of the rest of the
# stack — destroys will fail loudly until the line is explicitly removed.
resource "linode_object_storage_bucket" "infra_backups" {
  region     = var.REGION
  label      = "${var.HOSTNAME_TLD}-infra-backups"
  versioning = false
  acl        = "private"

  lifecycle {
    prevent_destroy = true
  }

  lifecycle_rule {
    abort_incomplete_multipart_upload_days = 7
    enabled                                = true
  }
}

resource "linode_object_storage_key" "infra_backups" {
  label = "${var.HOSTNAME_TLD}-infra-backups-rw"

  bucket_access {
    bucket_name = linode_object_storage_bucket.infra_backups.label
    region      = linode_object_storage_bucket.infra_backups.region
    permissions = "read_write"
  }
}
```

- [ ] **Step 3: Pass new vars into the module call**

In `linode/environments/production/base.tf`, replace the `module "dokploy-instance"` block (lines 24-33) with:

```hcl
module "dokploy-instance" {
  source = "../../modules/dokploy"

  region                 = var.REGION
  HOSTNAME_TLD           = var.HOSTNAME_TLD
  TAGS                   = local.TAGS
  DOKPLOY_ADMIN_EMAIL    = var.DOKPLOY_ADMIN_EMAIL
  DOKPLOY_ADMIN_PASSWORD = var.DOKPLOY_ADMIN_PASSWORD
  DOKPLOY_VERSION        = var.DOKPLOY_VERSION

  BACKUP_BUCKET          = linode_object_storage_bucket.infra_backups.label
  BACKUP_BUCKET_REGION   = linode_object_storage_bucket.infra_backups.region
  BACKUP_BUCKET_ENDPOINT = linode_object_storage_bucket.infra_backups.s3_endpoint
  BACKUP_ACCESS_KEY      = linode_object_storage_key.infra_backups.access_key
  BACKUP_SECRET_KEY      = linode_object_storage_key.infra_backups.secret_key
  GPG_RECIPIENT          = var.GPG_RECIPIENT
}
```

- [ ] **Step 4: Reference restore_acme from bind_dokploy_domain triggers**

In `linode/environments/production/base.tf`, find the `triggers` block of `null_resource.bind_dokploy_domain` (lines 52-56) and add the `restore_acme` line:

```hcl
  triggers = {
    instance_ip  = module.dokploy-instance.instance_ip
    host         = "${var.DASHBOARD_SUBDOMAIN}.${var.HOSTNAME_TLD}"
    email        = var.EMAIL_ADDRESS
    restore_acme = module.dokploy-instance.restore_acme_id
  }
```

The reference creates the dependency edge — bind cannot run until restore is done.

- [ ] **Step 5: Update `.env.example`**

Append to `linode/environments/production/.env.example`:

```
# GPG recipient (id/fingerprint/email) used to encrypt acme.json backups.
# Public key must be present in the deploy machine's gpg keyring.
TF_VAR_GPG_RECIPIENT=
```

- [ ] **Step 6: Update bootstrap.sh prompts**

In `linode/environments/bootstrap/bootstrap.sh`, after the existing `prompt_if_missing` block (around line 83), add:

```bash
prompt_if_missing "TF_VAR_GPG_RECIPIENT"          "GPG recipient (id/fingerprint/email) for acme.json backup encryption"
```

- [ ] **Step 7: Validate**

```
cd linode/environments/production && terraform init -upgrade && terraform validate
```

Expected: `Success!`

- [ ] **Step 8: Commit**

```
git add linode/environments/
git commit -m "infra: provision infra-backups bucket + key in production, wire vars to dokploy module"
```

---

## Task 6: End-to-end apply and verification

This is the only task that touches live infrastructure.

- [ ] **Step 1: Re-run bootstrap to pick up the GPG_RECIPIENT prompt**

```
cd linode/environments/bootstrap
./bootstrap.sh
```

The only new prompt should be `TF_VAR_GPG_RECIPIENT`. No new resources are applied. Confirm `production/.env` now contains `TF_VAR_GPG_RECIPIENT=...`.

- [ ] **Step 2: Plan production**

```
cd ../production
source .env
terraform plan -out=tfplan
```

Expected new resources:

- `linode_object_storage_bucket.infra_backups`
- `linode_object_storage_key.infra_backups`
- `module.dokploy-instance.null_resource.configure_acme_backup`
- `module.dokploy-instance.null_resource.restore_acme`

Expected updates:

- `module.dokploy-instance.linode_instance.dokploy_main` — **in-place** because `metadata.user_data` content changes (new inline backup section). If it shows **replacement**, STOP and investigate.
- `null_resource.bind_dokploy_domain` — re-runs (new trigger).

- [ ] **Step 3: Apply**

```
terraform apply tfplan
```

Watch `null_resource.configure_acme_backup` output for the gpg import. Watch `null_resource.restore_acme` for `[restore_acme] no backup ... — skipping` (first run).

- [ ] **Step 4: Verify backup tooling on the host**

SSH in and confirm:

```
ls -la /root/.s3cfg /root/.acme-backup.env /usr/local/bin/backup_acme.sh
systemctl list-timers acme-backup.timer
gpg --list-keys
head -20 /usr/local/bin/backup_acme.sh   # confirm dollar-brace expansions look right (no $$)
```

Expected: `.s3cfg` and `.acme-backup.env` are 0600; script is 0755; timer shows next-fire ≤1h; gpg keyring has the recipient public key; the backup script body has single-`$` references (no escape leakage).

- [ ] **Step 5: Trigger first backup manually + exercise happy path (GUARD 4, GUARD 5)**

```
systemctl start acme-backup.service
journalctl -u acme-backup.service --since "1 minute ago"
```

Expected: `[backup_acme] OK: uploaded NNNB plaintext / NNNB encrypted`. Exit status 0. Confirm bucket has `acme.json.gpg`:

```
s3cmd ls "s3://<bucket>/"
```

- [ ] **Step 6: Verify decrypt round-trip**

From the deploy machine (where the gpg private key lives):

```
s3cmd get "s3://<bucket>/acme.json.gpg" - | gpg --decrypt | jq empty && echo OK
```

Expected: `OK`. (Pipe-only — no plaintext written to disk.)

- [ ] **Step 7: Exercise GUARD 1 (and implicitly GUARD 5 surfacing)**

On the host:

```
mv /etc/dokploy/traefik/dynamic/acme.json /tmp/acme.json.bak
systemctl start acme-backup.service ; echo "service exit: $?"
mv /tmp/acme.json.bak /etc/dokploy/traefik/dynamic/acme.json
```

Expected: non-zero service exit, journal shows `ABORT: ... missing or empty`. The remote `acme.json.gpg` is unchanged (verify via `s3cmd info` etag matching pre-test).

- [ ] **Step 8: Exercise GUARD 2**

On the host:

```
cp /etc/dokploy/traefik/dynamic/acme.json /tmp/acme.json.bak
head -c 500 /dev/urandom | base64 > /etc/dokploy/traefik/dynamic/acme.json
systemctl start acme-backup.service ; echo "service exit: $?"
mv /tmp/acme.json.bak /etc/dokploy/traefik/dynamic/acme.json
```

Expected: non-zero service exit, journal shows `ABORT: ... not valid JSON`.

- [ ] **Step 9: Exercise the restore path**

Wait until at least one good backup has uploaded (Step 5 satisfies this). Then on the host, corrupt the live file:

```
cp /etc/dokploy/traefik/dynamic/acme.json /tmp/acme.json.preserve
echo '{}' > /etc/dokploy/traefik/dynamic/acme.json
```

From the deploy machine:

```
terraform apply -replace='module.dokploy-instance.null_resource.restore_acme'
```

Expected: `[restore_acme] restoring acme.json from backup` then `[restore_acme] done`. SSH back and verify:

```
diff /etc/dokploy/traefik/dynamic/acme.json /tmp/acme.json.preserve
```

Expected: no output (files identical). Cleanup: `rm /tmp/acme.json.preserve`.

- [ ] **Step 10: Document the manual restore in the README**

Append to `linode/README.md`:

```markdown
## Manual acme.json restore

To restore `acme.json` to a running instance without replacing it (e.g. after
in-place corruption):

    cd linode/environments/production
    terraform apply -replace='module.dokploy-instance.null_resource.restore_acme'

Pulls the latest `acme.json.gpg` from the backups bucket, decrypts locally
(plaintext never written to disk on the deploy machine), pipes onto the host,
and force-updates `dokploy-traefik` so it re-reads the cert store.
```

- [ ] **Step 11: Commit**

```
git add linode/README.md
git commit -m "docs: document manual acme.json restore procedure"
```

---

## Self-Review Checklist (run before declaring done)

- [ ] `terraform validate` passes in `bootstrap/` and `production/`
- [ ] Templatefile escape audit passed: rendered backup script body has no leftover `$$` (Task 2 Step 4, and again on the live host in Task 6 Step 4)
- [ ] `acme.json.gpg` exists in the backup bucket and round-trips through `gpg --decrypt | jq empty`
- [ ] systemd timer is enabled and shows a future fire time
- [ ] `cat /var/lib/cloud/instance/user-data.txt` on the host shows no new credentials beyond the pre-existing (and now-TODO'd) `DOKPLOY_ADMIN_*`
- [ ] GUARD 1, 2, and the restore path each exercised once on live infra (Task 6 Steps 7, 8, 9)
- [ ] No private key material appears in `terraform.tfstate` — search for the gpg fingerprint string and confirm it appears only as input variable references
- [ ] `terraform plan -destroy` errors on `infra_backups` due to `prevent_destroy`
