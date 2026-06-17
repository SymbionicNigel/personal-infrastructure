# MC Connectivity & Local Provisioning Foundation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Terraform-managed tailnet, join the existing Linode host
to it, and author the `homelab/` provisioning foundation (shared Tailscale
script + Ansible roles), converging the i7 Wings node and Pi subnet router as
they come online.

**Architecture:** Tailnet-as-code lives in a new `linode/modules/tailnet/`
consumed by `environments/production`; its generated `mc-cloud` auth key feeds a
post-boot `null_resource` that joins the cloud host (Terraform stays the only
provisioning path for that host). A single parameterized
`homelab/scripts/install-tailscale.sh` is the one source of truth for joining
any box — invoked by that `null_resource`, the Ansible `tailscale` role, and the
flash-drive `bootstrap.sh`. Ansible (push over the tailnet) converges the home
boxes.

**Tech Stack:** Terraform (`tailscale/tailscale` + `linode/linode`), Bash,
Ansible, GitHub Actions, chezmoi/GPG secrets.

**Parent design:**
[2026-06-14-minecraft-management-architecture-design.md](./2026-06-14-minecraft-management-architecture-design.md)
(sub-project 1). The brainstorming conversation is the spec.

**Convergence happens inline:** the tailnet + cloud host go live in Task 5; the
i7 and Pi are bootstrapped and converged in Task 10/11 as you bring them up; the
`wings` role's live converge is the one genuine cross-project wait — it needs the
node token sub-project 2 emits (Task 12).

---

## File structure

Created:

```text
homelab/
  README.md
  scripts/
    install-tailscale.sh        # shared tailnet-join (Task 1)
    bootstrap.sh                # flash-drive one-touch (Task 6)
  ansible/
    ansible.cfg                 # Task 7
    requirements.yml            # Task 7
    site.yml                    # Task 7
    inventory/hosts.yml         # Task 7
    inventory/group_vars/all.yml
    roles/
      common/tasks/main.yml     # Task 8
      tailscale/{tasks,defaults,files}   # Task 9
      docker/tasks/main.yml     # Task 10
      subnet-router/{tasks,defaults}     # Task 11
      wings/{tasks,defaults,handlers,templates}  # Task 12
  .env.example                  # Task 7

linode/modules/tailnet/{main,variables,outputs}.tf  # Task 3
linode/modules/tailnet/acl.hujson                   # Task 2
.github/workflows/_homelab-lint.yml                 # Task 13
```

Modified:

```text
linode/environments/production/base.tf          # provider + module + join
linode/environments/production/variables.tf     # tailscale vars
linode/environments/production/.env(.example)   # OAuth client creds
.github/workflows/ci.yml                         # wire homelab lint
```

---

## Task 1: Shared `install-tailscale.sh`

Built first: both the Terraform host-join (Task 5) and the `tailscale` role
(Task 9) consume it.

**Files:**
- Create: `homelab/scripts/install-tailscale.sh`

- [ ] **Step 1: Write the script**

```bash
#!/usr/bin/env bash
# Install tailscaled (if absent) and bring the box onto the tailnet.
# Idempotent and re-runnable. Single source of truth for tailnet membership:
# invoked by the cloud host's Terraform null_resource, the Ansible `tailscale`
# role, and the flash-drive bootstrap.sh.
set -euo pipefail

AUTHKEY=""
ADVERTISE_TAGS=""
ADVERTISE_ROUTES=""
ENABLE_SSH=0

usage() {
  echo "Usage: $0 --authkey KEY --advertise-tags TAGS \
[--advertise-routes CIDR] [--ssh]" >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --authkey)          AUTHKEY="${2:?}"; shift 2 ;;
    --advertise-tags)   ADVERTISE_TAGS="${2:?}"; shift 2 ;;
    --advertise-routes) ADVERTISE_ROUTES="${2:?}"; shift 2 ;;
    --ssh)              ENABLE_SSH=1; shift ;;
    *)                  usage ;;
  esac
done

[ -n "$AUTHKEY" ] && [ -n "$ADVERTISE_TAGS" ] || usage

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

up_args=(--authkey "$AUTHKEY" --advertise-tags "$ADVERTISE_TAGS")
[ -n "$ADVERTISE_ROUTES" ] && up_args+=(--advertise-routes "$ADVERTISE_ROUTES")
[ "$ENABLE_SSH" -eq 1 ] && up_args+=(--ssh)

sudo tailscale up "${up_args[@]}"
```

