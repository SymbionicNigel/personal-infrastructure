# Design: Minecraft Management Platform (architecture overview)

Date: 2026-06-14
Status: Approved architecture, pre-decomposition into sub-project specs

## Context

A self-hosted Minecraft game-server platform where the **management plane lives
in the cloud** (on the existing Linode + Dokploy host) and the **compute runs on
local hardware** at home (an i7-4xxx / 16 GB box). Players reach servers through a
**stable public hostname**; the home IP is never exposed. The home network is
joined to the cloud over **Tailscale**.

This document is the architecture overview. The work is decomposed into three
sub-projects, each of which gets its own spec -> plan -> build cycle (mirroring
the device-telemetry platform decomposition):

1. **Connectivity & local provisioning foundation** — the substrate.
2. **Cloud management plane (Pelican)** — the panel.
3. **Public player ingress** — how players reach servers.

### Hardware on hand

- **i7-4xxx, 16 GB** — the compute box. Runs Docker + the Wings daemon and all
  Minecraft server containers. On the tailnet directly (low-latency game path).
- **Raspberry Pi** — a Tailscale **subnet router** / management gateway so that
  *future* LAN-only compute boxes need no Tailscale client of their own. Kept out
  of the gameplay data path.
- (Spare Pis / Asus Tinker Board — unused in v1; candidates for later monitoring.)

## Key decisions and rejected alternatives

- **Panel: Pelican**, not Pterodactyl / Calagopus / MCSManager / PufferPanel.
  Pelican, Pterodactyl, Pyrodactyl, and Calagopus all drive the *same* Go daemon,
  **Wings**, on each node — so the cloud-control / local-compute split the project
  wants *is* the Wings architecture. Within that family Pelican is the actively
  developed, lightweight (SQLite, no Redis) successor by the ex-Pterodactyl core
  team, and single-node is its sweet spot. MCSManager / PufferPanel were the only
  options that preserve the maintainer's existing `itzg/minecraft-server` + compose
  workflow, but they are thinner as management planes; the itzg knowledge is
  convenient, not load-bearing, and modded servers are well supported on Pelican
  via the **CurseForge Generic** / FTB eggs (paste a modpack, it installs the
  loader). Wings-family panels do **not** run arbitrary Docker images such as
  `itzg/minecraft-server`; they run servers in Wings-managed containers via "eggs".
- **i7 directly on the tailnet AND a Pi subnet router.** The i7 carries the game
  data path, which wants throughput and low latency, so it joins the tailnet
  directly (the cloud relay then reaches it peer-to-peer where possible). The Pi
  subnet-routes the home LAN so additional future boxes can stay LAN-only. Putting
  the Pi *in* the game path (Pi as the only tailnet node) was rejected — Minecraft
  bandwidth is light, but it makes a Pi a gameplay dependency for no real gain.
- **Provisioning: push Ansible over Tailscale (Model A).** Mirrors how the Linode
  host is already provisioned (Terraform for declarative state + push). Pull-based
  GitOps (ansible-pull/chezmoi timer) and a dedicated always-on Pi controller were
  considered; both are deferred. The controller is kept abstract so a Pi control
  node is a later expansion, not a v1 bootstrap dependency.
- **Ingress proxy: Infrared**, not Velocity. Infrared is a transparent
  Minecraft-aware reverse proxy that routes by the hostname in the handshake packet
  with **zero backend changes**. Velocity is a full proxy-network tool
  (offline-mode + IP-forwarding, hub-and-transfer) — overkill unless a true server
  network is wanted later.
- **Tailnet managed in Terraform** (`tailscale/tailscale` provider): ACLs, tagged
  auth keys, MagicDNS as code, consistent with the repo's IaC posture.

## Topology

```
                    players (public internet)
                            |  TCP 25565
                            v
        +---------------------------------------------+
        |   CLOUD  - existing Linode + Dokploy host    |
        |   (host itself joined to the tailnet)        |
        |                                              |
        |   Traefik :80/:443  -- daedalus.<tld> --+    |  Pelican panel UI (HTTPS)
        |                                         v    |
        |   Pelican Panel  <- Dokploy compose stack    |
        |     + SQLite (volume)                        |
        |                                              |
        |   Infrared (MC proxy) :25565                 |  routes by handshake host
        |     survival.mc.<tld> -> i7(100.x):PORT_A    |
        |     creative.mc.<tld> -> i7(100.x):PORT_B    |
        +----------------+-------------+----------------+
                         | Tailscale   | Tailscale
                         | (game data) | (panel->Wings API + game data)
                         v             v
        +---------------------------------------------+
        |   HOME LAN                                   |
        |                                              |
        |   i7 box  (on tailnet directly)              |
        |     |- Tailscale client                      |
        |     |- Docker                                |
        |     '- Wings daemon --> MC server containers |
        |                                              |
        |   Pi  (Tailscale subnet router)              |  management gateway;
        |     advertises 192.168.x.0/24                |  future LAN-only boxes
        +---------------------------------------------+
```

### Key flows

- **Management UI:** browser -> `daedalus.<tld>` -> Traefik (HTTPS, existing
  wildcard cert) -> Pelican panel container. Pelican is just another Dokploy
  service.
- **Panel -> Wings control:** the Pelican container reaches the i7's Wings API
  (`8080`) and SFTP (`2022`) over Tailscale, routed through the Linode host's
  `tailscale0` interface. No per-container Tailscale sidecar.
- **Player game traffic:** `mc.<tld>` DNS A record -> Linode public IP -> Infrared
  on the Linode host parses the Minecraft handshake hostname -> forwards the TCP
  stream over Tailscale to the matching Wings container port on the i7. One public
  port, many servers, home IP hidden.
