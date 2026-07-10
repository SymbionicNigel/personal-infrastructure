#!/usr/bin/env bash
# Runs once on first boot from /boot/firmware/. Joins the tailnet, then wipes
# itself and the key. Ubuntu's cloud-init runcmd invokes this.
set -euo pipefail
KEY_FILE=/boot/firmware/tailscale-authkey
[ -r "$KEY_FILE" ] || { echo "no auth key file" >&2; exit 1; }
AUTHKEY="$(tr -d '[:space:]' < "$KEY_FILE")"
/usr/local/sbin/install-tailscale.sh \
  --authkey "$AUTHKEY" \
  --advertise-tags tag:mc-gateway \
  --advertise-routes "${HOME_LAN_CIDR:-192.168.1.0/24}"
shred -u "$KEY_FILE" "$0" || rm -f "$KEY_FILE" "$0"
