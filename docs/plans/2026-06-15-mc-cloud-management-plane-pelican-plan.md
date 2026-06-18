# MC Cloud Management Plane (Pelican) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Run the Pelican panel as a Dokploy compose stack behind the existing
Traefik at `daedalus.<tld>`, reaching the i7 Wings node over Tailscale, with all
env (secret + non-secret) supplied via a `dokploy_environment_variables`
resource and the `pelican-data` volume backed up to Linode Object Storage.

**Architecture:** Pelican is a single container (supervisord runs php-fpm, the
queue worker, the scheduler, and Caddy). It runs in **`BEHIND_PROXY=true`**
mode — Caddy stays on plain HTTP `:80`, Traefik terminates TLS and routes to
container port 80, exactly like `astarte`/`iris`. The compose service is
appended to `compose/docker-compose.yml`; its `compose_file_content` stays
non-sensitive because every env value is delivered through a
`dokploy_environment_variables` resource (`create_env_file = true`) whose map is
built from a chezmoi-decrypted `.secrets/compose/pelican.env` (secrets) merged
with Terraform-derived values (URLs, proxy CIDRs). The Wings node is registered
in the panel pointing at the i7's Tailscale IP over HTTP; the emitted node
config is handed to sub-project 1's `wings` role (its Task 12 seam). Volume
backup uses the provider's native `dokploy_backup_destination` +
`dokploy_volume_backup` against the existing `infra_backups` bucket.

**Tech Stack:** Docker Compose, Dokploy (`j0bIT/dokploy` provider, forked),
Terraform (`linode/linode`, `germanbrew/dotenv`), Pelican
(`ghcr.io/pelican-dev/panel`), Traefik, Tailscale, chezmoi/GPG secrets.

**Parent design:**
[2026-06-14-minecraft-management-architecture-design.md](./2026-06-14-minecraft-management-architecture-design.md)
(sub-project 2). The brainstorming conversation is the spec.

**Cross-project seams:**
- The Wings **node config** the panel emits in Task 6 is the input
  sub-project 1's `wings` role (its Task 12) waits on. Run that SP1 step with
  the config this task produces.
- The Linode **Object Storage bucket** (`linode_object_storage_bucket.infra_backups`)
  lives in `linode/environments/production`. Task 7 adds a dedicated access key
  there and surfaces its credentials; Task 8 (in the `dokploy` env) consumes
  them. The two environments are separate state files, so the handoff is an
  explicit secret copy, not a Terraform reference.

---

## Reference: how Pelican's image runs (verified against pelican-dev/panel)

- One image, supervisord runs all of: `php-fpm`, `queue-worker`
  (`artisan queue:work`), `supercronic` (the Laravel scheduler), and `caddy`.
  **No separate worker/cron services are needed.**
- `BEHIND_PROXY=true` ⇒ entrypoint sets Caddy to listen on `:80`,
  `auto_https off`, no Let's Encrypt, and sets `ASSET_URL` from `APP_URL`. This
  is the correct "behind Traefik" mode. `SKIP_CADDY=true` is **wrong** here — it
  leaves only FastCGI php-fpm on `:9000`, which Traefik cannot proxy.
- On first boot (no `/pelican-data/.env`), the entrypoint writes `APP_KEY` from
  the container env into `/pelican-data/.env` and sets `APP_INSTALLED=false`
  (the web installer). After install, the volume `.env` is the source of truth.
- Persisted state lives under `/pelican-data` (holds `.env`,
  `database/database.sqlite`, `storage/`, `plugins/`).

## File structure

Created:

```text
.secrets/compose/pelican.env                 # chezmoi-encrypted; APP_KEY (Task 3)
compose/pelican.env.example                  # committed dummy (Task 3)
```

Modified:

