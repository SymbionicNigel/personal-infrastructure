#!/usr/bin/env bash

apt-get update -y && apt-get upgrade -y

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
adduser symbionic_dokploy_user sudo
cp /root/.ssh/authorized_keys /home/symbionic_dokploy_user/.ssh/authorized_keys

# Install docker and docker compose
curl -fsSL https://get.docker.com -o get-docker.sh
sh get-docker.sh
rm get-docker.sh

systemctl enable docker
usermod -aG docker symbionic_dokploy_user

# Install dokploy
curl -sSL https://dokploy.com/install.sh | sh

# Configure firewall with ufw
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH # Remove this if I ever move to tailscale
ufw allow 80
ufw allow 443
ufw allow 3000

ufw enable
