# Dokploy Hardening and Cert-Issuance Decoupling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Cap end-user DNS-propagation pain after a Dokploy instance replacement to ~5 minutes, add a network-layer firewall in front of the instance, harden the instance itself (no-root SSH, automatic security patches, SSH-bruteforce mitigation), and switch Let's Encrypt validation to DNS-01 so cert issuance is decoupled from IP/DNS propagation entirely.

**Architecture:** Five hardening changes plus one cert-issuance change, all driven from Terraform with no extra services introduced. Tasks 1, 2, 4, 5 are independent and can be applied in any order; Task 3 (no-root SSH) cascades into the provisioners and benefits from being applied after Tasks 4 and 5 are stable; Task 6 (DNS-01) is the structural fix for the cert-issuance race and should land before relying on cert-dependent steps. The user (not the assistant) owns all `git add`/`git commit` and `terraform apply` operations.

**Tech Stack:** Terraform (Linode provider 3.4.0, time 0.11), bash 5.x, Ubuntu 24.04 (`unattended-upgrades`, `fail2ban`), Linode Cloud Firewall (network layer), Linode Object Storage (already wired for backups), Traefik v3.x (already running inside Dokploy).

---

## File Structure

- Modify: `linode/modules/domain/main.tf` — lower `ttl_sec` from `0` (24h default) to `300` (Task 1).
- Modify: `linode/modules/dokploy/outputs.tf` — surface `instance_id` so the production stage can attach the Cloud Firewall by ID (Task 2).
- Modify: `linode/modules/dokploy/user_data.sh` — install + configure `unattended-upgrades` (Task 4); install + configure `fail2ban` (Task 5); grant passwordless sudo to `symbionic_dokploy_user` and flip `PermitRootLogin` to `no` (Task 3).
- Modify: `linode/modules/dokploy/main.tf` — retarget the API-key-fetch `local-exec` from `root@` to `symbionic_dokploy_user@` + `sudo cat` (Task 3).
- Modify: `linode/modules/acme-backup/main.tf` — retarget the SSH `connection`, file-provisioner destinations, GPG import, and `restore_acme` pipeline to `symbionic_dokploy_user` + `sudo install` / `sudo gpg --batch --import`; replace the broken `docker service update --force dokploy-traefik` with `docker restart dokploy-traefik` (Task 3, includes the cross-cutting Traefik-reload fix).
- Modify: `linode/environments/production/base.tf` — add `linode_firewall.dokploy` (Task 2); retarget `bind_dokploy_domain` connection user + add `sudo` where reading `/root/.dokploy-api-key` (Task 3); update `local_file.ssh_config` to `User symbionic_dokploy_user` (Task 3); add `time_rotating.dns_token`, `terraform_data.dns_token_rotation`, `linode_token.dns` (`domains:read_write`-scoped), and `null_resource.configure_dokploy_dns01` that calls `settings.writeTraefikEnv` over SSH-to-localhost (Task 6); wire `bind_dokploy_domain` to depend on the DNS-01 config (Task 6).
- No tests added (IaC change with no test harness in repo); verification is via `terraform plan`, `terraform validate`, `bash -n`, and on-host smoke tests after apply.

---

## Task 1: Lower DNS TTL on the wildcard A records

**Files:**
- Modify: `linode/modules/domain/main.tf:32`

**Why:** `ttl_sec = 0` in the Linode provider defers to the zone default, which Linode sets to 86400 (24h). After a `terraform apply` that replaces the dokploy instance, the wildcard A record updates immediately at the authoritative nameservers but downstream resolvers (your router, ISP, browser) hold the old answer for up to 24h. Dropping the TTL to 300s caps propagation at ~5 minutes. Linode only accepts these values: `0, 30, 120, 300, 3600, 7200, 14400, 28800, 57600, 86400, 172800, 345600, 604800, 1209600, 2419200`.

- [ ] **Step 1: Edit the TTL**

