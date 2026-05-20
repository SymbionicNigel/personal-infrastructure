#!/usr/bin/env bash

set -euo pipefail

# Prevent dpkg conffile prompts from hanging cloud-init. -y alone is not
# enough — apt auto-accepts package versions but dpkg still prompts on
# config-file conflicts. confdef/confold tells it to keep the existing file
# on conflict (which is what we want — cloud-init's customizations win).
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

apt-get update -y
apt-get upgrade "$${APT_OPTS[@]}"
apt-get install "$${APT_OPTS[@]}" curl jq ufw sl s3cmd gnupg unattended-upgrades fail2ban

# Configure unattended-upgrades to apply security-pocket updates only, without
# auto-reboot. Running services stay up across patches; we reboot manually.
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
    "$${distro_id}ESM:$${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UU_EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AU_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AU_EOF

systemctl enable --now unattended-upgrades.service

# fail2ban: ban source IPs after repeated SSH auth failures. Dashboard
# bruteforce is handled separately (Traefik rate-limit, future).
cat > /etc/fail2ban/jail.d/sshd.local <<'F2B_EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
F2B_EOF

systemctl enable --now fail2ban.service

# Function to robustly set SSH config parameters
set_ssh_config() {
    local key="$1"
    local value="$2"
    local config_file="/etc/ssh/sshd_config"

    if grep -q "^#*$key" "$config_file"; then
        # Parameter exists (commented or not) - replace it
        sed -i "s/^#*$key.*/$key $value/" "$config_file"
    else
        # Parameter doesn't exist - add it
        echo "$key $value" >> "$config_file"
    fi
}
# SSH hardening configuration
set_ssh_config "PasswordAuthentication" "no"
set_ssh_config "PermitRootLogin" "no"
set_ssh_config "PubkeyAuthentication" "yes"
set_ssh_config "ChallengeResponseAuthentication" "no"
set_ssh_config "UsePAM" "no"
# Restart SSH to apply changes
systemctl restart sshd

# Configure timezone data
echo "tzdata tzdata/Areas select America" | debconf-set-selections
echo "tzdata tzdata/Zones/America select New_York" | debconf-set-selections
dpkg-reconfigure -f noninteractive tzdata

# Configure hostname
hostnamectl set-hostname "dokploy-main.${HOSTNAME_TLD}"

# Create non-root user and add public key
adduser --disabled-password --gecos "" symbionic_dokploy_user
usermod -aG sudo symbionic_dokploy_user
mkdir -p /home/symbionic_dokploy_user/.ssh
cp /root/.ssh/authorized_keys /home/symbionic_dokploy_user/.ssh/authorized_keys
chown -R symbionic_dokploy_user:symbionic_dokploy_user /home/symbionic_dokploy_user/.ssh
chmod 700 /home/symbionic_dokploy_user/.ssh
chmod 600 /home/symbionic_dokploy_user/.ssh/authorized_keys

# Install docker and docker compose
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

systemctl enable docker
usermod -aG docker symbionic_dokploy_user

# Passwordless sudo so terraform provisioners can run privileged commands
# without an interactive prompt. Scope narrow: only this one user.
cat > /etc/sudoers.d/symbionic_dokploy_user <<'SUDO_EOF'
symbionic_dokploy_user ALL=(ALL) NOPASSWD:ALL
SUDO_EOF
chmod 440 /etc/sudoers.d/symbionic_dokploy_user
visudo -c -f /etc/sudoers.d/symbionic_dokploy_user

# Install dokploy at the pinned version. The install script reads
# DOKPLOY_VERSION from the environment; without it, it auto-detects the
# latest release from GitHub, which would silently roll forward on rebuild.
export DOKPLOY_VERSION="${DOKPLOY_VERSION}"
curl -sSL https://dokploy.com/install.sh | sh

# Wait for Dokploy to be ready
until curl -sf http://localhost:3000 > /dev/null 2>&1; do sleep 5; done

# Create admin user (after hook auto-creates organization + owner member).
# Origin header satisfies better-auth's trustedOrigins check. curl -sf + set -e
# will halt the script if the API returns a non-2xx response.
curl -sf -X POST http://localhost:3000/api/auth/sign-up/email \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -d '{"email":"${DOKPLOY_ADMIN_EMAIL}","password":"${DOKPLOY_ADMIN_PASSWORD}","name":"admin"}' > /dev/null

