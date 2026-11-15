# homelab — local infrastructure

Home-side provisioning for the Minecraft compute (ThinkCentre Wings node, Pi
subnet router). The cloud side stays in `linode/`.

## Layout

- `scripts/install-tailscale.sh` — shared tailnet-join. Consumed by the cloud
  host's Terraform `null_resource.tailscale_join`, the Ansible `tailscale`
  role, and both boxes' first-boot payloads.
- `scripts/pi-firstrun.sh` — dropped onto the Pi's boot partition alongside a
  `tailscale-authkey` file; enables IP forwarding, joins the tailnet as
  `tag:mc-gateway` advertising the home LAN, then shreds itself and the key.
- `scripts/stage-pi-sd.sh` — writes the `pi/` cloud-init payload + tailnet join
  files onto a flashed Ubuntu Pi SD card's boot partition.
- `scripts/compute-firstrun.sh` — the ThinkCentre's first-boot analogue, run by
  `mc-firstrun.service`; joins as `tag:mc-compute`, then shreds the key and
  self-disables.
- `scripts/build-thinkcentre-iso.sh` — remasters a stock Ubuntu ISO into a
  zero-touch ThinkCentre autoinstaller.
- `scripts/download-ubuntu-iso.sh` — fetches + SHA-verifies the ThinkCentre's
  base Ubuntu amd64 ISO to a tmp path.
- `thinkcentre/` — the ThinkCentre's NoCloud autoinstall payload (`user-data`,
  `meta-data`, `mc-firstrun.service`) baked into the ISO by the build script.
- `pi/` — the Pi's cloud-init `user-data` (hostname, `deploy` user, first-boot
  runcmd), staged onto the SD card by `stage-pi-sd.sh`.

## Bringing up the ThinkCentre

The ThinkCentre (`mc-compute`, `tag:mc-compute`) is zero-touch: a remastered
Ubuntu Server 24.04 LTS ISO installs unattended (whole-disk wipe, no prompts)
and joins the tailnet on first boot. Nothing needed on the box beyond booting
the USB. The disk is claimed unconditionally — there is no inspect-first step,
so make sure nothing on it matters.

1. Materialize the shared homelab pubkey (baked into the installer, not your
   personal GitHub identity): `czm apply`.
2. Fetch + SHA-verify the current Ubuntu Server 24.04 LTS **amd64** ISO to a
   tmp path. Prints the build command to run next:

   ```bash
   homelab/scripts/download-ubuntu-iso.sh
   ```

3. Build the zero-touch ISO (needs `xorriso`; installed by
   `scripts/initialize.sh`). Run the command the downloader printed — it sources
   the production `.env` so the compute auth key is readable, then:

   ```bash
   homelab/scripts/build-thinkcentre-iso.sh \
     --iso "$ISO" --authkey "$COMPUTE_KEY"
   # → mc-compute-autoinstall.iso (embeds a live key; git-ignored, discard after)
   ```

4. Write it to USB (double-check the target — wrong device nukes a disk).
   Either pass `--device` to the build step above to flash in one go (it shows
   an `lsblk` preview and prompts for a typed confirmation), or dd manually:

   ```bash
   # one-shot: build + flash
   homelab/scripts/build-thinkcentre-iso.sh \
     --iso "$ISO" --authkey "$COMPUTE_KEY" --device /dev/sdX
   # or, flash an already-built ISO by hand:
   sudo dd if=mc-compute-autoinstall.iso of=/dev/sdX bs=4M status=progress oflag=sync
   ```

5. Boot the ThinkCentre from USB. It wipes the disk, installs `mc-compute` /
   `deploy` (key-only SSH, no snaps), reboots, and `mc-firstrun.service` joins
   the tailnet as `tag:mc-compute` then shreds the key.
6. Verify from the Linode host: `tailscale status | grep mc-compute` and
   `tailscale ping mc-compute`.

## Bringing up the Pi

The Pi 4B (`mc-gateway`, `tag:mc-gateway`) is zero-touch after "insert SD card,
power on". Raspberry Pi Imager can't customize a "Use custom" image and its
built-in list doesn't reliably carry Ubuntu Server, so we flash the raw Ubuntu
Pi image and author cloud-init ourselves: `stage-pi-sd.sh` writes the `pi/`
`user-data` (hostname, `deploy` user + SSH key, first-boot runcmd) plus the
tailnet payload onto the FAT32 `system-boot` partition — all on the one
partition Windows/WSL can write, no ext4 access required.

1. Download **Ubuntu Server 24.04 LTS (64-bit)** for Raspberry Pi
   (`ubuntu-24.04.x-preinstalled-server-arm64+raspi.img.xz`). The current LTS is
   front-paged on `ubuntu.com/download/raspberry-pi`; older releases live under
   `https://cdimage.ubuntu.com/releases/24.04/release/`. Leave it `.xz`-compressed.
2. In Raspberry Pi Imager: **Choose OS → Use custom →** that `.img.xz`, pick the
   SD card, and write. Skip Edit Settings — it's greyed out for custom images;
   `stage-pi-sd.sh` handles that config.
3. Stage the payload. After Imager finishes, Windows shows the boot partition as
   a drive letter (e.g. `E:`); WSL reaches it at `/mnt/e` (mount with
   `sudo mount -t drvfs E: /mnt/e` if it isn't auto-mounted). Materialize the
   SSH key first with `czm apply`:

   ```bash
   cd linode/environments/production
   set -a; source .env; set +a          # backend creds for terraform output
   GATEWAY_KEY=$(terraform output -raw tailnet_gateway_auth_key)
   cd "$(git rev-parse --show-toplevel)"
   homelab/scripts/stage-pi-sd.sh --boot /mnt/e --authkey "$GATEWAY_KEY"
   ```

4. Eject the card, boot the Pi with Ethernet + power. No monitor needed. On
   first boot cloud-init creates `deploy` + sets the hostname, then
   `pi-firstrun.sh` enables IP forwarding, joins as `tag:mc-gateway` advertising
   `192.168.18.0/24`, then shreds the key and itself.
5. Verify from the Linode host:

   ```bash
   tailscale status | grep mc-gateway
   tailscale status | grep 192.168.18.0/24    # expect no '!' — auto-approved
   ssh deploy@mc-gateway 'ls /boot/firmware/tailscale-authkey' 2>&1 \
     | grep -q 'No such file'
   ```
