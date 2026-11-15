#!/usr/bin/env bash
# Runs once on first boot from /boot/firmware/. Joins the tailnet as
# tag:mc-gateway, advertises the home LAN subnet route, then wipes itself and
# the key. Ubuntu's cloud-init runcmd invokes this. Everything it needs lives on
# the FAT32 boot partition so the SD card can be staged from Windows (no ext4
# write required). The gateway analogue of compute-firstrun.sh.
set -euo pipefail
KEY_FILE=/boot/firmware/tailscale-authkey
# Home LAN subnet advertised as a subnet router. Must stay in sync with
# var.HOME_LAN_CIDR and the ACL autoApprover (linode/modules/tailnet/acl.hujson),
# or the route won't auto-approve.
HOME_LAN_CIDR=192.168.18.0/24
[ -r "$KEY_FILE" ] || { echo "no auth key file" >&2; exit 1; }
AUTHKEY="$(tr -d '[:space:]' < "$KEY_FILE")"

# Subnet routing needs kernel IP forwarding on; the tailscale package doesn't
# enable it. Persist it so it survives reboots.
printf 'net.ipv4.ip_forward = 1\nnet.ipv6.conf.all.forwarding = 1\n' \
  | sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null
sudo sysctl -p /etc/sysctl.d/99-tailscale.conf

# The Pi has no RTC; on first boot the clock is stale until NTP syncs, and a
# clock in the past makes TLS fail ("certificate is not yet valid") — which
# breaks the tailscale install/join over HTTPS. Wait for the clock before any
# HTTPS. cloud-init runs this ~35s into boot, well before timesyncd catches up.
sudo systemctl restart systemd-timesyncd || true
# shellcheck disable=SC2016  # $(...) must run inside the bash -c subshell
timeout 120 bash -c \
  'until [ "$(timedatectl show -p NTPSynchronized --value)" = yes ]; do sleep 2; done' \
  || echo "warning: clock not NTP-synced after 120s; continuing anyway" >&2

bash /boot/firmware/install-tailscale.sh \
  --authkey "$AUTHKEY" \
  --advertise-tags tag:mc-gateway \
  --advertise-routes "$HOME_LAN_CIDR"
shred -u "$KEY_FILE" "$0" || rm -f "$KEY_FILE" "$0"
