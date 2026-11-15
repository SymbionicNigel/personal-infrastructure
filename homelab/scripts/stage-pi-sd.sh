#!/usr/bin/env bash
# Stage the mc-gateway payload onto a freshly flashed Ubuntu Pi SD card's FAT32
# system-boot partition. Raspberry Pi Imager can't customize a "Use custom"
# image, so we author cloud-init directly: overwrite user-data (hostname,
# deploy user + SSH key, first-boot runcmd) and drop the tailnet join payload
# (install-tailscale.sh, pi-firstrun.sh, tailscale-authkey). Everything lives on
# the one FAT32 partition Windows/WSL can write.
#
# Usage:
#   stage-pi-sd.sh --boot /mnt/e --authkey "$(terraform -chdir=... \
#     output -raw tailnet_gateway_auth_key)"
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$(dirname "$SCRIPT_DIR")"
PI_DIR="$HOMELAB_DIR/pi"

BOOT=""
AUTHKEY=""

usage() { echo "Usage: $0 --boot /mnt/X --authkey KEY" >&2; exit 64; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    --boot)    BOOT="${2:?}"; shift 2 ;;
    --authkey) AUTHKEY="${2:?}"; shift 2 ;;
    *)         usage ;;
  esac
done

if [ -z "$BOOT" ] || [ -z "$AUTHKEY" ]; then usage; fi
[ -d "$BOOT" ] || { echo "boot mount not found: $BOOT" >&2; exit 1; }
[ -f "$BOOT/user-data" ] || {
  echo "$BOOT has no user-data — not an Ubuntu Pi boot partition?" >&2; exit 1; }
[ -r "$HOMELAB_DIR/authorized_keys" ] || {
  echo "homelab/authorized_keys missing — run 'czm apply' first" >&2; exit 1; }

# Render user-data: expand the @@AUTHORIZED_KEYS@@ marker into a YAML list.
while IFS= read -r line; do
  if [ "$line" = "@@AUTHORIZED_KEYS@@" ]; then
    while IFS= read -r k; do
      case "$k" in ''|\#*) continue ;; esac
      printf '      - "%s"\n' "$k"
    done < "$HOMELAB_DIR/authorized_keys"
  else
    printf '%s\n' "$line"
  fi
done < "$PI_DIR/user-data" > "$BOOT/user-data"

cp "$SCRIPT_DIR/install-tailscale.sh" "$BOOT/install-tailscale.sh"
cp "$SCRIPT_DIR/pi-firstrun.sh"       "$BOOT/pi-firstrun.sh"
printf '%s' "$AUTHKEY" > "$BOOT/tailscale-authkey"

echo "Staged mc-gateway payload to $BOOT:"
echo "  user-data (hostname mc-gateway, deploy user + SSH key, first-boot runcmd)"
echo "  install-tailscale.sh, pi-firstrun.sh, tailscale-authkey"
echo "Eject the card and boot the Pi on Ethernet."