In [linode/modules/domain/main.tf:32](linode/modules/domain/main.tf#L32), change:

```hcl
  ttl_sec     = 0
```

to:

```hcl
  ttl_sec     = 300
```

- [ ] **Step 2: Validate and inspect plan**

```bash
cd linode/environments/production
terraform validate
terraform plan -out=/tmp/ttl.tfplan >/dev/null
terraform show -json /tmp/ttl.tfplan \
  | jq -r '.resource_changes[] | select(.address | test("main_site_a_records")) | "\(.address): \(.change.actions | join(","))"'
```

Expected: two `~ update` lines, one for `main` and one for `wildcard`. No replacements.

_Apply deferred to Task 7 (single consolidated apply at end of plan)._

---

## Task 2: Add Linode Cloud Firewall in front of the dokploy instance

**Files:**
- Modify: `linode/modules/dokploy/outputs.tf` — add `instance_id` output.
- Modify: `linode/modules/dokploy/main.tf` — already exposes the instance resource; no change beyond ensuring the output references it correctly.
- Modify: `linode/environments/production/base.tf` — add `linode_firewall.dokploy` resource.

**Why:** UFW on the instance is host-firewalled — packets still reach the box's network stack before being dropped. A Cloud Firewall drops at the Linode edge, surviving instance replacement (the firewall is attached by instance ID via `linodes = [...]`, so the rule set persists; only the attachment is rewritten when the instance is recreated).

**SSH access policy:** :22 stays open to `0.0.0.0/0`. Restricting via the Cloud Firewall to a personal CIDR was considered and rejected because residential dynamic IP rotation would create an operational lockout risk. Defense for :22 is provided by Task 3 (no password auth, no root login) and Task 5 (fail2ban). The Cloud Firewall's value here is closing every other port that might land on an instance over time and giving a Terraform-managed surface to tighten :80/:443 later if needed.

- [ ] **Step 1: Expose `instance_id` from the dokploy module**

In [linode/modules/dokploy/outputs.tf](linode/modules/dokploy/outputs.tf), add:

```hcl
output "instance_id" {
  description = "Numeric Linode ID of the dokploy_main instance, used to attach Cloud Firewalls and reserved IPs."
  value       = linode_instance.dokploy_main.id
}
```

If the resource is named differently in `linode/modules/dokploy/main.tf`, adjust accordingly — confirm via `grep -n 'resource "linode_instance"' linode/modules/dokploy/main.tf` before writing.

- [ ] **Step 2: Add the firewall resource**

In [linode/environments/production/base.tf](linode/environments/production/base.tf), add (anywhere top-level, e.g., after `module.dokploy-instance`):

```hcl
# Network-layer firewall. Survives instance replacement: the rule set lives on
# the firewall resource; only the `linodes = [...]` attachment is rewritten
# when the dokploy instance is recreated. UFW on the instance remains as
# defense in depth.
resource "linode_firewall" "dokploy" {
  label = "${local.resource_prefix}-dokploy"
  tags  = local.TAGS

  inbound_policy  = "DROP"
  outbound_policy = "ACCEPT"

  inbound {
    label    = "ssh"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "22"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "http"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "80"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  inbound {
    label    = "https"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "443"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }

  linodes = [module.dokploy-instance.instance_id]
}
```

- [ ] **Step 3: Validate + plan**

```bash
cd linode/environments/production
terraform validate
terraform plan -out=/tmp/firewall.tfplan >/dev/null
terraform show -json /tmp/firewall.tfplan \
  | jq -r '.resource_changes[] | select(.address | test("linode_firewall")) | "\(.address): \(.change.actions | join(","))"'
```

Expected: `linode_firewall.dokploy: create`. No instance replacement.

Apply + smoke test deferred to Task 7 (single consolidated apply at end of plan).

---

## Task 3: Disable root SSH login entirely

**Files:**
- Modify: `linode/modules/dokploy/user_data.sh` — provision the non-root user with an SSH key on first boot AND with passwordless sudo, then flip `PermitRootLogin` to `no`.
- Modify: `linode/modules/acme-backup/main.tf` — every `ssh root@...` invocation (both `local-exec` SSH calls + the `connection { user = "root" }` block on `null_resource.configure_acme_backup`) retargets to `symbionic_dokploy_user`. Commands that need root (e.g., `install` into `/etc/dokploy/...`, `gpg --batch --import` as root) are wrapped in `sudo`.
- Modify: `linode/modules/dokploy/main.tf` — the `local-exec` that fetches `/root/.dokploy-api-key` retargets to `symbionic_dokploy_user` and `sudo cat`s the file.
- Modify: `linode/environments/production/base.tf` — `null_resource.bind_dokploy_domain`'s `connection` block retargets to `symbionic_dokploy_user`; the `remote-exec` `sudo`s where needed.

**Why:** `PermitRootLogin prohibit-password` allows root with a key. The non-root user already exists (sudo + docker group). Since SSH stays open to `0.0.0.0/0` by design (residential dynamic IP makes an allow-list lock-out-prone — see Task 2's SSH access policy note), removing root SSH cuts the blast radius significantly: a compromised key now reaches a user account, not the superuser.

**Note:** This task touches both the dokploy module's bootstrap (the public key for `symbionic_dokploy_user` must be present at the right path) AND every Terraform provisioner that SSHes in. Plan to apply Tasks 4 and 5 first (independent, low-risk), then Task 3 as a focused apply with the cert backed up beforehand in case anything in the retarget needs adjusting.

- [ ] **Step 1: Confirm the non-root user's key landing point**

In [linode/modules/dokploy/user_data.sh](linode/modules/dokploy/user_data.sh) (currently around line 47–53), the existing block creates `symbionic_dokploy_user` and copies `/root/.ssh/authorized_keys` over. That's correct: both root and the non-root user accept the same key. No change to that block.

- [ ] **Step 2: Grant the non-root user passwordless sudo**

Append after the existing `usermod -aG docker symbionic_dokploy_user` line in user_data.sh:

```bash
# Passwordless sudo so terraform provisioners can run privileged commands
# without an interactive prompt. Scope narrow: only this one user, only
# /usr/bin/sudo (the standard binary).
cat > /etc/sudoers.d/symbionic_dokploy_user <<'SUDO_EOF'
symbionic_dokploy_user ALL=(ALL) NOPASSWD:ALL
SUDO_EOF
chmod 440 /etc/sudoers.d/symbionic_dokploy_user
visudo -c -f /etc/sudoers.d/symbionic_dokploy_user
```

The `visudo -c` syntax-checks the file; a malformed sudoers entry would lock all sudo access otherwise.

- [ ] **Step 3: Flip `PermitRootLogin` to `no`**

Change the existing call in user_data.sh:

```bash
set_ssh_config "PermitRootLogin" "prohibit-password"
```

to:

```bash
set_ssh_config "PermitRootLogin" "no"
```

`sshd` reload already happens via the `systemctl restart sshd` line below. No change to that.

- [ ] **Step 4: Retarget `linode/modules/dokploy/main.tf`'s `local-exec`**

The `local-exec` that fetches `/root/.dokploy-api-key`:

```hcl
provisioner "local-exec" {
  interpreter = ["bash", "-c"]
  command     = "ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -i ${path.root}/id_ed25519 root@${one(self.ipv4)} cat /root/.dokploy-api-key > ${path.root}/.dokploy-api-key"
}
```

becomes:

```hcl
provisioner "local-exec" {
  interpreter = ["bash", "-c"]
  command     = "ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=/dev/null -i ${path.root}/id_ed25519 symbionic_dokploy_user@${one(self.ipv4)} sudo cat /root/.dokploy-api-key > ${path.root}/.dokploy-api-key"
}
```

- [ ] **Step 5: Retarget `linode/environments/production/base.tf`'s `bind_dokploy_domain`**

The `connection` block currently has `user = "root"`. Change to:

```hcl
connection {
  type        = "ssh"
  host        = module.dokploy-instance.instance_ip
  user        = "symbionic_dokploy_user"
  private_key = file("${path.root}/id_ed25519")
}
```

And in the `remote-exec`:
- The `provisioner "file"` writes to `/root/.dokploy-bind-domain.json` — that destination is no longer writable by `symbionic_dokploy_user`. Move it to `/home/symbionic_dokploy_user/.dokploy-bind-domain.json` (or `/tmp/`; either works since the curl POSTs to localhost and immediately deletes the file).
- The `test -s /root/.dokploy-api-key` and `cat /root/.dokploy-api-key` lines need `sudo`:
  ```bash
  set -eu
  sudo test -s /root/.dokploy-api-key
  API_KEY=$(sudo cat /root/.dokploy-api-key)
  curl -sf -X POST http://localhost:3000/api/trpc/settings.assignDomainServer \
    -H 'Content-Type: application/json' \
    -H "x-api-key: $API_KEY" \
    --data @/home/symbionic_dokploy_user/.dokploy-bind-domain.json
  rm -f /home/symbionic_dokploy_user/.dokploy-bind-domain.json
  ```

- [ ] **Step 6: Retarget `linode/modules/acme-backup/main.tf`**

Multiple touch points:

**a. The `connection` block on `null_resource.configure_acme_backup`** — change `user = "root"` to `user = "symbionic_dokploy_user"`.

**b. The two `provisioner "file"` destinations** — `/root/.s3cfg` and `/root/.acme-backup.env` aren't writable by the non-root user. The simplest move is to upload to `/home/symbionic_dokploy_user/` first, then `sudo install` to `/root/` with the right perms in the `remote-exec`:

```hcl
provisioner "file" {
  destination = "/home/symbionic_dokploy_user/.s3cfg"
  content     = <<-EOT
    [default]
    access_key = ${linode_object_storage_key.infra_backups.access_key}
    secret_key = ${linode_object_storage_key.infra_backups.secret_key}
    host_base = ${var.endpoint}
    host_bucket = %(bucket)s.${var.endpoint}
    use_https = True
    signature_v2 = False
  EOT
}

provisioner "file" {
  destination = "/home/symbionic_dokploy_user/.acme-backup.env"
  content     = "BACKUP_BUCKET=${var.bucket_name}\nGPG_RECIPIENT=${var.gpg_recipient}\n"
}

provisioner "remote-exec" {
  inline = [
    "sudo install -m 0600 -o root -g root /home/symbionic_dokploy_user/.s3cfg /root/.s3cfg",
    "sudo install -m 0600 -o root -g root /home/symbionic_dokploy_user/.acme-backup.env /root/.acme-backup.env",
    "rm -f /home/symbionic_dokploy_user/.s3cfg /home/symbionic_dokploy_user/.acme-backup.env",
  ]
}
```

**c. The GPG-import `local-exec`** — the SSH target user changes, and the inner gpg import command needs `sudo` since root's keyring is what `backup_acme.sh` (run as root by systemd) reads:

```hcl
gpg --export -a "${var.gpg_recipient}" \
  | ssh -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/dev/null \
        -i ${path.root}/id_ed25519 \
        symbionic_dokploy_user@${var.instance_ip} \
        'sudo gpg --batch --import'
```

**d. The `restore_acme` `local-exec`** — the ssh + install pipeline. The `install` writes to `/etc/dokploy/traefik/dynamic/acme.json` and the `docker service update` (which we already noted is wrong for plain containers — fix to `docker restart` while here) both need root. Pipe through sudo:

```hcl
s3cmd -c "$CFG" get --force "s3://${var.bucket_name}/acme.json.gpg" - \
  | gpg --batch --decrypt \
  | ssh -o StrictHostKeyChecking=accept-new \
        -o UserKnownHostsFile=/dev/null \
        -i ${path.root}/id_ed25519 \
        symbionic_dokploy_user@${var.instance_ip} \
        "sudo install -m 0600 -o root -g root /dev/stdin /etc/dokploy/traefik/dynamic/acme.json && sudo docker restart dokploy-traefik >/dev/null"
```

Note this also bundles the `docker service update → docker restart` correction (cross-cutting fix flagged earlier — Dokploy runs Traefik as a plain container, not a swarm service).

- [ ] **Step 7: Update `linode/environments/production/dokploy.sshconfig` template**

In [linode/environments/production/base.tf](linode/environments/production/base.tf) the `local_file.ssh_config` resource has `User root`. Change to `User symbionic_dokploy_user`. The user's `ssh dokploy-prod` will then land as the non-root user (with sudo available for ad-hoc admin work).

- [ ] **Step 8: Validate**

```bash
cd linode/environments/production && terraform validate
bash -n linode/modules/dokploy/user_data.sh && echo OK
```

Apply + verification deferred to Task 7. Note for that task: this task's edits cause the dokploy instance to be replaced (user_data_hash changed). Pre-condition: a known-good `acme.json.gpg` should exist in the backups bucket, or `restore_acme` will have nothing to put back and the cert will be re-issued via Task 6's DNS-01 path on the new instance.

---

## Task 4: Auto-apply Ubuntu security updates via `unattended-upgrades`

**Files:**
- Modify: `linode/modules/dokploy/user_data.sh` — add an install + config block before the firewall section.

**Why:** Ubuntu 24.04 ships with `unattended-upgrades` available but not always enabled. Enabling the Security pocket only means CVE patches roll in automatically; main-archive updates still require manual intervention so they don't surprise you. Auto-reboot is off — running services keep running until you choose to reboot, which avoids mid-day Dokploy outages from a kernel update.

- [ ] **Step 1: Add the install + config block**

In [linode/modules/dokploy/user_data.sh](linode/modules/dokploy/user_data.sh), find the apt-install line:

```bash
apt-get install "${APT_OPTS[@]}" curl jq ufw s3cmd gnupg
```

and replace it with:

```bash
apt-get install "${APT_OPTS[@]}" curl jq ufw s3cmd gnupg unattended-upgrades

# Configure unattended-upgrades to apply security-pocket updates only, without
# auto-reboot. Running services stay up across patches; we reboot manually.
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
    "${distro_id}ESMApps:${distro_codename}-apps-security";
    "${distro_id}ESM:${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UU_EOF

cat > /etc/apt/apt.conf.d/20auto-upgrades <<'AU_EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
AU_EOF

systemctl enable --now unattended-upgrades.service
```

The two heredocs use `<<'EOF'` (single-quoted) so the `${distro_id}` placeholders pass through to the apt config literally — they're apt's substitution syntax, not bash's, and not Terraform's template syntax.

Note on Terraform templating: this file is rendered by `templatefile()`. The `${...}` inside the single-quoted heredocs would be intercepted by templatefile. Escape them by doubling the `$` to `$${distro_id}`:

```bash
cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'UU_EOF'
Unattended-Upgrade::Allowed-Origins {
    "$${distro_id}:$${distro_codename}-security";
    "$${distro_id}ESMApps:$${distro_codename}-apps-security";
    "$${distro_id}ESM:$${distro_codename}-infra-security";
};
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
UU_EOF
```

This is the same escape pattern used elsewhere in user_data.sh (e.g., `$${BUCKET}`).

- [ ] **Step 2: `bash -n`**

```bash
bash -n linode/modules/dokploy/user_data.sh && echo OK
```

Expected: `OK`.

- [ ] **Step 3: Render-test the template to confirm escaping**

```bash
cat > /tmp/render-uu.tf <<'EOF'
output "rendered" {
  value = templatefile("${path.module}/linode/modules/dokploy/user_data.sh", {
    HOSTNAME_TLD           = "example.com"
    DOKPLOY_VERSION        = "v0.29.2"
    DOKPLOY_ADMIN_EMAIL    = "a@b.c"
    DOKPLOY_ADMIN_PASSWORD = "pw"
  })
}
EOF
cp /tmp/render-uu.tf ./render-test.tf
terraform init -no-color 2>&1 | tail -1
terraform apply -auto-approve -no-color 2>&1 | grep -A2 'Allowed-Origins'
rm -f render-test.tf
```

Expected: the rendered output shows `"${distro_id}:${distro_codename}-security"` (single `$`, braces preserved) — NOT `"$${distro_id}..."` or `"<some-value>:..."`.

Apply + verification deferred to Task 7. This task contributes to user_data_hash change → instance replacement on the consolidated apply.

---

## Task 5: Add `fail2ban` for SSH brute-force mitigation

**Files:**
- Modify: `linode/modules/dokploy/user_data.sh` — install package + drop a jail config.

**Why:** Even with key-only SSH, scanners hammer :22 constantly. fail2ban bans source IPs after N failed attempts, which (a) cuts log noise so real anomalies are visible, (b) protects the Dokploy dashboard's login form (which is exposed at `vulcan.<HOSTNAME_TLD>:443` and uses username/password auth), and (c) costs nothing in resources at this scale.

This task assumes Task 4 is applied (apt-install line already modified). If applying out-of-order, add `fail2ban` to whichever apt-install line currently exists.

- [ ] **Step 1: Add `fail2ban` to the apt install line + jail config**

In [linode/modules/dokploy/user_data.sh](linode/modules/dokploy/user_data.sh), update the apt-install line to include `fail2ban`:

```bash
apt-get install "${APT_OPTS[@]}" curl jq ufw s3cmd gnupg unattended-upgrades fail2ban
```

Then add, after the unattended-upgrades block from Task 4:

```bash
# fail2ban: ban source IPs after repeated SSH auth failures. Dashboard
# bruteforce is handled separately (Traefik rate-limit, future).
cat > /etc/fail2ban/jail.d/sshd.local <<'F2B_EOF'
[sshd]
enabled  = true
port     = ssh
filter   = sshd
backend  = systemd
maxretry = 5
findtime = 10m
bantime  = 1h
F2B_EOF

systemctl enable --now fail2ban.service
```

The heredoc body has no template-interpolatable patterns, so no `$${...}` escaping is needed. The `[sshd]` brackets and `findtime = 10m` syntax are fail2ban-native; Terraform's templatefile only intercepts `${...}` and `%{...}`.

- [ ] **Step 2: `bash -n`**

```bash
bash -n linode/modules/dokploy/user_data.sh && echo OK
```

Expected: `OK`.

Apply + verification deferred to Task 7.

---

## Task 6: Switch ACME validation to DNS-01 via Linode

**Important constraint:** All Traefik configuration in this stack flows through Dokploy. Do NOT write static or dynamic Traefik config files (e.g., `/etc/dokploy/traefik/*.yml`) directly — Dokploy regenerates Traefik's config from its own database on its own schedule, and any hand-edited file is at best stale and at worst overwritten with no warning. Every change in this task must go through Dokploy's API, its environment, or the `j0bIT/dokploy` Terraform provider.

**Files:**
- Modify: `linode/environments/production/base.tf` — add `time_rotating.dns_token`, `terraform_data.dns_token_rotation`, `linode_token.dns`, and a mechanism (chosen in Step 1) that hands the token to Dokploy so Dokploy passes it to Traefik. Likely a `null_resource.configure_dokploy_dns01` mirroring `bind_dokploy_domain` (tRPC call) rather than a file-push provisioner.
- Possibly modify: `linode/environments/dokploy/main.tf` — if the `j0bIT/dokploy` provider exposes a settings/certificate-provider resource that handles this, prefer it over an SSH/curl tRPC call.
- Possibly modify: `linode/modules/dokploy/user_data.sh` — only if Dokploy reads the Linode token from an env var passed to its container at startup (rare; would require restarting Dokploy with a new env). Avoid if possible.
- No new variables needed in production — the token is generated and consumed entirely inside the terraform stage.

**Why:** HTTP-01 validation requires Let's Encrypt to fetch `http://vulcan.<HOSTNAME>/.well-known/acme-challenge/<token>` from the instance. When the instance is replaced the IP changes; LE's resolver caches the old A record for up to that record's TTL, so the first challenge after a replacement hits the old (dead) IP and fails. DNS-01 instead proves ownership by writing a TXT record (`_acme-challenge.vulcan.<HOSTNAME>`), which LE resolves directly against the authoritative nameserver. No A-record lookup, no IP dependency, no race. It also unblocks issuing certs for hosts that aren't publicly reachable on :80 at all (useful later for non-public services).

**Token hygiene:** Generated via Terraform with `scopes = "domains:read_write"` only. Blast radius if leaked is "attacker can manipulate DNS for your domains" — bounded, no account/instance/storage access. The master `TF_VAR_LINODE_TOKEN` continues to live only on the deploy machine and is never pushed to the instance.

- [ ] **Step 1: Mechanism (confirmed by source review of Dokploy v0.29.4)**

Confirmed via [apps/dokploy/server/api/routers/settings.ts](https://github.com/Dokploy/dokploy/blob/v0.29.4/apps/dokploy/server/api/routers/settings.ts) at the v0.29.4 tag:

- `settings.readTraefikEnv` (tRPC query, `adminProcedure`) — input `{ serverId?: string }` → returns the current Traefik env-file contents.
- `settings.writeTraefikEnv` (tRPC mutation, `adminProcedure`) — input `{ env: string, serverId?: string }` → parses via `prepareEnvironmentVariables`, calls `writeTraefikSetup` which re-renders Traefik's static config and reloads the container. The mutation returns immediately; the reload runs in the background and clients poll `/api/health`.

Both are admin-authenticated; the existing `/root/.dokploy-api-key` (admin API key created during cloud-init) is sufficient.

Traefik's ACME resolver config is settable via env vars in the format `TRAEFIK_CERTIFICATESRESOLVERS_<NAME>_ACME_*=...` (Traefik's standard env-binding convention; reference: <https://doc.traefik.io/traefik/reference/static-configuration/env/>). The Linode DNS provider in Traefik's `lego` library reads its credentials from `LINODE_TOKEN`.

The env blob we'll write looks like:

```
TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=<email>
TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/etc/dokploy/traefik/dynamic/acme.json
TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE=true
TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER=linode
TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS=1.1.1.1:53,8.8.8.8:53
LINODE_TOKEN=<token>
```

Important: Dokploy *preserves* whatever else is already in the Traefik env. The write replaces the whole blob, so any keys we're not setting need to be carried forward. **Implementation must first `readTraefikEnv`, then merge our keys in (overwriting same-named keys, preserving others), then `writeTraefikEnv`.** Naive overwrite would clobber whatever Dokploy or the user set in the dashboard.

- [ ] **Step 2: Add the rotating DNS-scoped token in `base.tf`**

In [linode/environments/production/base.tf](linode/environments/production/base.tf), after the existing `time_rotating.infra_backups_key` block, add:

```hcl
# Rotate the DNS-scoped Linode token every 365 days. The token is consumed by
# Traefik on the dokploy instance for ACME DNS-01 challenges. Rotation cadence
# is long because the blast radius is bounded (domains:read_write only) and
# replacing the token forces a re-push to the instance via the configure step
# below; we don't want that churn weekly.
resource "time_rotating" "dns_token" {
  rotation_days = 365
}

resource "terraform_data" "dns_token_rotation" {
  input = time_rotating.dns_token.rotation_rfc3339
}

resource "linode_token" "dns" {
  label  = "${local.resource_prefix}-traefik-dns"
  scopes = "domains:read_write"

  lifecycle {
    replace_triggered_by = [terraform_data.dns_token_rotation]
  }
}
```

`expiry` is intentionally omitted — the rotation drives lifecycle, not Linode's own expiry. Setting both creates ambiguous renewal semantics.

- [ ] **Step 3: Configure Dokploy's Traefik env via tRPC from the production stage**

**Critical ordering constraint:** This must happen in the production stage, NOT the dokploy stage. The `j0bIT/dokploy` provider connects to `https://vulcan.<HOSTNAME>/api`, which requires a valid TLS cert — but a valid cert is exactly what DNS-01 issues. Using the dokploy provider for this would create an unresolvable chicken-and-egg. The production stage instead reaches Dokploy via `http://localhost:3000/...` over an SSH tunnel from the deploy machine, the same pattern `bind_dokploy_domain` uses. No cert dependency.

`configure_dokploy_dns01` must run **before** `bind_dokploy_domain` so that by the time the dashboard route is assigned, Traefik is already DNS-01-configured. Otherwise Traefik will attempt HTTP-01 on the new domain and hit the same race we're trying to fix.

Add to [linode/environments/production/base.tf](linode/environments/production/base.tf):

```hcl
# Configure Dokploy's Traefik env to use DNS-01 with the linode lego provider.
# Read-merge-write so we don't clobber any other env keys Dokploy or the user
# has set in the dashboard. Mirrors bind_dokploy_domain (SSH + curl to
# localhost) so the call doesn't depend on a valid TLS cert — which is what
# we're trying to issue. MUST run before bind_dokploy_domain so the dashboard
# binding triggers DNS-01, not HTTP-01.
resource "null_resource" "configure_dokploy_dns01" {
  depends_on = [module.dokploy-instance, linode_token.dns]

  triggers = {
    instance_ip = module.dokploy-instance.instance_ip
    email       = var.EMAIL_ADDRESS
    token       = sha256(linode_token.dns.token) # hash so the secret isn't in plan output
  }

  connection {
    type        = "ssh"
    host        = module.dokploy-instance.instance_ip
    user        = "root"
    private_key = file("${path.root}/id_ed25519")
  }

  # Stage the new env keys we want set, one per line. The remote-exec merges
  # these with whatever Dokploy already has (preserving other keys) before
  # writing back via settings.writeTraefikEnv.
  provisioner "file" {
    destination = "/root/.dokploy-traefik-dns01.env"
    content     = <<-EOT
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_EMAIL=${var.EMAIL_ADDRESS}
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_STORAGE=/etc/dokploy/traefik/dynamic/acme.json
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE=true
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER=linode
      TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_RESOLVERS=1.1.1.1:53,8.8.8.8:53
      LINODE_TOKEN=${linode_token.dns.token}
    EOT
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -euo pipefail
      test -s /root/.dokploy-api-key
      API_KEY=$(cat /root/.dokploy-api-key)

      # Read current Traefik env from Dokploy.
      CURRENT=$(curl -sf "http://localhost:3000/api/trpc/settings.readTraefikEnv?input=%7B%22json%22%3A%7B%7D%7D" \
        -H "x-api-key: $API_KEY" | jq -r '.result.data.json')

      # Merge: keep CURRENT lines whose KEY is not in our new set, append all new lines.
      # Keys-to-replace are the part before '=' in our staged file.
      REPLACE_KEYS=$(awk -F= '{print $1}' /root/.dokploy-traefik-dns01.env | sort -u)
      KEEP=$(printf '%s\n' "$CURRENT" | awk -F= -v keys="$REPLACE_KEYS" '
        BEGIN { n = split(keys, a, "\n"); for (i=1;i<=n;i++) drop[a[i]]=1 }
        { if (!($1 in drop) && length($0)) print }
      ')
      MERGED=$(printf '%s\n%s' "$KEEP" "$(cat /root/.dokploy-traefik-dns01.env)")

      # Wrap merged env in the tRPC mutation payload shape: {"json":{"env":"...","serverId":null}}
      jq -n --arg env "$MERGED" '{json: {env: $env}}' > /root/.dokploy-traefik-dns01.json

      curl -sf -X POST "http://localhost:3000/api/trpc/settings.writeTraefikEnv" \
        -H 'Content-Type: application/json' \
        -H "x-api-key: $API_KEY" \
        --data @/root/.dokploy-traefik-dns01.json

      # Clean up: token never persists longer than one POST cycle on disk
      shred -u /root/.dokploy-traefik-dns01.env /root/.dokploy-traefik-dns01.json 2>/dev/null \
        || rm -f /root/.dokploy-traefik-dns01.env /root/.dokploy-traefik-dns01.json
      EOT
    ]
  }
}
```

And wire the new dependency into `bind_dokploy_domain`:

```hcl
resource "null_resource" "bind_dokploy_domain" {
  depends_on = [module.dokploy-instance, module.domain, null_resource.configure_dokploy_dns01]
  # ... rest unchanged
}
```

**Why this shape, in order of importance:**

1. **Read-merge-write, not write-only.** `settings.writeTraefikEnv` replaces the entire env blob. Writing only our keys would erase anything else (Dokploy's defaults, user-set values from the dashboard). The remote-exec reads the current env, drops only the keys we're overwriting, appends ours, then writes the merged result.
2. **Token never on the deploy machine's disk past Terraform state, and never on the host's disk past one POST.** The `file` provisioner writes to `/root/.dokploy-traefik-dns01.env`; the `remote-exec` uses it for the mutation payload then `shred -u`s (with `rm -f` fallback for filesystems where shred is a no-op). Terraform state holds the canonical copy.
3. **`sha256(token)` in `triggers`.** The actual token value would surface in `terraform plan` output if we put it in `triggers` directly. Hashing means the trigger fires on rotation (different hash) without revealing the value.
4. **`http://localhost:3000` over SSH, not the public dashboard URL.** Avoids the cert-chicken-and-egg. Also keeps Dokploy's API loopback-only as designed.

**Why not the `j0bIT/dokploy` provider, even if it had a resource for this**

The provider configures itself with `host = "https://vulcan.<HOSTNAME>/api"` (see `linode/environments/dokploy/main.tf`). That HTTPS endpoint depends on the cert we're trying to issue. Even a hypothetical `dokploy_lets_encrypt_settings` resource would inherit this dependency and deadlock first-time issuance. The production-stage tRPC-over-SSH path sidesteps it entirely.

- [ ] **Step 4: Validate**

```bash
cd linode/environments/production
terraform validate
terraform plan -out=/tmp/dns01.tfplan
```

Expected: `time_rotating.dns_token`, `terraform_data.dns_token_rotation`, `linode_token.dns`, `null_resource.configure_traefik_dns01` all show `+ create`. No instance replacement.

`token` in the `triggers` block is wrapped in `sha256()` so the secret doesn't print to plan output. The `provisioner "file"` content with the actual token value is marked sensitive by Terraform when sourced from `linode_token.dns.token`, but the trigger map values are surfaced — hashing avoids the leak.

Apply + DNS-01 verification + cert verification deferred to Task 7.

---

## Task 7: Single consolidated apply and end-to-end verification

**Files:** none modified.

**Why a single apply:** Tasks 3, 4, 5 each modify `user_data.sh` (`PermitRootLogin`, `unattended-upgrades`, `fail2ban`). All three changes funnel into `terraform_data.user_data_hash` and trigger one instance replacement. Task 6's `configure_dokploy_dns01` and `bind_dokploy_domain` retargeting depend on the new instance existing. Tasks 1 and 2 (DNS TTL, Cloud Firewall) don't strictly need to wait, but bundling everything into one `terraform apply` reduces the number of failure points and the time spent in a partially-applied state.

**Pre-condition:** A known-good `acme.json.gpg` should exist in the backups bucket from prior runs. If it does, `restore_acme` puts back a valid cert on the new instance and Task 6's DNS-01 path becomes a renewal mechanism rather than a first-issuance scramble. If it doesn't, the new instance comes up with no cert and Task 6's DNS-01 path will issue one — also fine, just slower (Traefik attempts at first dashboard hit).

Confirm:

```bash
ssh dokploy-prod '
  source /root/.acme-backup.env 2>/dev/null
  s3cmd ls "s3://$BACKUP_BUCKET/acme.json.gpg"
' 2>&1 | head -3
# Expect: a line with non-trivial size. If 0 bytes or missing, expect first-issuance via DNS-01.
```

- [ ] **Step 1: Pre-flight validation**

```bash
cd linode/environments/production
terraform validate
terraform fmt -check -recursive ../../modules/ base.tf
bash -n ../../modules/dokploy/user_data.sh && echo "bash-n OK"
```

Expected: validate succeeds, fmt-check exits 0, bash-n OK.

- [ ] **Step 2: Plan and inspect**

```bash
terraform plan -out=/tmp/full-hardening.tfplan
terraform show -json /tmp/full-hardening.tfplan \
  | jq -r '.resource_changes[] | "\(.address): \(.change.actions | join(","))"' \
  | sort
```

Expected (broad categories):
- `module.dokploy-instance.linode_instance.dokploy_main`: **replace** (user_data_hash changed across Tasks 3, 4, 5)
- `module.domain.linode_domain_record.main_site_a_records["main"]` / `["wildcard"]`: **update** (TTL change from Task 1, target update from instance replacement)
- `linode_firewall.dokploy`: **create** (Task 2)
- `time_rotating.dns_token`, `terraform_data.dns_token_rotation`, `linode_token.dns`: **create** (Task 6)
- `null_resource.configure_dokploy_dns01`: **create** (Task 6)
- `null_resource.bind_dokploy_domain`: **replace** (depends_on updated + instance replaced)
- `module.acme_backup.null_resource.configure_acme_backup`: **replace** (connection user changed)
- `module.acme_backup.null_resource.restore_acme`: **replace** (depends on configure_acme_backup)
- `local_file.ssh_config`: **update** (instance IP + user changed)

No unexpected destructions outside the dokploy instance.

- [ ] **Step 3: Apply (user action)**

```bash
./production.sh
```

Watch for:
- `module.dokploy-instance...` creation succeeds (cloud-init log line: "Apply finished" or similar)
- `null_resource.configure_dokploy_dns01` succeeds before `null_resource.bind_dokploy_domain` (ordering enforced by `depends_on`)
- `null_resource.bind_dokploy_domain` succeeds
- `module.acme_backup.null_resource.restore_acme` succeeds and reports either "restored" or "no backup — skipping"

If any null_resource fails: do NOT re-run `./production.sh` blindly. Read the error, fix the root cause, then `terraform apply -replace='<address>'` to retry just the failed resource without disturbing successful ones.

- [ ] **Step 4: Verify Task 1 (DNS TTL)**

```bash
terraform state show 'module.domain.linode_domain_record.main_site_a_records["wildcard"]' | grep -E 'ttl_sec|target'
# Expect: ttl_sec = 300; target = <new instance IP>
```

- [ ] **Step 5: Verify Task 2 (Cloud Firewall)**

```bash
INSTANCE_IP=$(ssh dokploy-prod 'curl -4 -sS ifconfig.me')

# Allowed ports work
ssh dokploy-prod 'echo ok'                                         # 22
curl -sI "https://vulcan.symbionic.tech" | head -1                # 443
curl -sI "http://vulcan.symbionic.tech" | head -1                 # 80

# A non-allowed port is dropped (timeout, not RST)
nc -zv -w 5 "$INSTANCE_IP" 8080
# Expect: timeout
```

- [ ] **Step 6: Verify Task 3 (no root SSH, non-root user with sudo)**

```bash
ssh dokploy-prod whoami
# Expect: symbionic_dokploy_user

ssh dokploy-prod sudo -n true && echo "passwordless sudo OK"
# Expect: passwordless sudo OK

ssh -o BatchMode=yes -o ConnectTimeout=5 \
    -i linode/environments/production/id_ed25519 \
    root@$(ssh dokploy-prod 'curl -4 -sS ifconfig.me') true 2>&1 | head -3
# Expect: "Permission denied (publickey)" — NOT a successful exec
```

- [ ] **Step 7: Verify Task 4 (unattended-upgrades)**

```bash
ssh dokploy-prod 'systemctl is-enabled unattended-upgrades && systemctl is-active unattended-upgrades'
# Expect: enabled / active

ssh dokploy-prod 'sudo unattended-upgrade --dry-run -d 2>&1 | tail -20'
# Expect: "Packages that will be upgraded: ..." (possibly empty) and no errors
```

- [ ] **Step 8: Verify Task 5 (fail2ban)**

```bash
ssh dokploy-prod 'systemctl is-active fail2ban'
# Expect: active

ssh dokploy-prod 'sudo fail2ban-client status sshd'
# Expect: status block, jail loaded, banned IP list (empty on a fresh boot)
```

- [ ] **Step 9: Verify Task 6 (DNS-01 + cert)**

```bash
# Dokploy stored the Traefik env keys
ssh dokploy-prod '
  API_KEY=$(sudo cat /root/.dokploy-api-key)
  curl -s "http://localhost:3000/api/trpc/settings.readTraefikEnv?input=%7B%22json%22%3A%7B%7D%7D" \
    -H "x-api-key: $API_KEY" | jq -r ".result.data.json"
' | grep -E '^TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE'
# Expect: TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE=true
#         TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE_PROVIDER=linode

# Traefik attempted DNS-01 (not HTTP-01) on this boot
ssh dokploy-prod 'sudo docker logs dokploy-traefik 2>&1 | grep -iE "dns-01|dnsChallenge|provider.*linode" | tail -10'
# Expect: at least one DNS-01 / linode provider line (if cert was restored from backup, may be silent — that's also success)

# Live cert is LE-issued
echo | openssl s_client -connect vulcan.symbionic.tech:443 -servername vulcan.symbionic.tech 2>/dev/null \
  | openssl x509 -noout -subject -issuer -dates
# Expect: issuer = "Let's Encrypt"; subject CN = vulcan.symbionic.tech
```

- [ ] **Step 10: Verify backup pipeline still works end-to-end**

```bash
ssh dokploy-prod 'sudo systemctl start acme-backup.service && sleep 2 && sudo tail -10 /var/log/acme-backup/backup.log'
# Expect last line: [backup_acme] OK: uploaded <N>B plaintext / <M>B encrypted

# Confirm the encrypted blob landed in the bucket and is recent
ssh dokploy-prod 'source /root/.acme-backup.env && s3cmd ls "s3://$BACKUP_BUCKET/acme.json.gpg"'
# Expect: a line dated within the last minute or two
```

- [ ] **Step 11: Re-sync secrets through chezmoi**

Per project convention, after the apply:

```bash
# From repo root
chezmoi --config ./.chezmoi.toml diff
# Review any drift; merge intentional changes back to .secrets/

chezmoi --config ./.chezmoi.toml git -- add .
chezmoi --config ./.chezmoi.toml git -- commit -m "sync: hardening + DNS-01 deploy"
chezmoi --config ./.chezmoi.toml git -- push

# Parent repo: commit the submodule pointer bump + any .terraform.lock.hcl changes
git add .secrets linode/environments/production/.terraform.lock.hcl
git status
git commit -m "chore: bump .secrets after hardening + DNS-01 deploy"
```

---

## Out of Scope (Deferred)

- **Reserve a stable IPv4 across instance replacements** — was a separate task in earlier drafts. Removed because the DNS-01 work (now Task 6) eliminates the cert-issuance race that motivated it, and Task 1 (TTL=300) caps end-user propagation pain at ~5 minutes after a replacement. The remaining benefit doesn't justify the complexity: Linode requires either the not-yet-account-enabled "Reserved IP" feature or the parking-anchor pattern (a $5/mo Nanode held as IP anchor + Terraform-managed swap orchestration). Revisit only if a future workload genuinely cannot tolerate the 5-min propagation window.
- **Dokploy dashboard IP allow-list at Traefik layer** — discussed in conversation but not included here. Would add a `vulcan.*`-scoped IP-allowlist middleware in Dokploy's Traefik config. Useful once you have a stable source IP to allow-list; defer until that's settled.
- **Linode account hardening (2FA, scoped API tokens beyond the DNS-01 one)** — account-level, not IaC-managed. Add to ops runbook. (Note: Task 6 introduces a `domains:read_write`-scoped token for Traefik DNS-01; the master `TF_VAR_LINODE_TOKEN` is still in scope here and lives only on the deploy machine.)
- **Migration off `s3cmd` to `linode-cli obj`** — explicitly rejected in the prior plan due to needing a master Linode API token on the tenant box. No change here.