- [ ] **Step 2: Make executable and shellcheck**

Run: `chmod +x homelab/scripts/install-tailscale.sh && shellcheck homelab/scripts/install-tailscale.sh`
Expected: exit 0, no output.

- [ ] **Step 3: Verify it fails closed on missing args**

Run: `bash homelab/scripts/install-tailscale.sh; echo "exit=$?"`
Expected: usage line printed, `exit=64`, no tailscale/network calls.

---

## Task 2: Tailnet ACL policy file

A separate HuJSON file so the policy is diff-reviewable, not buried in an HCL
string. `home_lan_cidr` and `game_port_range` are templated by Task 3.

**Files:**
- Create: `linode/modules/tailnet/acl.hujson`

- [ ] **Step 1: Write the policy**

The permissive `autogroup:member` rule preserves connectivity for any
pre-existing devices on the tailnet; the tag-scoped rule below it is the
documentary intent. Dropping the member rule to fully tighten is deliberate
later work.

```hujson
{
  "tagOwners": {
    "tag:mc-cloud":   ["autogroup:admin"],
    "tag:mc-compute": ["autogroup:admin"],
    "tag:mc-gateway": ["autogroup:admin"],
  },
  "acls": [
    // Preserve existing tailnet connectivity. Tighten later by removing this.
    { "action": "accept", "src": ["autogroup:member"], "dst": ["*:*"] },
    // Cloud host -> compute: Wings API, SFTP, and the game-port range.
    {
      "action": "accept",
      "src": ["tag:mc-cloud"],
      "dst": [
        "tag:mc-compute:8080",
        "tag:mc-compute:2022",
        "tag:mc-compute:${game_port_range}",
      ],
    },
  ],
  "ssh": [
    {
      "action": "accept",
      "src": ["autogroup:admin"],
      "dst": ["tag:mc-cloud", "tag:mc-compute", "tag:mc-gateway"],
      "users": ["autogroup:nonroot", "root"],
    },
  ],
  "autoApprovers": {
    "routes": {
      "${home_lan_cidr}": ["tag:mc-gateway"],
    },
  },
}
```

- [ ] **Step 2: Confirm only the two interpolations exist**

Run: `grep -n '\${' linode/modules/tailnet/acl.hujson`
Expected: exactly `${game_port_range}` and `${home_lan_cidr}`.

---

## Task 3: `linode/modules/tailnet/` module

Tags, ACL, MagicDNS, and three tagged auth keys. The provider is configured in
`production` (Task 4); modules inherit it, matching `network`/`domain`.

**Files:**
- Create: `linode/modules/tailnet/variables.tf`
- Create: `linode/modules/tailnet/main.tf`
- Create: `linode/modules/tailnet/outputs.tf`

- [ ] **Step 1: `variables.tf`**

```hcl
variable "home_lan_cidr" {
  type        = string
  nullable    = false
  description = "Home LAN CIDR the Pi subnet-router advertises, e.g. 192.168.1.0/24"
}

variable "game_port_range" {
  type        = string
  default     = "25565-25600"
  description = "Compute-node port range the cloud host may reach for game traffic"
}

variable "key_expiry_seconds" {
  type        = number
  default     = 7776000 # 90 days, the provider maximum
  description = "Lifetime of generated tagged auth keys"
}
```

- [ ] **Step 2: `main.tf`**