```text
compose/docker-compose.yml                   # pelican service + volumes (Task 1)
compose/docker-compose.override.yml          # local pelican ports (Task 2)
.secrets/.chezmoitemplates/compose-env       # PELICAN_IMAGE_TAG (Task 2)
compose/.env.example                         # PELICAN_IMAGE_TAG doc (Task 2)
linode/environments/dokploy/main.tf          # dotenv, templatefile var,
                                             #   env-vars + backup resources
                                             #   (Tasks 4, 8)
linode/environments/dokploy/variables.tf     # image tag + backup vars (Tasks 4, 8)
linode/environments/production/base.tf       # backups access key + outputs (Task 7)
linode/environments/production/outputs.tf    # surface backup creds (Task 7)
docs/plans/2026-06-14-minecraft-management-architecture-design.md  # Caddy note (Task 9)
linode/README.md                             # Pelican panel subsection (Task 9)
```

---

## Task 1: Pelican compose service

Append the `pelican` service to the base compose file and add the top-level
`volumes:` block it needs (the first stateful service in this stack). Every env
value is a `$${VAR}` runtime reference — the `$$` escapes Terraform's
`templatefile()` (same trick as the `iris` `$${1}` labels), leaving a literal
`${VAR}` that Docker Compose interpolates from the Dokploy-managed env file
(Task 4). No secret or derived value is written into the compose file.

**Files:**
- Modify: `compose/docker-compose.yml`

- [ ] **Step 1: Add the `pelican` service** (after the `janus` block, before the
  closing of `services:`)

```yaml
  # Pelican game-server panel. Single container: supervisord runs php-fpm, the
  # queue worker, the scheduler, and Caddy. BEHIND_PROXY keeps Caddy on plain
  # HTTP :80 (auto_https off) so Traefik terminates TLS and routes to port 80.
  # All env values come from the dokploy_environment_variables resource via
  # Dokploy's env file; $${VAR} survives templatefile() and is interpolated by
  # compose at deploy time, so no values land in compose_file_content.
  pelican:
    image: ghcr.io/pelican-dev/panel:${PELICAN_IMAGE_TAG}
    environment:
      APP_KEY: '$${APP_KEY}'
      APP_URL: '$${APP_URL}'
      APP_ENV: '$${APP_ENV}'
      APP_DEBUG: '$${APP_DEBUG}'
      BEHIND_PROXY: '$${BEHIND_PROXY}'
      TRUSTED_PROXIES: '$${TRUSTED_PROXIES}'
      XDG_DATA_HOME: '$${XDG_DATA_HOME}'
    labels:
      traefik.enable: 'true'
      traefik.http.routers.pelican.entrypoints: 'websecure'
      traefik.http.routers.pelican.rule: 'Host(`daedalus.${HOSTNAME_TLD}`)'
      traefik.http.routers.pelican.tls: 'true'
      traefik.http.routers.pelican.tls.certresolver: 'letsencrypt'
      traefik.http.services.pelican.loadbalancer.healthcheck.interval: '30s'
      traefik.http.services.pelican.loadbalancer.healthcheck.path: '/up'
      traefik.http.services.pelican.loadbalancer.healthcheck.timeout: '5s'
      traefik.http.services.pelican.loadbalancer.server.port: '80'
    networks:
      - dokploy-network
    restart: unless-stopped
    volumes:
      - pelican-data:/pelican-data
      - pelican-logs:/var/www/html/storage/logs
```

- [ ] **Step 2: Add the top-level `volumes:` block** (at the end of the file,
  after the `services:` map)

```yaml
volumes:
  pelican-data:
  pelican-logs:
```

- [ ] **Step 3: Verify the YAML parses**

Run: `python -c "import yaml; yaml.safe_load(open('compose/docker-compose.yml')); print('ok')"`
Expected: `ok`.

- [ ] **Step 4: Verify the `$$` escaping is present** (so secrets don't get
  templated into compose at apply time)

Run: `grep -c "\$\${" compose/docker-compose.yml`
Expected: `7` (one per env key in the `pelican` service).

---

## Task 2: Local-dev wiring (override + image tag)

