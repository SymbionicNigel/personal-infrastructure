# Plan: Deploy Dokploy on Linode with Automated Bootstrap

## Context

The project has Terraform modules for provisioning a Dokploy instance on Linode
and managing DNS, but they have bugs preventing successful deployment. There is
no deploy script and no Dokploy configuration-as-code. The goal is to:

1. Fix existing TF bugs and get the Linode instance deployed
2. Add a second TF stage using `j0bIT/dokploy` provider (v0.3.0) to manage
   Dokploy resources (projects, apps, domains, env vars)
3. Create a deploy script for running TF locally, with Dokploy's built-in
   GitHub integration handling application code redeploys on push

Architecture is **two-stage Terraform** (provider config can't depend on
resources, so the Dokploy provider needs the instance already running):

- **Stage 1** (`linode/environments/production/`): The instance and everything
  on it — Linode, DNS, cloud-init (Docker, Dokploy, admin account, API key).
  Changes rarely — only when rebuilding or reconfiguring the server.
- **Stage 2** (`linode/environments/dokploy/`): What runs on Dokploy —
  projects, apps, domains, env vars. Changes frequently as services are
  added/modified.

The Dokploy admin account and API key are **automated in cloud-init** via
Dokploy's better-auth API. The API key is retrieved once via SSH after Stage 1
completes (same pattern as retrieving bootstrap TF outputs to populate
production `.env`).

---

## Phase 1: Fix Existing Bugs

### 1a. SSH key resource — `linode/modules/dokploy/main.tf`

Line 22: `chomp("${path.root}/id_es25519.pub")` passes the literal path string
as the SSH key. Two bugs: missing `file()` call, and typo `es` vs `ed`.

```hcl
# Fix to:
ssh_key = chomp(file("${path.root}/id_ed25519.pub"))
```

### 1b. Missing tags — `linode/modules/dokploy/main.tf`

`linode_instance.dokploy_main` accepts `var.TAGS` but never applies it. Add
`tags = tolist(var.TAGS)` to the resource (matches pattern in `domain/main.tf`).

### 1c. user_data.sh — multiple fixes `linode/modules/dokploy/user_data.sh`

**User creation** (lines 37-38): `adduser` prompts interactively, `.ssh` dir
doesn't exist yet.

```bash
adduser --disabled-password --gecos "" symbionic_dokploy_user
usermod -aG sudo symbionic_dokploy_user
mkdir -p /home/symbionic_dokploy_user/.ssh
cp /root/.ssh/authorized_keys /home/symbionic_dokploy_user/.ssh/authorized_keys
chown -R symbionic_dokploy_user:symbionic_dokploy_user /home/symbionic_dokploy_user/.ssh
chmod 700 /home/symbionic_dokploy_user/.ssh
chmod 600 /home/symbionic_dokploy_user/.ssh/authorized_keys
```

**Add automated Dokploy admin + API key creation** (new section, after Dokploy
install, before firewall). Dokploy uses better-auth with `emailAndPassword`
enabled. The relevant API endpoints are:

- `POST /api/auth/sign-up/email` — Creates a user. A `before` hook in
  `packages/server/src/lib/auth.ts:131-154` checks if any `owner` member
  exists; if not, signup is allowed. The `after` hook auto-creates an
  organization + member with `role: "owner"`.
- `POST /api/auth/sign-in/email` — Returns a session cookie.
- `POST /api/auth/api-key/create` — better-auth's `apiKey` plugin endpoint.
  Requires auth (session cookie) and `metadata.organizationId`.

```bash
# Wait for Dokploy to be ready
until curl -sf http://localhost:3000 > /dev/null 2>&1; do sleep 5; done

# Create admin user (after hook auto-creates organization + owner member)
curl -s -X POST http://localhost:3000/api/auth/sign-up/email \
  -H "Content-Type: application/json" \
  -d '{"email":"${DOKPLOY_ADMIN_EMAIL}","password":"${DOKPLOY_ADMIN_PASSWORD}","name":"admin"}'

# Sign in to get session cookie
COOKIE_JAR=$(mktemp)
curl -s -X POST http://localhost:3000/api/auth/sign-in/email \
  -H "Content-Type: application/json" \
  -c "$COOKIE_JAR" \
  -d '{"email":"${DOKPLOY_ADMIN_EMAIL}","password":"${DOKPLOY_ADMIN_PASSWORD}"}'

# Get the organization ID (auto-created by sign-up after hook)
# NOTE: Verify during implementation whether the org is available
# immediately after sign-up or if a retry loop is needed.
ORG_ID=$(curl -s http://localhost:3000/api/auth/list-organizations \
  -b "$COOKIE_JAR" | jq -r '.[0].id')
[ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ] && \
  { echo "ERROR: Organization not found"; exit 1; }

# Create API key using better-auth's apiKey plugin
API_KEY=$(curl -s -X POST http://localhost:3000/api/auth/api-key/create \
  -H "Content-Type: application/json" \
  -b "$COOKIE_JAR" \
  -d "{\"name\":\"terraform\",\"expiresIn\":null,\"metadata\":{\"organizationId\":\"$ORG_ID\"}}" \
  | jq -r '.key')

# Write API key to a file for retrieval by the deploy script
echo "$API_KEY" > /root/.dokploy-api-key
chmod 600 /root/.dokploy-api-key

rm -f "$COOKIE_JAR"
```