- **Provisioning:** Ansible push over Tailscale SSH converges the i7 (Tailscale +
  Docker + Wings) and the Pi (subnet router).

### Naming

The Pelican panel takes the unused god-name **`daedalus`** (master craftsman who
built the labyrinth — apt for a world-building panel). Subject to change.

## Sub-project 1 — Connectivity & local provisioning foundation

The substrate everything else stands on.

- **Tailnet as code** via the `tailscale/tailscale` Terraform provider: tagged
  auth keys, ACLs, MagicDNS. Trust tags:
    - `tag:mc-cloud` (Linode host) -> may reach `tag:mc-compute` on `8080`,
      `2022`, and game ports.
    - `tag:mc-compute` (i7) -> no outbound initiation required.
    - `tag:mc-gateway` (Pi) -> advertises `192.168.x.0/24`; route auto-approved
      in the ACL.
    - The **Linode host joins the tailnet here**, so sub-projects 2 and 3 reach
      the i7 by routing through the host's `tailscale0`.
- **i7 bootstrap:** one unavoidable local touch — flash Ubuntu LTS, run a
  bootstrap script that installs Tailscale (with the tagged auth key) + Docker.
  After it is on the tailnet, **Ansible push** (from laptop / CI over Tailscale
  SSH) converges the rest via roles: `common`, `tailscale`, `docker`, `wings`,
  `subnet-router`.
- **Ansible lives in a new top-level `ansible/` dir**, parallel to `linode/`.
- **Pi:** same bootstrap, then the `subnet-router` role — `--advertise-routes`,
  IP forwarding, ACL-approved route.
- **Coupling:** Wings' `config.yml` + token are generated by the panel when the
  node is created (sub-project 2). The `wings` role takes the token as an input;
  build order resolves the chicken-and-egg.
- **Secrets:** Tailscale auth key + Wings token to chezmoi/Bitwarden, `.env` +
  `.env.example` per repo convention.

## Sub-project 2 — Cloud management plane (Pelican)

- **Pelican as a Dokploy compose stack**, like the repo's other services.
  **SQLite + filesystem cache** (no MariaDB, no Redis) for the lightest footprint;
  the SQLite file lives on a Dokploy volume. Pelican's bundled Caddy is disabled;
  the panel runs **behind the existing Traefik** at `daedalus.<tld>` via labels
  (wildcard DNS + cert already cover the subdomain).
- **Reaches Wings over Tailscale** through the Linode host (sub-project 1).
- **Node registration** in the panel emits the Wings token, handed to the i7's
  Ansible `wings` role.
- **Secrets** (app key, admin creds) via chezmoi/Bitwarden + `.env` /
  `.env.example`.

## Sub-project 3 — Public player ingress

- **Infrared** as another Dokploy compose service on the Linode host, publishing
  **TCP 25565**. It reads the Minecraft handshake hostname and maps
  `survival.mc.<tld> -> i7(100.x):PORT_A`, `creative.mc.<tld> -> PORT_B`, …,
  forwarding the stream over Tailscale.
- **DNS:** lean on the **existing `*.<tld>` wildcard** -> Linode IP. With flat,
  single-label server names (`survival.<tld>`, `creative.<tld>`) the wildcard
  already resolves them and **no new records are needed** — Infrared routes by the
  handshake hostname, and HTTP vs. MC traffic is separated by port (443 -> Traefik,
  25565 -> Infrared), so the names coexist with existing services. (A DNS wildcard
  matches only one label, so *nested* names like `survival.mc.<tld>` would instead
  require one `*.mc.<tld>` wildcard record.) Optional per-server SRV records let
  players omit the `:25565` port. v1 uses flat names + no new records.
- **Linode firewall:** open inbound TCP 25565 (existing TF firewall module).
- **Known small-scale friction (documented, not solved):** Infrared's backend map
  must stay in sync with Wings' per-server port allocations — a manual edit when a
  server is added. Acceptable at this scale; automatable later.

## Build order

1 -> 2 -> 3. The foundation must exist (tailnet + Wings on the i7) before the panel
can register the node, and servers must run before ingress has anything to route
to. Within that, the node-token handoff couples the tail of sub-project 1 to
sub-project 2.

## Out of scope (v1, YAGNI)

- A second Wings compute box / true multi-node.
- Pi-hosted monitoring (Prometheus / Grafana scraping Wings + hosts).
- Pull-based GitOps (ansible-pull / chezmoi timer) and a dedicated always-on Pi
  controller.
- A Velocity/BungeeCord server network with hub-and-transfer.
- Bedrock-edition ingress (UDP) — Java/TCP only for v1.

All are clean later additions this architecture does not preclude.

## Risks

- **Wings node-token handoff** couples sub-projects 1 and 2; build order handles it
  but the Ansible `wings` role must treat the token as a provided input.
- **Infrared <-> Wings port drift** is a manual sync point per added server.
- **Tailscale relay path** adds one hop to player traffic (see "What this does and
  does not do" below); acceptable for the stable-address + hidden-IP benefit.
- **Pelican on SQLite** is a deliberate lightweight choice; a busy multi-node
  future would want MariaDB + Valkey.

## What this does and does not do for player latency

The cloud relay is for a **stable public address and a hidden home IP**, not speed.
Player traffic takes one extra hop (player -> Linode -> Tailscale -> i7) versus a
direct home port-forward. Tailscale establishes a direct peer-to-peer path between
the Linode host and the i7 where NAT allows, falling back to a DERP relay
otherwise; Minecraft's bandwidth is light enough that this is not a practical
bottleneck. The architecture trades a small, fixed latency cost for never exposing
the home IP and for multiplexing many servers behind one public port.