Pelican uses an upstream image (no source build), so local dev just needs a
host port and a value for `PELICAN_IMAGE_TAG`. The tag is added to the shared
chezmoi compose-env partial so both `compose/.env` and `compose/.env.prod` pick
it up, mirroring `ASTARTE_IMAGE_TAG`/`IRIS_IMAGE_TAG`. Locally Pelican is
largely inert (no Wings, no Tailscale); the override exists for parity and to
let you exercise the web installer against SQLite.

**Files:**
- Modify: `compose/docker-compose.override.yml`
- Modify: `.secrets/.chezmoitemplates/compose-env`
- Modify: `compose/.env.example`

- [ ] **Step 1: Add the `pelican` port mapping to the override** (after the
  `janus` block)

```yaml
  pelican:
    ports:
      - '8088:80'
```

- [ ] **Step 2: Add `PELICAN_IMAGE_TAG` to the chezmoi compose-env partial**
  (after the `IRIS_IMAGE_TAG=local` line)

```text
PELICAN_IMAGE_TAG=latest
```

- [ ] **Step 3: Document `PELICAN_IMAGE_TAG` in `compose/.env.example`** (append)

```dotenv
# Image tag for the upstream Pelican panel image. Any pinned tag works;
# 'latest' for local/manual. In prod, Terraform substitutes the value from
# linode/environments/dokploy/variables.tf via templatefile().
PELICAN_IMAGE_TAG=latest
```

- [ ] **Step 4: Render the chezmoi templates and confirm the var lands**

Run: `czm apply --dry-run --verbose 2>&1 | grep -i pelican_image_tag || true`
then `czm apply` and
`grep PELICAN_IMAGE_TAG compose/.env compose/.env.prod`
Expected: `PELICAN_IMAGE_TAG=latest` in both rendered files.

- [ ] **Step 5: Verify the override YAML parses**

Run: `python -c "import yaml; yaml.safe_load(open('compose/docker-compose.override.yml')); print('ok')"`
Expected: `ok`.

---

## Task 3: Pelican secrets scaffolding

`APP_KEY` is the only true secret (it encrypts data in the SQLite DB and must
stay stable for the life of that DB). It lives in a chezmoi-encrypted
`.secrets/compose/pelican.env`, with a committed dummy `.example`. Non-secret
env (URLs, proxy CIDRs) is derived in Terraform in Task 4 — not stored here.

**Files:**
- Create: `compose/pelican.env.example`
- Create: `.secrets/compose/pelican.env` (via chezmoi)

- [ ] **Step 1: Write the committed example**

```bash
cat > compose/pelican.env.example <<'EOF'
# Laravel app key. 32 random alphanumeric chars (the format Pelican's
# entrypoint generates). Encrypts data in the SQLite DB; keep it stable for
# the life of that DB and back it up alongside the volume.
APP_KEY=replace-me-32-char-random-string
EOF
```

- [ ] **Step 2: Generate a real key and create the encrypted secret**

```bash
KEY=$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32)
printf 'APP_KEY=%s\n' "$KEY" > compose/pelican.env
bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt compose/pelican.env
```

- [ ] **Step 3: Confirm chezmoi tracks it**

Run: `czm managed | grep compose/pelican.env`
Expected: the path is listed (a `.secrets/compose/encrypted_*pelican.env` source
exists).

---

## Task 4: Thread Pelican into the dokploy environment

Add the image-tag variable, read the secret file, render it into the compose
templatefile, and create the `dokploy_environment_variables` resource that
delivers every env value to the container. The `variables` map merges the
decrypted secret(s) with Terraform-derived non-secret values, so secret and
non-secret env share one resource and the compose file stays clean.

**Files:**
- Modify: `linode/environments/dokploy/variables.tf`
- Modify: `linode/environments/dokploy/main.tf`

- [ ] **Step 1: Add `PELICAN_IMAGE_TAG`** to `variables.tf` (after `IRIS_IMAGE_TAG`)

