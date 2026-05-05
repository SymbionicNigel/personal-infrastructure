#!/usr/bin/env bash

set -euxo pipefail

# Prevent dpkg conffile prompts from hanging cloud-init. -y alone is not
# enough — apt auto-accepts package versions but dpkg still prompts on
# config-file conflicts. confdef/confold tells it to keep the existing file
# on conflict (which is what we want — cloud-init's customizations win).
export DEBIAN_FRONTEND=noninteractive
APT_OPTS=(-y -o Dpkg::Options::=--force-confdef -o Dpkg::Options::=--force-confold)

apt-get update -y
apt-get upgrade "$${APT_OPTS[@]}"
apt-get install "$${APT_OPTS[@]}" curl jq ufw

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
set_ssh_config "PermitRootLogin" "prohibit-password"
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

# Create API key using better-auth's apiKey plugin.
# Origin header is required: api-key/create is a POST, so better-auth runs
# its originCheck and rejects requests with no/unknown origin.
# Use `-s` (no `-f`) + `|| true` so a transient failure can be diagnosed
# from the captured body instead of killing the script via set -e.
API_KEY_RESPONSE=$(curl -s -X POST http://localhost:3000/api/auth/api-key/create \
  -H "Content-Type: application/json" \
  -H "Origin: http://localhost:3000" \
  -b "$COOKIE_JAR" \
  -d "{\"name\":\"terraform\",\"expiresIn\":null,\"metadata\":{\"organizationId\":\"$ORG_ID\"}}" \
  2>/dev/null || true)
API_KEY=$(echo "$API_KEY_RESPONSE" | jq -r '.key // empty' 2>/dev/null || true)
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

# Configure firewall with ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH # Remove this if I ever move to tailscale
ufw allow 80
ufw allow 443

ufw --force enable
