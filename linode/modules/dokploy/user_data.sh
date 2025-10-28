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
# Restart SSH to apply changes
systemctl restart sshd

# Configure timezone data
echo "tzdata tzdata/Areas select America" | debconf-set-selections
echo "tzdata tzdata/Zones/America select New_York" | debconf-set-selections
dpkg-reconfigure -f noninteractive tzdata

# Configure hostname
hostnamectl set-hostname "dokploy-main.${HOSTNAME_TLD}"

# Create non-root user
adduser symbionic_dokploy_user sudo
# TODO: add ssh key for this user


# TODO: install dokploy and other data/users