```hcl
variable "PELICAN_IMAGE_TAG" {
  type        = string
  nullable    = false
  description = "Image tag for the upstream Pelican panel image on GHCR."
  default     = "latest"
}
```

- [ ] **Step 2: Read the Pelican secret file** — add next to
  `data "dotenv" "compose"` in `main.tf`

```hcl
data "dotenv" "pelican" {
  filename = "${path.root}/../../../.secrets/compose/pelican.env"
}
```

- [ ] **Step 3: Add `PELICAN_IMAGE_TAG` to the compose templatefile vars**
  (inside the existing `templatefile(...)` call in `locals`)

```hcl
    PELICAN_IMAGE_TAG = var.PELICAN_IMAGE_TAG
```

- [ ] **Step 4: Add the env-vars resource** (after `resource "dokploy_compose" "stack"`)

```hcl
# All Pelican env, secret and non-secret, in one place. create_env_file makes
# Dokploy write a .env that compose interpolates the service's $${VAR} refs
# from, so no value lands in compose_file_content. APP_KEY is the only secret
# (from chezmoi-decrypted .secrets/compose/pelican.env); the rest are derived.
# TRUSTED_PROXIES covers the Docker/Swarm private ranges Traefik forwards from;
# verify against `docker network inspect dokploy-network` if client IPs look
# wrong in the panel.
resource "dokploy_environment_variables" "pelican" {
  compose_id      = dokploy_compose.stack.id
  create_env_file = true

  variables = {
    APP_KEY         = data.dotenv.pelican.entries["APP_KEY"]
    APP_URL         = "https://daedalus.${local.hostname_tld}"
    APP_ENV         = "production"
    APP_DEBUG       = "false"
    BEHIND_PROXY    = "true"
    TRUSTED_PROXIES = "172.16.0.0/12,10.0.0.0/8"
    XDG_DATA_HOME   = "/pelican-data"
  }

  depends_on = [dokploy_compose.stack]
}
```

- [ ] **Step 5: Format and validate**

Run:
```bash
cd linode/environments/dokploy
terraform fmt
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

---

## Task 5: Apply the stack and complete first-boot install

Deploy the stack, then run Pelican's one-time web installer (SQLite +
filesystem cache) and record the admin credentials. The installer is the single
manual touch for the panel — consistent with SP1's "one local touch" posture.

**Files:** none (operational).

- [ ] **Step 1: Apply the dokploy environment**

With the dokploy `.env` sourced, run: `cd linode/environments/dokploy && bash dokploy.sh`
Expected plan additions/changes: `dokploy_compose.stack` replaced (compose
content hash changed), `dokploy_environment_variables.pelican` created, the
redeploy `terraform_data` re-triggered.

- [ ] **Step 2: Confirm the container is up and env reached it**

```bash
ssh dokploy-prod 'docker ps --format "{{.Names}}" | grep -i pelican'
ssh dokploy-prod 'docker exec "$(docker ps -q -f name=pelican | head -1)" env | grep -E "APP_KEY|BEHIND_PROXY"'
```
Expected: a running pelican container; `APP_KEY` set and `BEHIND_PROXY=true`.
Confirm `APP_KEY` does **not** appear in the stack's `compose_file_content`
(`grep APP_KEY` of the rendered compose shows only the `$${APP_KEY}` reference).

- [ ] **Step 3: Run the web installer**

Browse to `https://daedalus.<tld>`. In the installer choose **SQLite** for the
database and **filesystem** for cache/session/queue, then create the admin user.

- [ ] **Step 4: Record the admin credentials in Bitwarden**