This requires two new templatefile variables: `DOKPLOY_ADMIN_EMAIL` and
`DOKPLOY_ADMIN_PASSWORD`, with corresponding TF variables threaded through the
module. The API key is written to `/root/.dokploy-api-key` and retrieved
automatically by the deploy script (see Phase 3).

**Update firewall** (lines 52-59): Add `--force` to `ufw enable` so it doesn't
prompt in cloud-init. Keep SSH (key-only auth).

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80
ufw allow 443
ufw allow 3000       # Dokploy UI — restrict after initial setup if desired
ufw --force enable
```

### 1d. Linode provider auth — `linode/environments/production/base.tf`

Currently uses `config_path`/`config_profile` (linode-cli config file on disk).
Switch to token-based auth matching the bootstrap pattern
(`TF_VAR_linode_token` in `linode/environments/bootstrap/.env`).

Add `LINODE_TOKEN` to `variables.tf` and simplify the provider block. Remove
the `config_path`/`config_profile` and the `locals` block that computed the
config profile name — no longer needed.

```hcl
# variables.tf — add:
variable "LINODE_TOKEN" {
  type        = string
  sensitive   = true
  description = "Linode API token"
}

# base.tf — replace provider block:
provider "linode" {
  token = var.LINODE_TOKEN
}
```

Add `TF_VAR_LINODE_TOKEN=<token>` to the production `.env` (same value as
`TF_VAR_linode_token` in the bootstrap `.env`).

### 1e. Thread new variables through TF — `linode/modules/dokploy/`

Add variables to the dokploy module's `variables.tf` and pass them through
`templatefile()` in `main.tf`:

```hcl
# modules/dokploy/variables.tf — add:
variable "DOKPLOY_ADMIN_EMAIL" {
  type        = string
  sensitive   = true
  description = "Email for the auto-created Dokploy admin account"
}

variable "DOKPLOY_ADMIN_PASSWORD" {
  type        = string
  sensitive   = true
  description = "Password for the auto-created Dokploy admin account"
}

# modules/dokploy/main.tf — update metadata block:
metadata {
  user_data = base64encode(templatefile("${path.module}/user_data.sh", {
    HOSTNAME_TLD           = var.HOSTNAME_TLD
    DOKPLOY_ADMIN_EMAIL    = var.DOKPLOY_ADMIN_EMAIL
    DOKPLOY_ADMIN_PASSWORD = var.DOKPLOY_ADMIN_PASSWORD
  }))
}
```

Add corresponding variables + passthrough in `production/base.tf` and
`production/variables.tf`. Add `TF_VAR_DOKPLOY_ADMIN_EMAIL` and
`TF_VAR_DOKPLOY_ADMIN_PASSWORD` to production `.env`. The production `.env`
is already chezmoi-managed via `bootstrap.sh`'s `add_or_merge_to_chezmoi`
call, so these values are automatically stored in `.secrets/`.

---

## Phase 2: Dokploy TF Environment

### Traefik and Subdomain Routing

Dokploy ships with its own Traefik instance that handles container routing and
TLS. This replaces the custom Traefik (`hendrix`) in `docker-compose.yml`,
which remains for local development only. Dokploy's Traefik already provides
automated subdomain routing based on Docker containers — the same goal as the
project's custom Traefik config. Adding `dokploy_domain` resources with
`https = true` configures Dokploy's Traefik to route and terminate TLS for
each service.

The wildcard DNS record (`*.HOSTNAME_TLD`) from Stage 1 means any new
`dokploy_domain` resource automatically resolves — adding a new service with
a domain is the only step needed for subdomain routing.

### New files under `linode/environments/dokploy/`

**`main.tf`** — Provider + initial resources:
- `dokploy_project.main` — "symbionic-services"
- `dokploy_application.whoami` — `traefik/whoami` Docker image (smoke test)
- `dokploy_domain.whoami` — `whoami.<HOSTNAME_TLD>` with HTTPS

**`variables.tf`** — `DOKPLOY_HOST`, `DOKPLOY_API_KEY` (sensitive), `HOSTNAME_TLD`

**`outputs.tf`** — Project ID, app IDs for reference

**`backend.hcl`** — Same S3 bucket as production, different key (`dokploy.tfstate`)

**`.env.example`** — Template with all needed vars (DOKPLOY_API_KEY, S3 creds, TF_VARs)

The whoami app validates the full pipeline: Linode -> DNS -> Dokploy -> Traefik
-> app -> HTTPS domain routing. Once validated, adding more services is just
adding `dokploy_application` + `dokploy_domain` resources to `main.tf`.

---

## Phase 3: Deploy Scripts

### `scripts/tf.sh` — Generic TF executor (run locally)

```bash
#!/usr/bin/env bash
set -euo pipefail
ACTION="$1"   # init | plan | apply
TF_DIR="$2"   # relative path to TF environment

