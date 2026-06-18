# MC Public Player Ingress (Infrared) — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use
> superpowers:subagent-driven-development (recommended) or
> superpowers:executing-plans to implement this plan task-by-task. Steps use
> checkbox (`- [ ]`) syntax for tracking.

**Goal:** Publish one public TCP port (`25565`) on the Linode host running
Infrared, which reads each Minecraft handshake hostname and forwards the stream
over Tailscale to the matching Wings server port on the home i7 — so many
servers sit behind one public port and the home IP is never exposed.

**Architecture:** Infrared is appended to the existing Dokploy compose stack as
another service (like `astarte`/`iris`/`pelican`), but — unlike the
Traefik-fronted HTTP services — it publishes host port `25565/tcp` directly,
because it speaks the raw Minecraft protocol, not HTTP. Its `config.yml` and
per-server `proxies/*.yml` files are delivered as Docker Compose **inline
`configs`** whose `${HOSTNAME_TLD}` / `${I7_TAILSCALE_IP}` placeholders are
substituted by Terraform's `templatefile()` at apply time (the same mechanism
that fills the Traefik labels), so the proxy map is version-controlled in the
compose file with no host-side files and no secrets. The container reaches the
i7's `100.x` Tailscale IP through the Linode host's `tailscale0` (the same path
the Pelican panel uses for the Wings API). The Linode network firewall opens
inbound TCP `25565`. DNS needs no new records: the existing `*.<tld>` wildcard
already resolves the flat server names, and HTTP (`443`→Traefik) vs. Minecraft
(`25565`→Infrared) are separated by port.

**Tech Stack:** Docker Compose (inline `configs`), Dokploy (`j0bIT/dokploy`),
Terraform (`linode/linode`, `germanbrew/dotenv`), Infrared v2
(`haveachin/infrared`), Tailscale, chezmoi/GPG secrets.

**Parent design:**
[2026-06-14-minecraft-management-architecture-design.md](./2026-06-14-minecraft-management-architecture-design.md)
(sub-project 3). The brainstorming conversation is the spec.

## Global Constraints

- **Build order 1 → 2 → 3.** This sub-project is last: it assumes SP1 (i7 on the
  tailnet, Wings converged) and SP2 (panel up, servers created with known port
  allocations) are done. Infrared has nothing to route to otherwise.
- **Java/TCP only (v1).** No Bedrock/UDP ingress.
- **One public port.** Only TCP `25565` is exposed publicly; the per-server fan
  -out happens inside Infrared by handshake hostname.
- **Infrared v2 config schema** (`config.yml` + a `proxies/` dir of files with
  `domains:` / `addresses:`). Pin the image to a v2 tag — `latest` on this repo
  tracks the v2 alpha line, but pin for reproducibility per repo posture.
- **Docker Compose v2.23.1+** on the Dokploy host (inline `configs.content`
  support). This is satisfied by current Dokploy hosts; Task 6 verifies it.
- **TLD is `symbionic.tech`** (from `compose/.env.prod`). Server names are flat,
  single-label: `survival.symbionic.tech`, `creative.symbionic.tech`.
- **YAML key convention:** in compose service blocks `image` comes first, then
  remaining keys alphabetical; Traefik label keys sorted A–Z (match the file).

## Cross-project seams

- **i7 Tailscale IP** — produced when SP1 brings the i7 onto the tailnet (its
  Task 10). Read it the same way SP2 Task 6 Step 1 does
  (`tailscale status | grep mc-compute`). Supplied here as
  `TF_VAR_I7_TAILSCALE_IP` (Task 5).
- **Per-server backend ports** — allocated by the Pelican panel / Wings when each
  server is created (SP2). The `addresses:` in each proxy config must match those
  allocations. This is the architecture's documented manual sync point: adding a
  server = add a proxy config block here and re-apply (Task 6, Step 5).

## File structure

Modified:

```text
compose/docker-compose.yml                   # infrared service + inline configs (Task 1)
.secrets/.chezmoitemplates/compose-env        # INFRARED_IMAGE_TAG, I7_TAILSCALE_IP locals (Task 2)
compose/.env.example                          # document the two new vars (Task 2)
linode/environments/dokploy/variables.tf      # INFRARED_IMAGE_TAG, I7_TAILSCALE_IP (Task 3)
linode/environments/dokploy/main.tf           # templatefile vars (Task 3)
linode/modules/network/main.tf                # inbound TCP 25565 (Task 4)
.secrets/linode/environments/dokploy/encrypted_dot_env  # TF_VAR_I7_TAILSCALE_IP (Task 5, via chezmoi)
linode/README.md                              # ingress subsection (Task 7)
```