Store the admin email + password as a Bitwarden item (e.g. "Pelican daedalus
admin"). These are not re-derivable from the repo; the volume backup (Task 8) is
their disaster-recovery path together with `APP_KEY`.

- [ ] **Step 5: Verify the panel is healthy**

Run: `curl -sf -o /dev/null -w '%{http_code}\n' https://daedalus.<tld>/up`
Expected: `200`. The Traefik dashboard shows the `pelican` service healthy.

---

## Task 6: Register the Wings node and hand off its config (SP1 seam)

Create the node in the panel and feed its generated config to sub-project 1's
`wings` role. The node points at the i7's **Tailscale IP** (not its MagicDNS
name — the container resolves via Docker DNS, not the tailnet) over **HTTP**
(the tailnet is already encrypted, so no cert is needed on the i7).

**Files:** none (operational; produces input for SP1 Task 12).

- [ ] **Step 1: Find the i7's Tailscale IP**

Run (from any tailnet member, e.g. the Linode host): `tailscale status | grep mc-compute`
Expected: the i7 listed; note its `100.x.y.z` address.

- [ ] **Step 2: Create the node in the panel**

In `daedalus.<tld>` → Admin → Nodes → Create:
- FQDN/address: the i7's `100.x.y.z` Tailscale IP.
- Scheme: **HTTP** (uncheck "Behind Proxy"/SSL).
- Daemon port `8080`, SFTP port `2022`.
- Allocate the game-port range that matches SP1's ACL (`25565`+).

- [ ] **Step 3: Copy the generated node config**

On the node's "Configuration" tab, copy the full `config.yml` Pelican generates
(it embeds the node token).

- [ ] **Step 4: Converge Wings on the i7** (this is SP1 Task 12, Step 6)

Run:
```bash
cd homelab/ansible && ansible-playbook site.yml --limit i7 \
  --extra-vars "tailscale_authkey=<compute_auth_key> wings_config='$(cat <saved-config.yml>)'"
```
Expected: Wings installed and active; the node shows **connected** (green
heartbeat) in the panel.

- [ ] **Step 5: Verify the panel reaches Wings over Tailscale**

In the panel the node's resource stats (CPU/memory) populate, confirming the
panel container reached `http://100.x.y.z:8080` through the Linode host's
`tailscale0`.

---

## Task 7: Dedicated Object Storage key for Pelican backups (production env)

The backups bucket and its keys live in `linode/environments/production`. Add a
dedicated, non-rotating Object Storage key scoped to that bucket and surface the
credentials so the `dokploy` env can consume them. (A separate key — not the
acme key — avoids the 90-day rotation breaking the Dokploy backup destination.)

**Files:**
- Modify: `linode/environments/production/base.tf`
- Modify: `linode/environments/production/outputs.tf`

- [ ] **Step 1: Add the access key** (near `linode_object_storage_bucket.infra_backups`)

```hcl
# Dedicated key for Dokploy's native volume backups (Pelican). Separate from
# the acme/postgres key so its 90-day rotation can't break Dokploy's backup
# destination, which holds the credentials statically.
resource "linode_object_storage_key" "dokploy_backups" {
  label = "${local.resource_prefix}-dokploy-backups"

  bucket_access {
    bucket_name = linode_object_storage_bucket.infra_backups.label
    region      = linode_object_storage_bucket.infra_backups.region
    permissions = "read_write"
  }
}
```

- [ ] **Step 2: Surface the credentials** in `outputs.tf`

```hcl
output "dokploy_backups_bucket" {
  value       = linode_object_storage_bucket.infra_backups.label
  description = "Bucket for Dokploy volume backups; copy into the dokploy env .env"
}

output "dokploy_backups_endpoint" {
  value       = linode_object_storage_bucket.infra_backups.s3_endpoint
  description = "S3 endpoint host for Dokploy volume backups"
}

output "dokploy_backups_region" {
  value       = linode_object_storage_bucket.infra_backups.region
  description = "Bucket region for Dokploy volume backups"
}

output "dokploy_backups_access_key" {
  value       = linode_object_storage_key.dokploy_backups.access_key
  sensitive   = true
  description = "Access key ID for Dokploy volume backups"
}

output "dokploy_backups_secret_key" {
  value       = linode_object_storage_key.dokploy_backups.secret_key
  sensitive   = true
  description = "Secret access key for Dokploy volume backups"
}
```