# Load .env if present
if [ -f "$TF_DIR/.env" ]; then
    set -a; source "$TF_DIR/.env"; set +a
fi

cd "$TF_DIR"
case "$ACTION" in
    init)  terraform init -backend-config=backend.hcl ;;
    plan)  terraform init -backend-config=backend.hcl -input=false
           terraform plan -input=false ;;
    apply) terraform init -backend-config=backend.hcl -input=false
           terraform apply -input=false -auto-approve ;;
esac
```

### `scripts/deploy-production.sh` — Stage 1 deploy + dokploy `.env` setup

Mirrors the `bootstrap.sh` pattern: runs TF apply, retrieves outputs,
builds the next environment's `.env`, and adds everything to chezmoi.

```bash
#!/usr/bin/env bash
# Intended to be ran from the repository root
set -euo pipefail

PROD_DIR="linode/environments/production"
DOKPLOY_DIR="linode/environments/dokploy"

# Source Bitwarden session if available
if [ -f ".env.bitwarden" ] || [ -n "${BW_SESSION:-}" ]; then
    source "./dotfile-utils/scripts/source_bitwarden_session.sh" \
        || { echo "Error: Bitwarden session setup failed"; exit 1; }
fi

# Reuse bootstrap.sh's add_or_merge_to_chezmoi pattern
add_or_merge_to_chezmoi() {
    local file_path="$1"
    if chezmoi source-path \
        --config ./.chezmoi.toml "$file_path" &>/dev/null
    then
        echo "$file_path is already managed. Merging..."
        chezmoi merge --config ./.chezmoi.toml "$file_path"
    else
        echo "$file_path is not managed. Adding..."
        source ./dotfile-utils/scripts/chezmoi-add-secret.sh \
            --encrypt "$file_path"
    fi
}

# --- Stage 1: Apply production TF ---
bash scripts/tf.sh apply "$PROD_DIR"

INSTANCE_IP=$(cd "$PROD_DIR" && terraform output -raw instance_ip)
echo "Instance IP: $INSTANCE_IP"

# --- Wait for cloud-init + Dokploy bootstrap ---
echo "Waiting for cloud-init to complete (~5 min)..."
until ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
    "root@$INSTANCE_IP" \
    "test -f /root/.dokploy-api-key" 2>/dev/null; do
    sleep 10
done

# --- Retrieve API key ---
API_KEY=$(ssh "root@$INSTANCE_IP" cat /root/.dokploy-api-key)
echo "Retrieved Dokploy API key."

# --- Build dokploy .env (same pattern as bootstrap.sh) ---
# Pull S3 creds from production .env (already loaded by tf.sh)
set -a; source "$PROD_DIR/.env"; set +a

cat > "$DOKPLOY_DIR/.env" << EOF
TF_VAR_DOKPLOY_HOST=https://${TF_VAR_HOSTNAME_TLD}:3000
TF_VAR_DOKPLOY_API_KEY=$API_KEY
TF_VAR_HOSTNAME_TLD=$TF_VAR_HOSTNAME_TLD
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
EOF

# --- Add to chezmoi (encrypt into .secrets/) ---
add_or_merge_to_chezmoi "./$DOKPLOY_DIR/.env"
add_or_merge_to_chezmoi "./$PROD_DIR/.env"