No new files are created.

---

## Task 1: Infrared compose service + inline proxy configs

Append the `infrared` service after the `pelican` block (added in SP2), and add a
top-level `configs:` block holding `config.yml` and one proxy file per server.
Every value that varies by environment is a `${VAR}` reference that Terraform's
`templatefile()` substitutes at apply time (exactly like the Traefik `Host()`
rules) — `${HOSTNAME_TLD}`, `${I7_TAILSCALE_IP}`, `${INFRARED_IMAGE_TAG}`. None
is a secret, so no `dokploy_environment_variables` resource is needed; the
rendered values are baked into the raw compose content. Infrared has **no Traefik
labels** — it owns raw TCP `25565` and is not an HTTP service.

**Files:**
- Modify: `compose/docker-compose.yml`

**Interfaces:**
- Consumes (from Task 3 via `templatefile()`): `HOSTNAME_TLD`,
  `I7_TAILSCALE_IP`, `INFRARED_IMAGE_TAG`.
- Produces: a service named `infrared` publishing host `25565/tcp`; top-level
  config names `infrared_config`, `infrared_proxy_survival`,
  `infrared_proxy_creative` mounted at `/etc/infrared/config.yml` and
  `/etc/infrared/proxies/<name>.yml`.

- [ ] **Step 1: Add the `infrared` service** (after the `pelican` block, before
  the file's top-level `volumes:` block added in SP2)

```yaml
  # Public Minecraft ingress. Unlike the HTTP services, Infrared is not behind
  # Traefik: it speaks the raw Minecraft protocol and publishes host TCP 25565
  # directly. It reads the handshake hostname and forwards the stream to the
  # matching Wings server port on the i7 over Tailscale (reaching 100.x through
  # the host's tailscale0, like the Pelican panel reaches the Wings API). Config
  # and per-server proxy maps come from the inline `configs:` block below; their
  # ${VAR} placeholders are substituted by templatefile() at apply time, so the
  # routing table is version-controlled here with no host files and no secrets.
  infrared:
    image: haveachin/infrared:${INFRARED_IMAGE_TAG}
    configs:
      - source: infrared_config
        target: /etc/infrared/config.yml
      - source: infrared_proxy_survival
        target: /etc/infrared/proxies/survival.yml
      - source: infrared_proxy_creative
        target: /etc/infrared/proxies/creative.yml
    networks:
      - dokploy-network
    ports:
      - '25565:25565/tcp'
    restart: unless-stopped
```

- [ ] **Step 2: Add the top-level `configs:` block** (at the end of the file,
  after the `volumes:` block; if `volumes:` is absent, append `configs:` as the
  last top-level key)

Each proxy file's `addresses:` port must match the Wings allocation for that
server (SP2). `survival` = i7 `25565`, `creative` = i7 `25566` — the first two
of SP1's `25565-25600` compute port range. To add a server later: add a
`configs:` entry + a matching `service.configs` mount, then re-apply.

```yaml
configs:
  infrared_config:
    content: |
      # Public listener. Infrared multiplexes every server behind this one port
      # by matching the Minecraft handshake hostname against the proxies below.
      bind: 0.0.0.0:25565
      keepAliveTimeout: 30s
  infrared_proxy_survival:
    content: |
      domains:
        - survival.${HOSTNAME_TLD}
      addresses:
        - ${I7_TAILSCALE_IP}:25565
  infrared_proxy_creative:
    content: |
      domains:
        - creative.${HOSTNAME_TLD}
      addresses:
        - ${I7_TAILSCALE_IP}:25566
```

- [ ] **Step 3: Verify the YAML parses**

Run: `python -c "import yaml; yaml.safe_load(open('compose/docker-compose.yml')); print('ok')"`
Expected: `ok`.

- [ ] **Step 4: Confirm the service has no Traefik labels and publishes 25565**

Run: `python -c "import yaml; s=yaml.safe_load(open('compose/docker-compose.yml'))['services']['infrared']; print('labels' in s, s['ports'])"`
Expected: `False ['25565:25565/tcp']` (no `labels` key; port published).

---

## Task 2: Local-dev env vars

`docker compose` locally interpolates `${INFRARED_IMAGE_TAG}` and
`${I7_TAILSCALE_IP}` from `compose/.env`; without defaults it warns and renders
empty addresses. Add both to the shared chezmoi compose-env partial (so `.env`
and `.env.prod` both get them, like `ASTARTE_IMAGE_TAG`). Locally Infrared is
inert — it has no live i7 — so the IP is a harmless `127.0.0.1` placeholder. In
prod these values come from Terraform via `templatefile()` (Task 3), not from
`.env`.

**Files:**
- Modify: `.secrets/.chezmoitemplates/compose-env`
- Modify: `compose/.env.example`

- [ ] **Step 1: Add the two vars to the compose-env partial** (after the
  `IRIS_IMAGE_TAG=local` line, before the `GHCR_OWNER` block)

```text
# Upstream Infrared image tag (v2 line). In prod Terraform substitutes the
# pinned value via templatefile(); this local value is inert (no live i7).
INFRARED_IMAGE_TAG=latest
# Home i7's Tailscale IP that Infrared forwards Minecraft traffic to. Real value
# is supplied in prod as TF_VAR_I7_TAILSCALE_IP; locally a harmless placeholder.
I7_TAILSCALE_IP=127.0.0.1
```

- [ ] **Step 2: Document both vars in `compose/.env.example`** (append)

```dotenv
# Upstream Infrared image tag (Minecraft ingress proxy). 'latest' tracks the
# v2 alpha line; prod pins a v2 tag via linode/environments/dokploy/variables.tf
# through templatefile(). The value here is used only for local `docker compose`.
INFRARED_IMAGE_TAG=latest

# Home i7's Tailscale IP that Infrared forwards Minecraft streams to. Locally a
# placeholder (no live i7). In prod, supplied via the dokploy env as
# TF_VAR_I7_TAILSCALE_IP and substituted into the compose configs by templatefile().
I7_TAILSCALE_IP=127.0.0.1
```

- [ ] **Step 3: Render the templates and confirm both land**

Run: `czm apply && grep -E 'INFRARED_IMAGE_TAG|I7_TAILSCALE_IP' compose/.env compose/.env.prod`
Expected: `INFRARED_IMAGE_TAG=latest` and `I7_TAILSCALE_IP=127.0.0.1` in both
rendered files.

- [ ] **Step 4: Confirm compose interpolates cleanly with no warnings**

Run: `cd compose && docker compose config >/dev/null`
Expected: exit 0, no `variable is not set` warnings. (Confirms the base file +
override + rendered `.env` resolve every `${VAR}`.)

---

## Task 3: Thread Infrared vars into the dokploy environment

Add the two Terraform variables and pass them into the existing compose
`templatefile()` call so the apply-time render substitutes them into the inline
configs. `INFRARED_IMAGE_TAG` is pinned by default; `I7_TAILSCALE_IP` has no
default (supplied via the dokploy `.env` in Task 5).

**Files:**
- Modify: `linode/environments/dokploy/variables.tf`
- Modify: `linode/environments/dokploy/main.tf`

**Interfaces:**
- Produces (consumed by Task 1's compose via `templatefile()`):
  `INFRARED_IMAGE_TAG`, `I7_TAILSCALE_IP`.

- [ ] **Step 1: Add the variables** to `variables.tf` (after the `IRIS_IMAGE_TAG`
  / `PELICAN_IMAGE_TAG` block)

```hcl
variable "INFRARED_IMAGE_TAG" {
  type        = string
  nullable    = false
  description = "Image tag for the upstream Infrared proxy (haveachin/infrared, v2 line)."
  default     = "2.0.0-alpha.15"
}

variable "I7_TAILSCALE_IP" {
  type        = string
  nullable    = false
  description = "Tailscale 100.x IP of the home i7 Wings node that Infrared forwards Minecraft traffic to."
}
```

- [ ] **Step 2: Add both to the compose `templatefile()` vars** in `main.tf`
  (inside the existing `templatefile(...)` map in `locals`, alongside
  `IRIS_IMAGE_TAG`)

```hcl
    INFRARED_IMAGE_TAG = var.INFRARED_IMAGE_TAG
    I7_TAILSCALE_IP    = var.I7_TAILSCALE_IP
```

- [ ] **Step 3: Format and validate**

Run:
```bash
cd linode/environments/dokploy
terraform fmt
terraform init -backend=false && terraform validate
```
Expected: `Success! The configuration is valid.`

---

## Task 4: Open inbound TCP 25565 on the network firewall — and apply

Add the Minecraft ingress rule to the existing firewall module (matching the
`http`/`https` rule style) and apply the production environment so the port
opens. The rule lives on the firewall resource, so it survives instance
replacement (per the module's design comment).

**Files:**
- Modify: `linode/modules/network/main.tf`

- [ ] **Step 1: Add the inbound rule** (after the `https-quic` block, before
  `linodes = var.linode_ids`)

```hcl
  # Public Minecraft (Java/TCP) ingress -> Infrared on the host, which
  # multiplexes by handshake hostname to the home Wings node over Tailscale.
  # One public port, many servers; the home IP is never exposed.
  inbound {
    label    = "minecraft"
    action   = "ACCEPT"
    protocol = "TCP"
    ports    = "25565"
    ipv4     = ["0.0.0.0/0"]
    ipv6     = ["::/0"]
  }
```

- [ ] **Step 2: Validate**

Run: `cd linode/environments/production && terraform init -backend=false && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Apply and confirm the rule is live**

With the production `.env` sourced, run: `cd linode/environments/production && bash production.sh`
Expected plan change: `module.network.linode_firewall.this` updated in place with
the new `minecraft` inbound rule. After apply:

Run: `cd linode/environments/production && terraform state show 'module.network.linode_firewall.this' | grep -A1 minecraft`
Expected: the `minecraft` rule present with `ports = "25565"`.

---

## Task 5: Supply the i7 Tailscale IP and deploy the stack

Read the i7's Tailscale IP (SP1 seam), add it to the dokploy chezmoi `.env` as
`TF_VAR_I7_TAILSCALE_IP`, then apply the dokploy environment to roll out the
Infrared service.

**Files:**
- Modify: `.secrets/linode/environments/dokploy/encrypted_dot_env` (via chezmoi)

- [ ] **Step 1: Read the i7's Tailscale IP** (SP1 must have converged the i7)

Run (from any tailnet member, e.g. the Linode host): `tailscale status | grep mc-compute`
Expected: the i7 listed; note its `100.x.y.z` address.

- [ ] **Step 2: Add the credential to the dokploy chezmoi `.env`**

```bash
bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --edit \
  linode/environments/dokploy/.env
```

Append (substituting the real IP):
```dotenv
TF_VAR_I7_TAILSCALE_IP=100.x.y.z
```

- [ ] **Step 3: Apply the dokploy environment**

With the dokploy `.env` sourced, run: `cd linode/environments/dokploy && bash dokploy.sh`
Expected plan changes: `dokploy_compose.stack` updated (compose content hash
changed — now includes the `infrared` service + `configs`), and
`terraform_data.redeploy` re-triggered (its `sha256(local.compose_content)`
changed).

- [ ] **Step 4: Confirm the container is up and the configs mounted**

```bash
ssh dokploy-prod 'docker ps --format "{{.Names}}\t{{.Ports}}" | grep -i infrared'
ssh dokploy-prod 'cid=$(docker ps -q -f name=infrared | head -1); \
  docker exec "$cid" cat /etc/infrared/config.yml; \
  docker exec "$cid" cat /etc/infrared/proxies/survival.yml'
```
Expected: a running infrared container publishing `25565/tcp`; `config.yml` shows
`bind: 0.0.0.0:25565`; `survival.yml` shows the real `survival.symbionic.tech`
domain and the i7's `100.x.y.z:25565` address (placeholders substituted, no
literal `${...}` remaining).

---

## Task 6: Verify end-to-end routing

Confirm the Linode host reaches the i7 over Tailscale, that Infrared loaded its
proxies, and that a real Minecraft client connects through to a server.

**Files:** none (operational).

- [ ] **Step 1: Confirm Infrared loaded the proxies (no `ErrNoServers`)**

Run: `ssh dokploy-prod 'docker logs "$(docker ps -q -f name=infrared | head -1)" 2>&1 | tail -20'`
Expected: `Starting Infrared` / `System is online`, and **no**
`No proxy configs found` fatal line. (That fatal would mean the `proxies/` mount
is empty — re-check Task 1 Step 1's `service.configs` targets.)

- [ ] **Step 2: Confirm the host can reach the i7's game port over Tailscale**

Run:
```bash
ssh dokploy-prod 'timeout 3 bash -c "cat < /dev/null > /dev/tcp/100.x.y.z/25565" && echo reachable'
```
(substitute the i7 IP and a port a Wings server is actually listening on)
Expected: `reachable`. (Confirms the host's `tailscale0` path to the i7 — the
same path the container egresses through. A failure here is a tailnet/ACL issue,
not an Infrared one: re-check SP1's `tag:mc-cloud -> tag:mc-compute` ACL and that
the Wings server is running.)

- [ ] **Step 3: Confirm DNS resolves the flat names to the Linode IP**

Run: `dig +short survival.symbionic.tech; dig +short creative.symbionic.tech`
Expected: both return the Linode host's public IP (via the existing `*.<tld>`
wildcard). No new DNS records are required — the wildcard already covers these
single-label names.

- [ ] **Step 4: Connect a Minecraft client end-to-end**

In the Java client, add a server with address `survival.symbionic.tech` (no port
— defaults to `25565`) and connect. Expected: the survival world loads. Repeat
with `creative.symbionic.tech` and confirm it lands on the creative server (the
hostname routes to the different backend port). While connected:

Run: `ssh dokploy-prod 'docker logs "$(docker ps -q -f name=infrared | head -1)" 2>&1 | tail -5'`
Expected: a log line for the proxied connection to the matching backend address;
no dial errors.

- [ ] **Step 5: Record the port-sync rule (the documented manual seam)**

Confirm the operator note in `linode/README.md` (Task 7) states: when a server is
added in the panel, add a matching `configs:` entry + `service.configs` mount in
`compose/docker-compose.yml` with the server's allocated i7 port, then re-apply
the dokploy environment. This is the architecture's accepted Infrared↔Wings
manual sync point.

---

## Task 7: Document the ingress in `linode/README.md`

Add a short operator subsection so the ingress path, the no-new-DNS fact, and the
manual port-sync seam aren't only in this plan (per the repo convention: describe
the pattern, not the plan).

**Files:**
- Modify: `linode/README.md`

- [ ] **Step 1: Add a "Public player ingress (Infrared)" subsection**

```markdown
## Public player ingress (Infrared)

Players reach the home Minecraft servers through `infrared`, a service in the
Dokploy stack that publishes raw TCP `25565` on the Linode host (the network
firewall opens that one port). Infrared reads the Minecraft handshake hostname
and forwards each stream over Tailscale to the matching Wings server port on the
i7 (`100.x`), reached through the host's `tailscale0`. One public port fans out
to many servers and the home IP is never exposed.

The routing table lives in `compose/docker-compose.yml` as inline Compose
`configs`: a `config.yml` (the `0.0.0.0:25565` listener) plus one
`proxies/<name>.yml` per server mapping a domain to an i7 address. The
`${HOSTNAME_TLD}` / `${I7_TAILSCALE_IP}` placeholders are filled by Terraform's
`templatefile()` at apply time, so no values or secrets land on the host.

No DNS records are needed for new servers: the existing `*.<tld>` wildcard
resolves the flat names (`survival.<tld>`, `creative.<tld>`) to the Linode IP,
and HTTP (`443`→Traefik) and Minecraft (`25565`→Infrared) are separated by port.

**Adding a server:** create it in the Pelican panel (note its allocated i7
port), then add a `configs:` entry plus a matching `service.configs` mount in
`compose/docker-compose.yml` and re-apply the `dokploy` environment. Keeping the
proxy addresses in sync with Wings' port allocations is a manual step at this
scale.
```

- [ ] **Step 2: Confirm markdown lints clean**

Run: `npx markdownlint-cli linode/README.md`
Expected: no errors (matches the repo's `.markdownlint.yml`).

---

## Out of scope (v1, YAGNI)

- Bedrock-edition ingress (UDP) — Java/TCP only.
- SRV records to let players omit `:25565` — flat names + wildcard only.
- Automated Infrared↔Wings port sync (the manual edit is the accepted seam).
- PROXY-protocol IP forwarding, rate-limiting filters, and Infrared's
  Docker/Redis config provider — the file-based config is sufficient at one node.
- Velocity/BungeeCord-style proxy network with hub-and-transfer.
```