- [ ] **Step 3: Validate, then apply the production env**

Run:
```bash
cd linode/environments/production && terraform validate
bash production.sh
```
Expected: `Success! The configuration is valid.`; apply creates
`linode_object_storage_key.dokploy_backups`.

- [ ] **Step 4: Read the credentials for the handoff**

```bash
cd linode/environments/production
terraform output -raw dokploy_backups_bucket
terraform output -raw dokploy_backups_endpoint
terraform output -raw dokploy_backups_region
terraform output -raw dokploy_backups_access_key
terraform output -raw dokploy_backups_secret_key
```
Expected: five values; carry them to Task 8 (do not commit them in plaintext).

---

## Task 8: Native volume backup to Linode Object Storage (dokploy env)

Add the Dokploy backup destination (the bucket from Task 7) and a volume backup
for `pelican-data`. Credentials come from the dokploy env's chezmoi-managed
`.env` as `TF_VAR_*`, matching how `DOKPLOY_API_KEY` is supplied.

**Files:**
- Modify: `linode/environments/dokploy/variables.tf`
- Modify: `linode/environments/dokploy/main.tf`
- Modify: `.secrets/linode/environments/dokploy/encrypted_dot_env` (via chezmoi)

- [ ] **Step 1: Bump the dokploy provider to `0.4.0`** in `main.tf`

`dokploy_backup_destination` and `dokploy_volume_backup` are provided by
`j0bIT/dokploy` `0.4.0`. Bump the pin; the change is additive for the
`project`, `compose`, and `environment_variables` resources already in use, so
no other edits are required.

```hcl
dokploy = {
  source  = "j0bIT/dokploy"
  version = "0.4.0"
}
```

- [ ] **Step 2: Add the backup variables** to `variables.tf`

```hcl
variable "PELICAN_BACKUP_BUCKET" {
  type        = string
  nullable    = false
  description = "Object Storage bucket for the Pelican volume backup (from production output)."
}

variable "PELICAN_BACKUP_ENDPOINT" {
  type        = string
  nullable    = false
  description = "S3 endpoint host for the backup bucket (e.g. us-ord-1.linodeobjects.com)."
}

variable "PELICAN_BACKUP_REGION" {
  type        = string
  nullable    = false
  description = "Region of the backup bucket (e.g. us-ord-1)."
}

variable "PELICAN_BACKUP_ACCESS_KEY_ID" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Access key ID for the backup bucket."
}

variable "PELICAN_BACKUP_SECRET_ACCESS_KEY" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Secret access key for the backup bucket."
}
```

- [ ] **Step 3: Add the destination + volume backup resources** to `main.tf`
  (after `dokploy_environment_variables.pelican`)

```hcl
resource "dokploy_backup_destination" "linode" {
  name              = "linode-object-storage"
  bucket            = var.PELICAN_BACKUP_BUCKET
  endpoint          = var.PELICAN_BACKUP_ENDPOINT
  region            = var.PELICAN_BACKUP_REGION
  access_key_id     = var.PELICAN_BACKUP_ACCESS_KEY_ID
  secret_access_key = var.PELICAN_BACKUP_SECRET_ACCESS_KEY
}

# Nightly backup of the panel's SQLite + APP_KEY-bearing .env. service_name and
# volume_name match the pelican service and its named volume in the compose file.
resource "dokploy_volume_backup" "pelican_data" {
  compose_id        = dokploy_compose.stack.id
  destination_id    = dokploy_backup_destination.linode.id
  name              = "pelican-data"
  service_name      = "pelican"
  volume_name       = "pelican-data"
  cron_expression   = "0 3 * * *"
  keep_latest_count = 14
  enabled           = true
}
```

- [ ] **Step 4: Add the credentials to the dokploy chezmoi `.env`**

Edit the encrypted env via chezmoi and append the five `TF_VAR_*` values from
Task 7, Step 4:

