# Minecraft Management Platform — consolidated spec

Status: approved architecture, decomposed into `issues/`. This is the durable
record (context, decisions, risks, scope). The step-by-step implementation lives
in the numbered tickets under `issues/`; superseded per-sub-project plan docs were
removed in favour of this file (recoverable in git history if the granular steps
are ever needed).

## Problem

A self-hosted Minecraft game-server platform where the **management plane lives in
the cloud** (the existing Linode + Dokploy Host) and the **compute runs on local
hardware** at home (an i7-4xxx / 16 GB box). Players reach servers through a
**stable public hostname**; the home IP is never exposed. The home network is
joined to the cloud over **Tailscale**.

Scale: ~10 players, private, friends-only. Several decisions below only hold at
this scale and are marked where they do.

## Topology

```text
                    players (public internet)
                            |  TCP 25565
                            v
        +-----------------------------------------------+
        |   CLOUD  - existing Linode + Dokploy Host      |
        |   (host itself joined to the tailnet)          |
        |                                                |
        |   Traefik :443  -- daedalus.<tld> ------+      |  Pelican panel UI (HTTPS)
        |                                         v      |
        |   Pelican Panel  <- Dokploy compose stack      |
        |     + SQLite (volume)          ^               |
        |                                | power API     |
        |   mc-router :25565             |               |  routes by handshake host
        |     survival.<tld> -> mc-compute:25566         |
        |     creative.<tld> -> mc-compute:25567         |
        |        |  wake webhook          |              |
        |        +--------> astarte ------+              |  (all on the docker net)
        +----------------+-------------+------------------+
                         | Tailscale   | Tailscale
                         | (game data) | (panel->Wings API + game data)
                         v             v
        +---------------------------------------------+
        |   HOME LAN                                   |
        |   i7 box (on tailnet directly)               |
        |     Tailscale + Docker + Wings -> MC servers |
        |   Pi (Tailscale subnet router)               |  advertises 192.168.18.0/24
        +---------------------------------------------+
```

### Key flows

- **Management UI:** browser → `daedalus.<tld>` → Traefik (HTTPS, existing wildcard
  cert) → Pelican panel container (just another Dokploy Service).
- **Panel → Wings control:** the Pelican container reaches the i7's Wings API
  (`8080`) + SFTP (`2022`) over Tailscale, routed through the host's `tailscale0`.
  No per-container Tailscale sidecar.
- **Player game traffic:** flat name → Linode public IP → mc-router parses the
  Minecraft handshake hostname → forwards the TCP stream over Tailscale to the
  matching Wings container port on the i7. One public port, many servers, home IP
  hidden. An unmatched hostname is dropped at the Host and never reaches the
  tailnet.
- **Wake-on-connect:** a login attempt for a sleeping server makes mc-router POST
  `{"action":"up"}` to astarte; astarte calls Pelican's client power API to start
  the server. `{"action":"down"}` after idle. This hop never touches the tailnet —
  mc-router, astarte, and the panel are all Services on the same Docker network,
  addressed by service name. The only tailnet hop remains panel → Wings.
- **Provisioning:** Ansible push over Tailscale SSH converges the i7 (Tailscale +
  Docker + Wings) and the Pi (subnet router).

## Key decisions and rejected alternatives

- **Panel: Pelican**, not Pterodactyl / Pyrodactyl / Calagopus / MCSManager /
  PufferPanel. The Pelican family all drive the same Go daemon, **Wings**, on each
  node — so the cloud-control / local-compute split the project wants *is* the
  Wings architecture. Pelican is the actively developed, lightweight (SQLite, no
  Redis) successor by the ex-Pterodactyl core team; single-node is its sweet spot.
  Modded servers are supported via CurseForge Generic / FTB eggs. (Wings-family
  panels do not run arbitrary images like `itzg/minecraft-server`; they run
  Wings-managed containers via "eggs" — the itzg knowledge is convenient, not
  load-bearing.)
- **i7 directly on the tailnet AND a Pi subnet router.** The i7 carries the game
  data path (wants throughput + low latency) so it joins the tailnet directly. The
  Pi subnet-routes the home LAN so future LAN-only boxes need no Tailscale client
  of their own. Putting the Pi *in* the game path was rejected — it makes a Pi a
  gameplay dependency for no real gain.