```hcl
terraform {
  required_providers {
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
  }
}

resource "tailscale_acl" "policy" {
  acl = templatefile("${path.module}/acl.hujson", {
    home_lan_cidr   = var.home_lan_cidr
    game_port_range = var.game_port_range
  })
}

resource "tailscale_dns_preferences" "magicdns" {
  magic_dns = true
}

resource "tailscale_tailnet_key" "cloud" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-cloud (Linode host)"
  tags          = ["tag:mc-cloud"]
}

resource "tailscale_tailnet_key" "compute" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-compute (i7 Wings node)"
  tags          = ["tag:mc-compute"]
}

resource "tailscale_tailnet_key" "gateway" {
  reusable      = true
  ephemeral     = false
  preauthorized = true
  expiry        = var.key_expiry_seconds
  description   = "mc-gateway (Pi subnet router)"
  tags          = ["tag:mc-gateway"]
}
```

- [ ] **Step 3: `outputs.tf`**

```hcl
output "cloud_auth_key" {
  value       = tailscale_tailnet_key.cloud.key
  sensitive   = true
  description = "Auth key for the Linode host (tag:mc-cloud)"
}

output "compute_auth_key" {
  value       = tailscale_tailnet_key.compute.key
  sensitive   = true
  description = "Auth key for the i7 (tag:mc-compute), for bootstrap.sh"
}

output "gateway_auth_key" {
  value       = tailscale_tailnet_key.gateway.key
  sensitive   = true
  description = "Auth key for the Pi (tag:mc-gateway), for bootstrap.sh"
}
```

- [ ] **Step 4: Validate the module in isolation**

Run: `terraform -chdir=linode/modules/tailnet init -backend=false && terraform -chdir=linode/modules/tailnet validate`
Expected: `Success! The configuration is valid.`

---

## Task 4: Provider + secrets in `production`

**Files:**
- Modify: `linode/environments/production/base.tf`
- Modify: `linode/environments/production/variables.tf`
- Modify: `linode/environments/production/.env` + `.env.example`

- [ ] **Step 1: Add to `required_providers`** (insert alphabetically before `time`)

```hcl
    tailscale = {
      source  = "tailscale/tailscale"
      version = "~> 0.21"
    }
```

- [ ] **Step 2: Add the provider block** (after `provider "linode"`)

```hcl
# Tailnet-as-code. OAuth client (recommended over a personal API key).
# tailnet "-" = the OAuth client's own tailnet.
provider "tailscale" {
  oauth_client_id     = var.TAILSCALE_OAUTH_CLIENT_ID
  oauth_client_secret = var.TAILSCALE_OAUTH_CLIENT_SECRET
  tailnet             = "-"
}
```

- [ ] **Step 3: Add variables to `variables.tf`**

```hcl
variable "TAILSCALE_OAUTH_CLIENT_ID" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Tailscale OAuth client ID (scopes: auth keys, dns, policy file, devices)"
}

variable "TAILSCALE_OAUTH_CLIENT_SECRET" {
  type        = string
  sensitive   = true
  nullable    = false
  description = "Tailscale OAuth client secret"
}

variable "HOME_LAN_CIDR" {
  type        = string
  nullable    = false
  description = "Home LAN CIDR advertised by the Pi subnet router"
}
```

- [ ] **Step 4: Append to `.env.example`** (then set real values in `.env` and
  encrypt it via the chezmoi add-secret script)

```dotenv
# Tailscale OAuth client (Admin console -> Settings -> OAuth clients).
# Scopes: Auth Keys (write), DNS (write), Policy File (write), Devices (read).
TF_VAR_TAILSCALE_OAUTH_CLIENT_ID=
TF_VAR_TAILSCALE_OAUTH_CLIENT_SECRET=
TF_VAR_HOME_LAN_CIDR=192.168.1.0/24
```

- [ ] **Step 5: Validate**

Run: `terraform -chdir=linode/environments/production init -backend=false && terraform -chdir=linode/environments/production validate`
Expected: `Success! The configuration is valid.`

