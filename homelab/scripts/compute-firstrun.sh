#!/usr/bin/env bash
# Runs once on the ThinkCentre's first boot (via mc-firstrun.service). Joins
# the tailnet as tag:mc-compute, then shreds the key, disables the unit, and
# removes itself. Guards on the key file so reboots are no-ops. The compute
# analogue of pi-firstrun.sh.
set -euo pipefail
KEY_FILE=/etc/mc-compute-authkey
UNIT=mc-firstrun.service
[ -r "$KEY_FILE" ] || { echo "no auth key file; nothing to do" >&2; exit 0; }
AUTHKEY="$(tr -d '[:space:]' < "$KEY_FILE")"
# No --ssh (Tailscale SSH is the cloud host's job) and no routes (only the Pi
# is a subnet router).
/usr/local/sbin/install-tailscale.sh \
  --authkey "$AUTHKEY" \
  --advertise-tags tag:mc-compute
systemctl disable "$UNIT" || true
rm -f "/etc/systemd/system/$UNIT"
shred -u "$KEY_FILE" "$0" || rm -f "$KEY_FILE" "$0"