- **Provisioning: push Ansible over Tailscale (Model A).** Mirrors how the Linode
  Host is provisioned (Terraform for declarative state + push). Pull-based GitOps
  (ansible-pull / chezmoi timer) and a dedicated always-on Pi controller were
  considered and deferred.

### Ingress proxy: mc-router

**mc-router** (`itzg/mc-router`), not Infrared, Gate, or Velocity. The first three
are all transparent handshake-hostname routers needing zero backend changes;
**Velocity stays rejected** as a full proxy-network tool requiring backend
forwarding config — overkill unless a true server network is wanted later. Among
the transparent options:

- **Infrared was rejected as abandoned.** Upstream `haveachin/infrared` last
  committed **2024-02-07**, and its newest tag is `v2.0.0-alpha.r2` — an alpha. The
  original plan's config shape (`config.yml` + `proxies/*.yml`) was the v2 layout,
  i.e. the only public ingress path pinned to a two-year-dead alpha.
- **Gate (`minekube/gate`) is healthy** (last commit 2026-07-13; 41 commits/90d;
  `v0.68.26`) and its Lite mode is an exact functional match — `Route{Host,
  Backend}`, transparent forwarding. Rejected because its advantages are a growth
  path to a real proxy network and Bedrock via Geyser, both explicitly out of scope
  here, while mc-router's advantage lands on a constraint we have today.
- **mc-router won on wake-on-connect.** Its `AUTO_SCALE_WEBHOOK_URL` works for
  statically-configured backends (not just Kubernetes), which is what makes 16 GB
  tractable. Healthy: last commit 2026-07-14, 24 commits/90d, `v1.44.0`.
- **Infrared's "Docker/Redis config provider" does not exist** and was never a real
  fallback for the port-sync problem. `docker`/`redis` appear in zero `.go` files
  in the v2 line; v1's `Docker` block is a *process manager* (start/stop a local
  container), not route discovery. Docker-based discovery is foreclosed here
  regardless: the proxy runs on the Host, the game containers run on the i7's
  daemon, and Wings does not let you label its containers.

**Pre-allocated port pool, not per-server route edits.** Routes are declared once
as a pool — `survival` → 25566, `creative` → 25567, plus spare slots — and
Pelican's node allocations hand out exactly those ports. Adding a server is then a
panel action on a pre-allocated port: no route change, no `terraform apply`, no
proxy restart, no dropping players on other servers. Routes only change when the
pool is exhausted. This is the decision that buys down the four-way agreement
between the ACL's `game_port_range` (`25565-25600`), Pelican's allocations,
mc-router's routes, and reality — drift there fails silently at the ACL with no log
on either end. Empty slots are harmless: a route with no backend just fails until
one appears.

**Routes as code in `MAPPING`, not on a volume.** mc-router can hold routes in a
watched file with a REST API that persists changes (`SaveRoutes` → `writeFile`),
escaping the deploy cycle entirely. Rejected: with the pool, routes change roughly
never, so the escape hatch buys nothing and would cost route drift out of git plus
a second volume backup. Revisit only if routes start changing often.

**Backends addressed by MagicDNS name, not a literal `100.x` IP.**
`tailscale_dns_preferences.magic_dns` is already true, so routes point at
`mc-compute:<port>` and survive an i7 rebuild or re-join. Removes the
`I7_TAILSCALE_IP` variable and its handoff step. Container DNS resolution of
MagicDNS depends on the Host's `resolv.conf` and is verified in ticket 13; the raw
IP is the documented fallback.

**No `Default` route.** mc-router drops any connection whose handshake hostname
matches no route (`Unable to find registered backend`, `connector.go:618`) at the
Host — it never dials Tailscale. Scanners connect to the bare IP, so their
handshake carries the IP literal and matches nothing: effectively all untargeted
abuse dies in the cloud. Setting `-default` would forward exactly that traffic to a
backend and undo it. This is the most important ingress hardening decision here,
and it is a knob we deliberately leave *unset*.