# Sign in to get session cookie
COOKIE_JAR=$(mktemp)
curl -sf -X POST http://localhost:3000/api/auth/sign-in/email \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -c "$COOKIE_JAR" \
  -d '{"email":"${DOKPLOY_ADMIN_EMAIL}","password":"${DOKPLOY_ADMIN_PASSWORD}"}' > /dev/null

# Get the organization ID. The org is created by better-auth's after-hook on
# sign-up, which runs asynchronously — under post-install load it can take a
# few seconds to materialize, so retry briefly before giving up.
#
# Path is /api/auth/organization/list (better-auth org plugin) — NOT
# /api/auth/list-organizations (route does not exist in better-auth >=1.5.x).
#
# `-s` (no `-f`) so non-2xx responses don't kill the loop under set -e; we
# parse the body either way and rely on the jq guard. No Origin header
# because better-auth's GET routes are permissive about Origin and Dokploy's
# trustedOrigins list is empty on a freshly bootstrapped box.
ORG_ID=""
for _ in $(seq 1 15); do
    RESPONSE=$(curl -s http://localhost:3000/api/auth/organization/list \
      -b "$COOKIE_JAR" 2>/dev/null || true)
    ORG_ID=$(echo "$RESPONSE" | jq -r '.[0].id // empty' 2>/dev/null || true)
    if [ -n "$ORG_ID" ] && [ "$ORG_ID" != "null" ]; then
        break
    fi
    sleep 2
done
if [ -z "$ORG_ID" ] || [ "$ORG_ID" = "null" ]; then
    echo "ERROR: Organization not found after sign-up (waited 30s)" >&2
    echo "Last response body: $RESPONSE" >&2
    exit 1
fi

# Create API key via Dokploy's user.createApiKey tRPC route, NOT better-auth's
# /api/auth/api-key/create. Two reasons the better-auth endpoint can't set rate
# limits from outside:
#   1. Its Zod schema expects flat `rateLimitEnabled`/`rateLimitMax`/
#      `rateLimitTimeWindow` fields, not a nested `rateLimit` object — unknown
#      keys are silently dropped, so the column falls back to the plugin
#      default of enabled=true, max=10/24h.
#   2. Even with the correct field names, those fields are "server-only" and
#      HTTP requests carrying them are rejected with BAD_REQUEST (see
#      better-auth packages/api-key/src/routes/create-api-key.ts isClientRequest
#      gate).
# The Dokploy route below wraps better-auth's server-side createApiKey call,
# bypassing the client gate and accepting flat rate-limit fields. Auth is via
# the session cookie picked up during sign-up. Response is tRPC+superjson, so
# the key is at .result.data.json.key.
#
# Rate limit: 1000 requests / 1 hour. Comfortably absorbs Terraform applies
# (refresh+plan+apply ≈ tens of calls per resource) plus dashboard browsing,
# while still catching runaway loops or compromised keys.
API_KEY_RESPONSE=$(curl -s -X POST http://localhost:3000/api/trpc/user.createApiKey \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -b "$COOKIE_JAR" \
  -d "{\"json\":{\"name\":\"terraform\",\"rateLimitEnabled\":true,\"rateLimitTimeWindow\":3600000,\"rateLimitMax\":1000,\"metadata\":{\"organizationId\":\"$ORG_ID\"}}}" \
  2>/dev/null || true)
API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.result.data.json.key // empty' 2>/dev/null || true)
if [ -z "$API_KEY" ] || [ "$API_KEY" = "null" ]; then
    echo "ERROR: API key creation failed" >&2
    echo "Response body: $API_KEY_RESPONSE" >&2
    exit 1
fi

# Atomic write of the API key sentinel so a partial failure cannot leave a
# zero-byte file that fools the Terraform `test -s` gate.
TMP_KEY=$(mktemp)
printf '%s' "$API_KEY" > "$TMP_KEY"
chmod 600 "$TMP_KEY"
mv "$TMP_KEY" /root/.dokploy-api-key

rm -f "$COOKIE_JAR"

# Domain binding (assignDomainServer) is performed by Terraform after the
# wildcard A record exists, not from this script — see the bind_dokploy_domain
# null_resource in the production environment.