---

## Task 5: Join the Linode host to the tailnet — and apply

Adds the module call + a `null_resource` modeled on `null_resource.ghcr_login`,
then applies so the tailnet and cloud host go live.

**Files:**
- Modify: `linode/environments/production/base.tf`

- [ ] **Step 1: Add the module call** (near the other `module` blocks)

```hcl
module "tailnet" {
  source = "../../modules/tailnet"

  home_lan_cidr = var.HOME_LAN_CIDR
}
```

- [ ] **Step 2: Add the host-join resource**

```hcl
# Join the Linode host to the tailnet as tag:mc-cloud. Mirrors ghcr_login:
# ships the shared install-tailscale.sh, runs it, rm's the key in the same step.
# Triggers on host IP + key hash, so rebuilds/rotation re-converge hands-off.
# --ssh enables Tailscale SSH so later Ansible push reaches home boxes through
# this host's tailscale0.
resource "null_resource" "tailscale_join" {
  depends_on = [module.dokploy-instance, module.tailnet]

  triggers = {
    instance_ip = module.dokploy-instance.instance_ip
    key_hash    = sha256(module.tailnet.cloud_auth_key)
  }

  connection {
    type        = "ssh"
    host        = module.dokploy-instance.instance_ip
    user        = module.dokploy-instance.deploy_user
    private_key = file("${path.root}/id_ed25519")
  }

  provisioner "file" {
    source      = "${path.root}/../../../homelab/scripts/install-tailscale.sh"
    destination = "/home/${module.dokploy-instance.deploy_user}/install-tailscale.sh"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      set -eu
      chmod +x /home/${module.dokploy-instance.deploy_user}/install-tailscale.sh
      sudo /home/${module.dokploy-instance.deploy_user}/install-tailscale.sh \
        --authkey '${module.tailnet.cloud_auth_key}' \
        --advertise-tags tag:mc-cloud \
        --ssh
      rm -f /home/${module.dokploy-instance.deploy_user}/install-tailscale.sh
      EOT
    ]
  }
}
```

- [ ] **Step 3: Validate**

Run: `terraform -chdir=linode/environments/production validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Apply (real credentials) and verify the host is on the tailnet**

With the production `.env` sourced, run `cd linode/environments/production && bash production.sh`.
Expected plan additions: `tailscale_acl.policy`, `tailscale_dns_preferences.magicdns`,
three `tailscale_tailnet_key.*`, `null_resource.tailscale_join`. After apply:

Run (from any tailnet member): `tailscale status | grep mc-cloud`
Expected: the Linode host listed with `tag:mc-cloud`. MagicDNS resolves its name.

---

## Task 6: `bootstrap.sh` (flash-drive one-touch)

Minimal: joins a fresh box to the tailnet via the shared script. Docker/Wings
are the Ansible roles' job.

**Files:**
- Create: `homelab/scripts/bootstrap.sh`

- [ ] **Step 1: Write it**

```bash
#!/usr/bin/env bash
# One local touch for a fresh box: join it to the tailnet so Ansible push can
# take over. Thin wrapper over install-tailscale.sh in the same dir.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$here/install-tailscale.sh" "$@"
```

- [ ] **Step 2: Make executable, shellcheck, verify passthrough**

Run:
```bash
chmod +x homelab/scripts/bootstrap.sh
shellcheck homelab/scripts/bootstrap.sh
bash homelab/scripts/bootstrap.sh; echo "exit=$?"
```
Expected: shellcheck exit 0; the usage line from `install-tailscale.sh` and
`exit=64`.

---

## Task 7: Ansible skeleton

**Files:**
- Create: `homelab/ansible/ansible.cfg`, `requirements.yml`, `site.yml`,
  `inventory/hosts.yml`, `inventory/group_vars/all.yml`, `homelab/.env.example`,
  `homelab/README.md`

- [ ] **Step 1: `ansible.cfg`**

```ini
[defaults]
inventory = inventory/hosts.yml
roles_path = roles
host_key_checking = False
stdout_callback = yaml
interpreter_python = auto_silent