**`CONNECTION_RATE_LIMIT=60` — set high to make the limiter inert.** The default is
`1`, and the limiter **delays rather than drops**: `bucket.Take(1)` returns a wait
duration and the accept loop sleeps before `Accept()` (`connector.go:241`), on a
single global bucket (burst `rate*2`), *upstream* of route matching and the client
filter. At the default, a routine port scan is not blocked — it fills a FIFO queue
draining at 1/sec and starves real players, presenting as unexplained flakiness. It
is not a defense (an attacker just holds connections open); it is a liability. 60
is far above any plausible burst for ~10 players and low enough to remain a
backstop. It cannot be disabled — `server.go:101` clamps below 1 up to 1.

### Access control

**`online-mode=true` + a per-server username whitelist**, not proxy-level
filtering. mc-router's `CLIENTS_TO_ALLOW`/`DENY` are IP/CIDR only — useless for
friends on dynamic residential IPs. More fundamentally, a proxy-level username
filter would be **security theater**: the username in the login packet is
unauthenticated at the proxy, because Mojang session auth happens between the
client and the *backend*. Only the backend can authenticate a player, so that is
where the whitelist lives.

Net layering: **unknown hostname → dropped in the cloud; known hostname, unknown
player → authenticated and rejected at the box.** Someone who knows
`survival.<tld>` and is not whitelisted costs one TCP stream over Tailscale and a
login rejection — kilobytes, and not worth engineering against at this scale.

**Losing player IPs is a non-issue here.** Every connection reaches Wings from the
Host's tailnet address, so in-game IP bans would ban everyone — but a 10-person
username whitelist never needs IP bans. Username-based moderation is unaffected by
the proxy.

### Platform

- **Tailnet managed in Terraform** (`tailscale/tailscale` provider): ACLs, tagged
  auth keys, MagicDNS as code, consistent with the repo's IaC posture. Trust tags
  as built: `tag:dokploy` (Linode Host) → may reach `tag:mc-compute` (i7) on
  `8080`, `2022`, and the game-port range; `tag:mc-gateway` (Pi) advertises the
  home CIDR, auto-approved in the ACL.
- **Tailscale key expiry is not a silent-death risk.** Tagged devices carry no
  node-key expiry, and `key_expiry_seconds` bounds the *auth key's* usable
  lifetime, not the node's. Recorded because it is the kind of thing a future
  reader will reasonably worry about.
- **Naming:** the panel takes the unused god-name **`daedalus`** (master craftsman
  who built the labyrinth — apt for a world-building panel).
- **Pelican runs `BEHIND_PROXY=true`:** its bundled Caddy stays on plain HTTP `:80`
  (`auto_https off`); Traefik terminates TLS and routes to container port 80, like
  `astarte`/`iris`. (`SKIP_CADDY=true` is wrong here — it leaves only FastCGI on
  `:9000`, which Traefik cannot proxy.)
- **The wake webhook lives in astarte, unrouted.** mc-router POSTs to astarte by
  Docker service name; astarte calls Pelican's client power API. A dedicated
  Service was rejected as a Dockerfile, image, CI job, and Stack entry for ~40
  lines of handler. The endpoint is **not exposed via Traefik** — mc-router reaches
  it over the Docker network regardless, and a start/stop control surface has no
  business on the public API. Auth is a **bearer token** via
  `AUTO_SCALE_WEBHOOK_HEADERS` as a deliberate pin; real auth is designed
  separately (see `../astarte-wake-webhook-auth/`). Accepted cost: astarte becomes
  load-bearing for gameplay.

## Sub-projects (see `issues/` for the sliced work)

1. **Connectivity & local provisioning foundation** — the substrate. The
   tailnet-as-code, the shared `install-tailscale.sh`, and the i7/Pi first-boot
   bootstrap are **already built** on this branch; the remaining work is the
   `homelab/ansible/` convergence layer (tickets 01–04).
2. **Cloud management plane (Pelican)** — the panel as a Dokploy compose stack,
   SQLite on a volume, all env delivered via `dokploy_environment_variables`, node
   registration handing the Wings token to the Ansible `wings` role, panel volume
   backup (tickets 05–10) and world backups from Wings (ticket 15).
3. **Public player ingress (mc-router)** — one public TCP `25565` on the Host,
   fanning out to per-server Wings ports by handshake hostname over Tailscale;
   leans on the existing `*.<tld>` wildcard so no new DNS records are needed
   (tickets 11–13). Wake-on-connect is ticket 16; the add-a-server runbook is
   ticket 17; docs are ticket 14.