# --- acme.json backup tooling ---------------------------------------------
# Inlined backup script, systemd units, and timer. The gpg public key,
# /root/.s3cfg, and /root/.acme-backup.env are SSH-pushed by Terraform's
# null_resource.configure_acme_backup AFTER cloud-init completes — keeps
# credentials out of the Linode metadata service. The systemd service has
# ConditionPathExists guards on those files, so the timer is safe to enable
# now; until Terraform pushes them, the service fires and skips silently.

cat > /usr/local/bin/backup_acme.sh <<'BACKUP_SCRIPT_EOF'
#!/usr/bin/env bash
# Backs up /etc/dokploy/traefik/dynamic/acme.json to $${BACKUP_BUCKET} as acme.json.gpg.
# Asymmetric gpg using the public key imported into root's keyring (recipient = GPG_RECIPIENT).
# Five guardrails — see GUARDS in-line. Exits non-zero on any failure so systemd surfaces it.

set -euo pipefail

ACME_PATH="/etc/dokploy/traefik/dynamic/acme.json"
BUCKET="$${BACKUP_BUCKET:?BACKUP_BUCKET must be set}"
RECIPIENT="$${GPG_RECIPIENT:?GPG_RECIPIENT must be set}"
KEY="acme.json.gpg"
MIN_BYTES=200
REGRESSION_RATIO=50

log() { printf '[backup_acme] %s\n' "$*" >&2; }

# GUARD 1: source exists and above floor
if [ ! -s "$ACME_PATH" ]; then log "ABORT: $ACME_PATH missing or empty"; exit 1; fi
LOCAL_BYTES=$(stat -c %s "$ACME_PATH")
if [ "$LOCAL_BYTES" -lt "$MIN_BYTES" ]; then
    log "ABORT: $ACME_PATH is $LOCAL_BYTES bytes (< $MIN_BYTES floor)"; exit 1
fi

# GUARD 2: source parses as JSON
if ! jq empty "$ACME_PATH" >/dev/null 2>&1; then
    log "ABORT: $ACME_PATH is not valid JSON"; exit 1
fi

# GUARD 3: regression check vs remote (skip if remote missing)
REMOTE_BYTES=""
if s3cmd info "s3://$${BUCKET}/$${KEY}" >/dev/null 2>&1; then
    # awk: parse "File size: <bytes>" by colon; gsub strips surrounding whitespace.
    # Robust across s3cmd 2.x format variants observed as of 2026-05.
    REMOTE_BYTES=$(s3cmd info "s3://$${BUCKET}/$${KEY}" \
        | awk -F: '/File size/ {gsub(/[[:space:]]/, "", $2); print $2; exit}')
fi
if [ -n "$REMOTE_BYTES" ] && [ "$REMOTE_BYTES" -gt 0 ]; then
    THRESHOLD=$(( REMOTE_BYTES * REGRESSION_RATIO / 100 ))
    NEW_ENCRYPTED_EST=$(( LOCAL_BYTES * 105 / 100 ))
    if [ "$NEW_ENCRYPTED_EST" -lt "$THRESHOLD" ]; then
        log "ABORT: new encrypted size ~$${NEW_ENCRYPTED_EST}B < $${REGRESSION_RATIO}% of remote $${REMOTE_BYTES}B"
        exit 1
    fi
fi

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT
ENCRYPTED="$${WORKDIR}/$${KEY}"

gpg --batch --yes --trust-model always \
    --recipient "$RECIPIENT" \
    --output "$ENCRYPTED" \
    --encrypt "$ACME_PATH"

# GUARD 4: direct PUT — S3 PUT is atomic on its own, and bucket versioning
# preserves prior good copies for the lifecycle-rule retention window.
s3cmd put "$ENCRYPTED" "s3://$${BUCKET}/$${KEY}" >/dev/null

# GUARD 5: any failure above triggers `set -e` → non-zero exit. systemd surfaces it.

log "OK: uploaded $${LOCAL_BYTES}B plaintext / $(stat -c %s "$ENCRYPTED")B encrypted"
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

# Configure firewall with ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH # Remove this if I ever move to tailscale
ufw allow 80
ufw allow 443

ufw --force enable