[ssh_connection]
pipelining = True
```

- [ ] **Step 2: `requirements.yml`**

```yaml
---
collections:
  - name: ansible.posix
  - name: community.docker
  - name: community.general
roles: []
```

- [ ] **Step 3: `inventory/hosts.yml`** (MagicDNS names; placeholders until
  the boxes are bootstrapped and named)

```yaml
---
all:
  children:
    compute:
      hosts:
        i7:
          ansible_host: i7.<your-tailnet>.ts.net
      vars:
        tailscale_advertise_tags: tag:mc-compute
    gateway:
      hosts:
        pi:
          ansible_host: pi.<your-tailnet>.ts.net
      vars:
        subnet_router_cidr: 192.168.1.0/24
        tailscale_advertise_routes: 192.168.1.0/24
        tailscale_advertise_tags: tag:mc-gateway
  vars:
    ansible_python_interpreter: /usr/bin/python3
    ansible_user: deploy
```

- [ ] **Step 4: `inventory/group_vars/all.yml`**

```yaml
---
# Per-box auth key, supplied at run time: --extra-vars tailscale_authkey=...
tailscale_authkey: ""
```

- [ ] **Step 5: `site.yml`**

```yaml
---
- name: Common baseline on all home boxes
  hosts: all
  become: true
  roles:
    - common
    - tailscale
    - docker

- name: Compute node (Wings)
  hosts: compute
  become: true
  roles:
    - wings

- name: Gateway node (subnet router)
  hosts: gateway
  become: true
  roles:
    - subnet-router
```

- [ ] **Step 6: `homelab/.env.example`**

```dotenv
# Provided by sub-project 2 (the Pelican node's config.yml). Empty until then.
WINGS_CONFIG=
```

- [ ] **Step 7: `homelab/README.md`**

```markdown
# homelab — local infrastructure

Home-side provisioning for the Minecraft compute (i7 Wings node, Pi subnet
router). The cloud side stays in `linode/`.

## Bring up a box

1. Flash Ubuntu LTS, enable SSH, create the `deploy` user.
2. Copy `scripts/` to the box and run:
   `sudo bash scripts/bootstrap.sh --authkey <KEY> --advertise-tags <TAG>`
   `<KEY>` = the matching `*_auth_key` output of the `tailnet` Terraform module;
   `<TAG>` = `tag:mc-compute` (i7) or `tag:mc-gateway` (Pi).
3. Put the box's MagicDNS name in `ansible/inventory/hosts.yml`.
4. Converge: `cd ansible && ansible-playbook site.yml --limit <host> \
   --extra-vars tailscale_authkey=<KEY>`.

## Layout

- `scripts/install-tailscale.sh` — shared tailnet-join (also used by Terraform).
- `scripts/bootstrap.sh` — one-touch flash-drive entry (Tailscale only).
- `ansible/` — roles, inventory, playbook. Governed by `ansible-lint`.
```

- [ ] **Step 8: Install tooling and syntax-check**

Run:
```bash
pip install ansible ansible-lint
cd homelab/ansible && ansible-galaxy collection install -r requirements.yml
ansible-playbook site.yml --syntax-check
```
Expected: fails referencing the missing roles (resolves after Task 12) —
confirms the playbook/inventory parse.

---

## Task 8: `common` role

**Files:**
- Create: `homelab/ansible/roles/common/tasks/main.yml`

- [ ] **Step 1: Write the tasks**

```yaml
---
- name: Install base packages
  ansible.builtin.apt:
    name:
      - ca-certificates
      - curl
      - gnupg
      - unattended-upgrades
    state: present
    update_cache: true
    cache_valid_time: 3600

- name: Enable unattended-upgrades
  ansible.builtin.service:
    name: unattended-upgrades
    enabled: true
    state: started