## Build order

1 → 2 → 3. The foundation must exist (tailnet + Wings on the i7) before the panel
can register the node, and servers must run before ingress has anything to route
to. The **node-token handoff** couples the tail of SP1 to SP2 (ticket 08).

## Risks

- **Wings node-token handoff** couples SP1 and SP2; build order handles it, but the
  `wings` role must treat the token as a provided input.
- **Wake-on-connect does not enforce capacity.** Nothing makes servers mutually
  exclusive — each route wakes independently, so two simultaneous logins to two
  heavy modded worlds can exceed 16 GB. It buys idle savings and works in practice
  because ~10 friends play one world at a time, but that is a convention, not a
  constraint. Containment is **per-server memory limits** in Pelican (enforced by
  Wings as Docker limits), so an overcommit kills one server's container rather
  than the box and Wings with it. Real exclusion would mean a scheduler in astarte
  that avoids evicting active players — deliberately out of scope. The operable
  consequence lives in the runbook (ticket 17): the sum of memory limits is the
  real constraint, tracked against 16 GB.
- **Wake UX is fail-then-retry, not seamless.** `WakeTimeout` defaults to 60s but a
  modded pack takes 2–5 min to bind its port (Minecraft binds the listener after
  world load), and the Minecraft client times out around 30s regardless. The first
  login attempt always fails; the wake fires anyway; a retry a few minutes later
  succeeds. Set `WAKE_TIMEOUT` ~300s and document the behaviour or it reads as a
  bug. `LoadingMOTD`'s usage string says "Docker servers", so it may not apply to
  webhook scaling — verify before promising a "waking" indicator.
- **Only a login attempt can wake a server**, never a status ping —
  `connector.go:577` gates waking on `nextState > mcproto.StateStatus`. Good:
  scanners pinging the server list cannot wake the box. But a login attempt is free
  to make, which is why `AUTO_SCALE_ALLOW_DENY` (by player uuid/name) is a day-one
  requirement of ticket 16, not a later addition. Note it is the one config that
  does **not** hot-reload — changing it needs a router restart.
- **astarte is a gameplay dependency** once it hosts the wake webhook. A resume
  backend outage becomes "nobody can start a world". Tolerable at this scale; a
  real seam between two otherwise-unrelated things.
- **Pelican on SQLite** is a deliberate lightweight choice; a busy multi-node
  future would want MariaDB + Valkey.
- **Tailscale relay path** adds one hop to player traffic. Tailscale establishes a
  direct peer-to-peer path where NAT allows, falling back to DERP otherwise;
  Minecraft's bandwidth is light enough that this is not a practical bottleneck.
  The cloud relay buys a stable public address and a hidden home IP, not speed.

## Out of scope (v1, YAGNI)

- A second Wings compute box / true multi-node.
- Pi-hosted monitoring (Prometheus / Grafana scraping Wings + hosts).
- Pull-based GitOps (ansible-pull / chezmoi timer) and an always-on Pi controller.
- A Velocity/BungeeCord server network with hub-and-transfer.
- **Bedrock-edition ingress (UDP)** — Java/TCP only for v1.
- SRV records to let players omit `:25565` — flat names + the existing wildcard.
- Headless/automated panel install — the one-time web installer is the chosen
  single manual touch.
- Mail delivery (`MAIL_DRIVER=log` default; no SMTP).
- GPG-at-rest for the volume backup — native Dokploy backup, bucket-side encryption
  only.
- **PROXY-protocol IP forwarding.** `UseProxyProtocol` exists, but it does not
  reject anyone earlier — it only tells the backend the true client IP, which we do
  not need (username whitelist). Worse, the backend must *speak* PROXY protocol and
  a vanilla Wings-managed server does not; enabling it would break every
  connection.
- **Proxy-level IP filtering** (`CLIENTS_TO_ALLOW`/`DENY`) — CIDR-only, useless for
  friends on dynamic IPs.
- **Mutual exclusion / a wake scheduler** — see the capacity risk above.
- **Real auth on the wake webhook** — bearer token is the pin; designed separately.
- Local-dev Pelican/mc-router beyond reachability (no Wings/Tailscale locally).

All are clean later additions this architecture does not preclude.