```bash
bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --edit \
  linode/environments/dokploy/.env
```

Append:
```dotenv
TF_VAR_PELICAN_BACKUP_BUCKET=<bucket>
TF_VAR_PELICAN_BACKUP_ENDPOINT=<endpoint>
TF_VAR_PELICAN_BACKUP_REGION=<region>
TF_VAR_PELICAN_BACKUP_ACCESS_KEY_ID=<access-key-id>
TF_VAR_PELICAN_BACKUP_SECRET_ACCESS_KEY=<secret-access-key>
```

- [ ] **Step 5: Format, validate, and apply**

Run:
```bash
cd linode/environments/dokploy
terraform fmt && terraform validate
bash dokploy.sh
```
Expected: `Success! The configuration is valid.`; apply creates
`dokploy_backup_destination.linode` and `dokploy_volume_backup.pelican_data`.

- [ ] **Step 6: Trigger a backup and verify the object lands in the bucket**

In the panel (or via the Dokploy API) run the `pelican-data` volume backup
once, then:
```bash
cd linode/environments/production
s3cmd ls "s3://$(terraform output -raw dokploy_backups_bucket)/" | grep -i pelican
```
Expected: at least one backup object for `pelican-data`.

---

## Task 9: Correct the architecture doc and document the panel

Fix the inaccurate "disable Caddy" line in the parent design and add a short
operator note so the panel's run mode and recovery story aren't only in this
plan (per the "no plan refs in long-lived docs" convention, describe the
pattern, not the plan).

**Files:**
- Modify: `docs/plans/2026-06-14-minecraft-management-architecture-design.md`
- Modify: `linode/README.md`

- [ ] **Step 1: Fix the Caddy wording** in the architecture doc's sub-project 2
  section. Replace:

  > Pelican's bundled Caddy is disabled; the panel runs **behind the existing
  > Traefik** at `daedalus.<tld>` via labels

  with:

  > Pelican runs in `BEHIND_PROXY=true` mode (its bundled Caddy stays on plain
  > HTTP `:80`, `auto_https off`); the panel sits **behind the existing
  > Traefik** at `daedalus.<tld>` via labels, which terminates TLS and routes to
  > container port 80

- [ ] **Step 2: Add a "Pelican panel (daedalus)" subsection** to `linode/README.md`

```markdown
## Pelican panel (daedalus)

The game-server panel runs as the `pelican` service in the Dokploy stack,
behind Traefik at `daedalus.<tld>` in `BEHIND_PROXY` mode (TLS terminates at
Traefik). It is a single container — supervisord runs php-fpm, the queue
worker, the scheduler, and Caddy. State (SQLite, `APP_KEY`, uploads) lives on
the `pelican-data` volume, backed up nightly to Object Storage via Dokploy.

All panel env is delivered by the `dokploy_environment_variables` resource in
the `dokploy` environment (so the compose file holds no values); `APP_KEY` is
the only secret, in `.secrets/compose/pelican.env`. Disaster recovery = restore
the `pelican-data` backup plus `APP_KEY`; the admin login is in Bitwarden.

The Wings node points at the i7's Tailscale IP over HTTP; the node config the
panel generates is consumed by the homelab `wings` Ansible role.
```

- [ ] **Step 3: Confirm markdown lints clean**

Run: `npx markdownlint-cli linode/README.md docs/plans/2026-06-14-minecraft-management-architecture-design.md`
Expected: no errors (matches the repo's `.markdownlint.yml`).

---

## Out of scope (v1, YAGNI)

- Public player ingress (Infrared) — sub-project 3.
- Headless/automated panel install (`p:user:make` + pre-seeded `.env`); the web
  installer is the chosen one-time step.
- Mail delivery (`MAIL_DRIVER=log` is the default; no SMTP wired).
- GPG-at-rest for the volume backup (native Dokploy backup chosen; bucket-side
  encryption only).
- Local-dev Pelican beyond reachability (no Wings/Tailscale locally).
