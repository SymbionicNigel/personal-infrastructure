# homelab — local infrastructure

Home-side provisioning for the Minecraft compute (ThinkCentre Wings node, Pi
subnet router). The cloud side stays in `linode/`.

## Layout

- `scripts/install-tailscale.sh` — shared tailnet-join. Consumed by the cloud
  host's Terraform `null_resource.tailscale_join`, the Ansible `tailscale`
  role, and the Pi's first-boot payload.
- `scripts/pi-firstrun.sh` — dropped onto the Pi's boot partition alongside a
  `tailscale-authkey` file; joins the tailnet on first boot, then shreds both
  itself and the key.

## Bringing up the ThinkCentre

The ThinkCentre (`mc-compute`, `tag:mc-compute`) uses an interactive Ubuntu
Server 24.04 LTS install for the first flash — the box's factory state is
unknown, and an autoinstall config is only worth writing once the shape is
understood.

1. Boot the existing storage first and inspect: `lsblk`, `ip -br link`, RAM,
   whether anything worth keeping (Windows licence, BitLocker keys, data)
   already lives on the disk.
2. Download Ubuntu Server 24.04 LTS amd64 from
   `https://ubuntu.com/download/server` and verify the SHA256.
3. Write the USB with Raspberry Pi Imager ("Use custom"), Rufus, or `dd`.
4. Interactive install. Settings that matter for downstream Ansible:
   - Hostname: `mc-compute`
   - User: `deploy`
   - Storage: entire disk, LVM off
   - Install OpenSSH server: **yes**
   - Import SSH identity → paste `homelab/authorized_keys` (the shared
     homelab pubkey — not your personal GitHub identity; run `czm apply`
     first to materialize it from Bitwarden)
   - Skip featured server snaps
5. Once the box is on the LAN, join it to the tailnet from your workstation:

   ```bash
   COMPUTE_KEY=$(terraform -chdir=linode/environments/production output -raw tailnet_compute_auth_key)
   scp homelab/scripts/install-tailscale.sh deploy@<lan-ip>:/tmp/
   ssh deploy@<lan-ip> sudo bash /tmp/install-tailscale.sh \
     --authkey "$COMPUTE_KEY" --advertise-tags tag:mc-compute
   ssh deploy@<lan-ip> rm /tmp/install-tailscale.sh
   ```

6. Verify from the Linode host: `tailscale status | grep mc-compute` and
   `tailscale ping mc-compute`.

## Bringing up the Pi

The Pi 4B (`mc-gateway`, `tag:mc-gateway`) is genuinely zero-touch after
"insert SD card, power on": Raspberry Pi Imager sets the hostname / SSH key /
user, and a `pi-firstrun.sh` payload on the boot partition joins the tailnet.

1. Download Ubuntu Server 24.04 LTS arm64 for Pi from
   `https://ubuntu.com/download/raspberry-pi` and verify the SHA256.
2. Flash with Raspberry Pi Imager ("Use custom" → the Ubuntu image). In
   advanced options (cog icon):
   - Hostname: `mc-gateway`
   - SSH: key-based only, paste `homelab/authorized_keys` (run `czm apply`
     first to materialize it from Bitwarden)
   - Username: `deploy` (password is a fallback; SSH stays key-only)
   - Wi-Fi: **off** — the Pi is on rack Ethernet; Wi-Fi is a footgun for a
     subnet router
3. Before ejecting the card, stage the boot payload:

   ```bash
   GATEWAY_KEY=$(terraform -chdir=linode/environments/production output -raw tailnet_gateway_auth_key)
   # boot partition (Ubuntu names it "system-boot" and mounts it as
   # /boot/firmware on the running Pi):
   BOOT=/media/$USER/system-boot
   ROOT=/media/$USER/writable
   sudo install -m 0755 homelab/scripts/install-tailscale.sh \
     "$ROOT/usr/local/sbin/install-tailscale.sh"
   sudo install -m 0755 homelab/scripts/pi-firstrun.sh \
     "$BOOT/pi-firstrun.sh"
   printf '%s' "$GATEWAY_KEY" | sudo tee "$BOOT/tailscale-authkey" >/dev/null
   sudo chmod 0600 "$BOOT/tailscale-authkey"
   # Append the runcmd entry to cloud-init's user-data:
   sudo tee -a "$BOOT/user-data" <<'EOF'
   runcmd:
     - /boot/firmware/pi-firstrun.sh
   EOF
   ```

4. Boot the Pi with Ethernet + power. No monitor needed.
5. Verify from the Linode host:

   ```bash
   tailscale status | grep mc-gateway
   tailscale status | grep 192.168.1.0/24     # expect no '!' — auto-approved
   ssh deploy@mc-gateway.<tailnet>.ts.net 'ls /boot/firmware/tailscale-authkey' 2>&1 \
     | grep -q 'No such file'
   ```