```

- [ ] **Step 2: Lint**

Run: `cd homelab/ansible && ansible-lint roles/common`
Expected: PASS.

---

## Task 9: `tailscale` role

Thin wrapper: ships the shared `install-tailscale.sh` and runs it. No duplicated
install logic.

**Files:**
- Create: `homelab/ansible/roles/tailscale/files/install-tailscale.sh` (symlink)
- Create: `homelab/ansible/roles/tailscale/defaults/main.yml`
- Create: `homelab/ansible/roles/tailscale/tasks/main.yml`

- [ ] **Step 1: Symlink the single source of truth into the role**

Run:
```bash
mkdir -p homelab/ansible/roles/tailscale/files
ln -srf homelab/scripts/install-tailscale.sh \
  homelab/ansible/roles/tailscale/files/install-tailscale.sh
```

- [ ] **Step 2: `defaults/main.yml`**

```yaml
---
tailscale_authkey: ""
tailscale_advertise_tags: ""
tailscale_advertise_routes: ""
```

- [ ] **Step 3: `tasks/main.yml`**

```yaml
---
- name: Require an auth key and tag
  ansible.builtin.assert:
    that:
      - tailscale_authkey | length > 0
      - tailscale_advertise_tags | length > 0
    fail_msg: "tailscale_authkey and tailscale_advertise_tags are required"

- name: Install join script
  ansible.builtin.copy:
    src: install-tailscale.sh
    dest: /usr/local/sbin/install-tailscale.sh
    mode: "0755"

- name: Join the tailnet
  ansible.builtin.command:
    cmd: >-
      /usr/local/sbin/install-tailscale.sh
      --authkey {{ tailscale_authkey }}
      --advertise-tags {{ tailscale_advertise_tags }}
      {{ ('--advertise-routes ' + tailscale_advertise_routes)
         if tailscale_advertise_routes | length > 0 else '' }}
  register: ts_up
  changed_when: ts_up.rc == 0
```

- [ ] **Step 4: Lint**

Run: `cd homelab/ansible && ansible-lint roles/tailscale`
Expected: PASS.

---

## Task 10: `docker` role — then bootstrap & converge the i7 base

Installs Docker, then (hardware step) brings the i7 onto the tailnet and
converges its base roles.

**Files:**
- Create: `homelab/ansible/roles/docker/tasks/main.yml`

- [ ] **Step 1: Write the tasks**

```yaml
---
- name: Check for docker
  ansible.builtin.command: docker --version
  register: docker_check
  changed_when: false
  failed_when: false

- name: Install Docker via convenience script
  ansible.builtin.shell:
    cmd: curl -fsSL https://get.docker.com | CHANNEL=stable sh
  when: docker_check.rc != 0
  changed_when: true

- name: Ensure docker is enabled and running
  ansible.builtin.service:
    name: docker
    enabled: true
    state: started
```

- [ ] **Step 2: Lint**

Run: `cd homelab/ansible && ansible-lint roles/docker`
Expected: PASS.

- [ ] **Step 3: Bootstrap the i7 (hardware)**

Flash Ubuntu LTS on the i7, create the `deploy` user, then from the box:
`sudo bash scripts/bootstrap.sh --authkey <compute_auth_key> --advertise-tags tag:mc-compute`
(`<compute_auth_key>` = `terraform -chdir=linode/environments/production output -raw` of
the `tailnet` module's `compute_auth_key`, surfaced via a root output if needed).

Verify: `tailscale status | grep mc-compute` shows the i7.

- [ ] **Step 4: Set the i7's real MagicDNS name in `inventory/hosts.yml`**

Replace `i7.<your-tailnet>.ts.net` with the actual MagicDNS name.

- [ ] **Step 5: Converge the base roles on the i7**

Run: `cd homelab/ansible && ansible-playbook site.yml --limit i7 \
--extra-vars tailscale_authkey=<compute_auth_key> --tags all --skip-tags wings`
(or run with the `wings` play absent — it asserts on the missing config and will
halt; that is expected and addressed in Task 12.)
Expected: `common`, `tailscale`, `docker` converge; i7 reachable, Docker running.

---

## Task 11: `subnet-router` role — then converge the Pi

**Files:**
- Create: `homelab/ansible/roles/subnet-router/defaults/main.yml`
- Create: `homelab/ansible/roles/subnet-router/tasks/main.yml`

- [ ] **Step 1: `defaults/main.yml`**

```yaml
---
subnet_router_cidr: ""
```

- [ ] **Step 2: `tasks/main.yml`**

```yaml
---
- name: Require a CIDR to route
  ansible.builtin.assert:
    that: subnet_router_cidr | length > 0
    fail_msg: "subnet_router_cidr is required for the subnet-router role"

