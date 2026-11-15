#!/usr/bin/env bash
# Remaster a stock Ubuntu 24.04 amd64 server ISO into a zero-touch autoinstall
# installer for the ThinkCentre (mc-compute). Injects the NoCloud autoinstall
# payload under /nocloud/ and adds the `autoinstall` kernel cmdline to GRUB so
# the box installs unattended and joins the tailnet on first boot.
#
# Usage:
#   build-thinkcentre-iso.sh --iso ubuntu-24.04-live-server-amd64.iso \
#     --authkey "$(terraform -chdir=linode/environments/production \
#       output -raw tailnet_compute_auth_key)" [--out mc-compute-autoinstall.iso] \
#     [--device /dev/sdX]
#
# With --device, the built ISO is flashed to that block device (after an
# lsblk preview + typed confirmation); without it, the dd command is printed.
# The output ISO embeds a live tailnet auth key — it is git-ignored and should
# be written to USB then discarded. Requires xorriso (apt install xorriso).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOMELAB_DIR="$(dirname "$SCRIPT_DIR")"
TC_DIR="$HOMELAB_DIR/thinkcentre"

ISO=""
AUTHKEY=""
OUT="mc-compute-autoinstall.iso"
DEVICE=""

usage() {
  echo "Usage: $0 --iso ISO --authkey KEY [--out OUT] [--device /dev/sdX]" >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --iso)     ISO="${2:?}"; shift 2 ;;
    --authkey) AUTHKEY="${2:?}"; shift 2 ;;
    --out)     OUT="${2:?}"; shift 2 ;;
    --device)  DEVICE="${2:?}"; shift 2 ;;
    *)         usage ;;
  esac
done

if [ -z "$ISO" ] || [ -z "$AUTHKEY" ]; then usage; fi
# Validate the write target early — before a long build — so a bad --device
# fails fast rather than after building the ISO.
if [ -n "$DEVICE" ]; then
  [ -b "$DEVICE" ] || { echo "--device $DEVICE is not a block device" >&2; exit 1; }
fi
command -v xorriso >/dev/null 2>&1 || { echo "xorriso not found (apt install xorriso)" >&2; exit 1; }
[ -r "$ISO" ] || { echo "ISO not readable: $ISO" >&2; exit 1; }
[ -r "$HOMELAB_DIR/authorized_keys" ] || {
  echo "homelab/authorized_keys missing — run 'czm apply' first" >&2; exit 1; }

STAGE="$(mktemp -d)"
cleanup() { shred -u "$STAGE/tailscale-authkey" 2>/dev/null || true; rm -rf "$STAGE"; }
trap cleanup EXIT

# 1. Render user-data: expand the @@AUTHORIZED_KEYS@@ marker into a YAML list.
while IFS= read -r line; do
  if [ "$line" = "@@AUTHORIZED_KEYS@@" ]; then
    while IFS= read -r k; do
      case "$k" in ''|\#*) continue ;; esac
      printf '      - "%s"\n' "$k"
    done < "$HOMELAB_DIR/authorized_keys"
  else
    printf '%s\n' "$line"
  fi
done < "$TC_DIR/user-data" > "$STAGE/user-data"

# 2. Stage the rest of the NoCloud payload.
cp "$TC_DIR/meta-data" "$STAGE/meta-data"
cp "$TC_DIR/mc-firstrun.service" "$STAGE/mc-firstrun.service"
printf '%s' "$AUTHKEY" > "$STAGE/tailscale-authkey"
chmod 0600 "$STAGE/tailscale-authkey"

# 3. Pull the ISO's GRUB config and bake in the autoinstall cmdline + fast boot.
xorriso -osirrox on -indev "$ISO" -extract /boot/grub/grub.cfg "$STAGE/grub.cfg" >/dev/null 2>&1
# Escape the ';' so GRUB treats "ds=nocloud;s=..." as one kernel arg.
sed -i 's|\(linux[[:space:]]\+/casper/vmlinuz\)|\1 autoinstall ds=nocloud\\;s=/cdrom/nocloud/|g' "$STAGE/grub.cfg"
sed -i 's|^set timeout=.*|set timeout=1|' "$STAGE/grub.cfg"

# 4. Repack, replaying the original boot records (preserves BIOS+UEFI booting).
xorriso -indev "$ISO" -outdev "$OUT" \
  -boot_image any replay \
  -overwrite on \
  -map "$STAGE/grub.cfg"               /boot/grub/grub.cfg \
  -map "$STAGE/user-data"              /nocloud/user-data \
  -map "$STAGE/meta-data"              /nocloud/meta-data \
  -map "$STAGE/tailscale-authkey"      /nocloud/tailscale-authkey \
  -map "$STAGE/mc-firstrun.service"    /nocloud/mc-firstrun.service \
  -map "$SCRIPT_DIR/install-tailscale.sh" /nocloud/install-tailscale.sh \
  -map "$SCRIPT_DIR/compute-firstrun.sh"  /nocloud/compute-firstrun.sh

echo
echo "Built: $OUT"

if [ -z "$DEVICE" ]; then
  echo "Write it to USB (double-check the target with lsblk — wrong device nukes a disk):"
  echo "  sudo dd if=$OUT of=/dev/sdX bs=4M status=progress oflag=sync"
  echo "Then boot the ThinkCentre from USB — it installs and joins the tailnet unattended."
  exit 0
fi

# --device given: flash it, but make the destructiveness impossible to miss.
echo
echo "About to OVERWRITE $DEVICE with $OUT. This erases everything on it:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS "$DEVICE"
printf 'Type the device path again to confirm (%s): ' "$DEVICE"
read -r CONFIRM
[ "$CONFIRM" = "$DEVICE" ] || { echo "Mismatch; not writing." >&2; exit 1; }

sudo dd if="$OUT" of="$DEVICE" bs=4M status=progress oflag=sync
sync
echo "Flashed $DEVICE. Boot the ThinkCentre from it — it installs and joins the tailnet unattended."