echo "Done. Run: bash scripts/tf.sh apply $DOKPLOY_DIR"
```

### Usage

```bash
# First-time or rebuild: provisions infra + generates dokploy .env
bash scripts/deploy-production.sh

# Stage 2 (and subsequent runs): apply dokploy config
bash scripts/tf.sh apply linode/environments/dokploy

# Ad-hoc TF operations on any environment
bash scripts/tf.sh plan linode/environments/production
```

### Dokploy handles application deployments

Infrastructure/config changes (TF) are applied locally via the scripts
above. Application code changes are handled by Dokploy's built-in GitHub
integration: setting `auto_deploy = true` on `dokploy_application`
resources causes Dokploy to watch the linked GitHub repo and redeploy
on push.

This means:

- **Infra changes** (new Linode resources, DNS, firewall)
  → `bash scripts/deploy-production.sh`
- **Dokploy config changes** (new projects, apps, domains, env vars)
  → `bash scripts/tf.sh apply linode/environments/dokploy`
- **Application code changes**
  → push to GitHub, Dokploy auto-redeploys

---

## Phase 4: First-Time Bootstrap Sequence

1. Run `bash linode/environments/bootstrap/bootstrap.sh` if not already
   done — creates S3 state bucket and populates production `.env` with
   S3 creds (already adds to chezmoi).
2. Add remaining vars to `linode/environments/production/.env`:
   - `TF_VAR_LINODE_TOKEN` (same as `TF_VAR_linode_token` in bootstrap)
   - `TF_VAR_DOKPLOY_ADMIN_EMAIL`, `TF_VAR_DOKPLOY_ADMIN_PASSWORD`
   - `TF_VAR_HOSTNAME_TLD`, `TF_VAR_EMAIL_ADDRESS`, `TF_VAR_REGION`
3. `bash scripts/deploy-production.sh` — This single command:
   - Applies production TF (creates Linode + DNS)
   - Waits for cloud-init to complete
   - Retrieves the Dokploy API key via SSH
   - Builds `linode/environments/dokploy/.env` with the key + S3 creds
   - Encrypts both `.env` files into `.secrets/` via chezmoi
4. `bash scripts/tf.sh apply linode/environments/dokploy` — Configures
   project + whoami app.
5. Verify `https://whoami.<HOSTNAME_TLD>` responds with HTTPS.

Update `linode/README.md` with these steps.

---

## Files to Create/Modify

| Action | File |
|---|---|
| **Edit** | `linode/modules/dokploy/main.tf` (SSH key fix, add tags, new templatefile vars) |
| **Edit** | `linode/modules/dokploy/variables.tf` (add DOKPLOY_ADMIN_EMAIL, DOKPLOY_ADMIN_PASSWORD) |
| **Edit** | `linode/modules/dokploy/user_data.sh` (adduser fix, Dokploy bootstrap, firewall) |
| **Edit** | `linode/environments/production/base.tf` (LINODE_TOKEN variable, remove config_path) |
| **Edit** | `linode/environments/production/variables.tf` (add LINODE_TOKEN, DOKPLOY_ADMIN_*) |
| **Create** | `linode/environments/dokploy/main.tf` |
| **Create** | `linode/environments/dokploy/variables.tf` |
| **Create** | `linode/environments/dokploy/outputs.tf` |
| **Create** | `linode/environments/dokploy/backend.hcl` |
| **Create** | `linode/environments/dokploy/.env.example` |
| **Create** | `scripts/tf.sh` |
| **Create** | `scripts/deploy-production.sh` |
| **Edit** | `linode/README.md` (add bootstrap docs) |

---

## Verification

1. `terraform validate` in both `linode/environments/production/`
   and `linode/environments/dokploy/`
2. `bash scripts/tf.sh plan linode/environments/production`
   succeeds (dry run)
3. `bash scripts/deploy-production.sh` provisions Linode + DNS,
   waits for cloud-init, retrieves API key, builds dokploy `.env`,
   and adds both `.env` files to chezmoi
4. Dokploy UI accessible at `http://<linode-ip>:3000`
5. `linode/environments/dokploy/.env` exists with API key populated
6. `.secrets/` contains encrypted versions of both `.env` files
7. `bash scripts/tf.sh apply linode/environments/dokploy` creates
   project + whoami app
8. `curl https://whoami.<HOSTNAME_TLD>` returns whoami response
9. SSH access works with key auth only (no password)