- name: Enable IPv4 forwarding
  ansible.posix.sysctl:
    name: net.ipv4.ip_forward
    value: "1"
    sysctl_set: true
    state: present
    reload: true

- name: Enable IPv6 forwarding
  ansible.posix.sysctl:
    name: net.ipv6.conf.all.forwarding
    value: "1"
    sysctl_set: true
    state: present
    reload: true

- name: Advertise the LAN route
  ansible.builtin.command:
    cmd: tailscale set --advertise-routes={{ subnet_router_cidr }}
  changed_when: true
```

- [ ] **Step 3: Lint**

Run: `cd homelab/ansible && ansible-lint roles/subnet-router`
Expected: PASS.

- [ ] **Step 4: Bootstrap the Pi (hardware) and converge**

On the Pi: `sudo bash scripts/bootstrap.sh --authkey <gateway_auth_key> --advertise-tags tag:mc-gateway`,
set its MagicDNS name in the inventory, then:
`cd homelab/ansible && ansible-playbook site.yml --limit pi --extra-vars tailscale_authkey=<gateway_auth_key>`.
Expected: forwarding enabled, route advertised. Because the ACL auto-approves
`tag:mc-gateway` routes, the `192.168.1.0/24` route shows **approved** in
`tailscale status` / the admin console with no manual click.

---

## Task 12: `wings` role — converge once sub-project 2 emits the node token

The node config (`/etc/pelican/config.yml`) is produced by the Pelican panel in
sub-project 2. The role is authored now; its live converge is the cross-project
seam — run Step 6 when SP2 hands over the node config.

**Files:**
- Create: `homelab/ansible/roles/wings/defaults/main.yml`
- Create: `homelab/ansible/roles/wings/templates/wings.service.j2`
- Create: `homelab/ansible/roles/wings/tasks/main.yml`
- Create: `homelab/ansible/roles/wings/handlers/main.yml`

- [ ] **Step 1: `defaults/main.yml`**

```yaml
---
# Full /etc/pelican/config.yml content, copied from the Panel's node page (SP2).
# Empty so the assert fails loudly until SP2 provides it.
wings_config: ""
wings_version: latest
```

- [ ] **Step 2: `templates/wings.service.j2`**

```jinja
[Unit]
Description=Pelican Wings Daemon
After=docker.service
Requires=docker.service
PartOf=docker.service

[Service]
User=root
WorkingDirectory=/etc/pelican
LimitNOFILE=4096
PIDFile=/var/run/wings/daemon.pid
ExecStart=/usr/local/bin/wings
Restart=on-failure
StartLimitInterval=180
StartLimitBurst=30
RestartSec=5s

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 3: `tasks/main.yml`**

```yaml
---
- name: Require node config from the Panel (sub-project 2)
  ansible.builtin.assert:
    that: wings_config | length > 0
    fail_msg: >-
      wings_config is empty. Create the node in the Pelican panel (sub-project 2)
      and supply its config.yml before converging this role.

- name: Create Wings directories
  ansible.builtin.file:
    path: "{{ item }}"
    state: directory
    mode: "0700"
  loop:
    - /etc/pelican
    - /var/run/wings

- name: Download Wings binary
  ansible.builtin.get_url:
    url: >-
      https://github.com/pelican-dev/wings/releases/{{
        'latest/download' if wings_version == 'latest'
        else 'download/' + wings_version
      }}/wings_linux_{{ 'amd64' if ansible_architecture == 'x86_64' else 'arm64' }}
    dest: /usr/local/bin/wings
    mode: "0755"

- name: Write node config
  ansible.builtin.copy:
    content: "{{ wings_config }}"
    dest: /etc/pelican/config.yml
    mode: "0600"
  notify: Restart wings

- name: Install systemd unit
  ansible.builtin.template:
    src: wings.service.j2
    dest: /etc/systemd/system/wings.service
    mode: "0644"
  notify: Restart wings

- name: Enable and start wings
  ansible.builtin.systemd:
    name: wings
    enabled: true
    state: started
    daemon_reload: true
```

- [ ] **Step 4: `handlers/main.yml`**

```yaml
---
- name: Restart wings
  ansible.builtin.systemd:
    name: wings
    state: restarted
    daemon_reload: true
```

- [ ] **Step 5: Lint**

Run: `cd homelab/ansible && ansible-lint roles/wings`
Expected: PASS.

- [ ] **Step 6: Converge Wings on the i7 (after SP2 hands over the node config)**

Run: `cd homelab/ansible && ansible-playbook site.yml --limit i7 \
--extra-vars "tailscale_authkey=<compute_auth_key> wings_config='$(cat <node-config.yml>)'"`.
Expected: Wings installed, `systemctl status wings` active, and the node shows
**connected** (heartbeat green) in the Pelican panel.

---

## Task 13: CI — lint the homelab tree

**Files:**
- Create: `.github/workflows/_homelab-lint.yml`
- Modify: `.github/workflows/ci.yml`

- [ ] **Step 1: `_homelab-lint.yml`** (keys alphabetical, matching the repo)

```yaml
name: _homelab-lint

on:
  workflow_call:

jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6
      - name: shellcheck
        run: shellcheck homelab/scripts/*.sh
      - name: install ansible tooling
        run: pip install ansible ansible-lint
      - name: ansible collections
        run: ansible-galaxy collection install -r homelab/ansible/requirements.yml
      - name: ansible-lint
        run: ansible-lint
        working-directory: homelab/ansible
      - name: syntax-check
        run: ansible-playbook site.yml --syntax-check
        working-directory: homelab/ansible
```

- [ ] **Step 2: Add a `homelab` filter + output to the `changes` job**

In `ci.yml` `changes.outputs` (alphabetical, after `astarte`):

```yaml
      homelab: ${{ steps.filter.outputs.homelab || 'false' }}
```

In the `filters` block:

```yaml
            homelab:
              - 'homelab/**'
              - '.github/workflows/_homelab-lint.yml'
```

- [ ] **Step 3: Add the `homelab` job and make it a required check**

Add (alphabetical, after `dokploy`):

```yaml
  homelab:
    if: ${{ needs.changes.outputs.homelab == 'true' }}
    needs: changes
    uses: ./.github/workflows/_homelab-lint.yml
```

Append `homelab` to `ci-gate.needs`:

```yaml
    needs: [changes, astarte, iris, collect, prod, dokploy, homelab]
```

- [ ] **Step 4: Validate workflow YAML + run the lint commands locally**

Run:
```bash
python -c "import yaml; yaml.safe_load(open('.github/workflows/ci.yml')); yaml.safe_load(open('.github/workflows/_homelab-lint.yml')); print('ok')"
shellcheck homelab/scripts/*.sh
cd homelab/ansible && ansible-lint && ansible-playbook site.yml --syntax-check
```
Expected: `ok`; shellcheck PASS; `ansible-lint` PASS; `--syntax-check` PASS (all
roles now exist).
