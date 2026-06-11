# personal-infrastructure

This repository is the maintainer's personal infrastructure configuration.
It is published as a reference for anyone learning the same stack
(Linode + Dokploy + Terraform + chezmoi + Traefik), **not** as a
maintained product. Patterns are tuned for one specific deployment
target; copying the repo wholesale will not produce a working stack.
See [NOTICE](./NOTICE) for the full disclaimer and [LICENSE](./LICENSE)
(Apache-2.0) for terms.

## Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - astarte - FastAPI backend (Phoenician goddess of beauty; the public-facing presence of the Phoenician pantheon)
   - enki - gitlab
   - hendrix - traefik
   - iris - React Router v7 web frontend (Greek messenger goddess; rainbow personified, the visible link between gods and mortals)
   - janus - whoami (Roman two-faced god of beginnings, doorways, and transitions)
   - vulcan - dokploy console - Roman god of the forge, craftsmen, and builders
   - IN NEED OF SERVICE
     - mimir - Norse god of knowledge.  Good for observation or knowledgebase
     - selene - Greek moon goddess; the visible face of the night sky
     - ptah — Egyptian creator god and patron of craftsmen and architects.
     - inanna — Sumerian goddess of love and war, predecessor to Astarte/Ishtar. Keeps the Mesopotamian thread you started with Enki.
     - daedalus — the master craftsman and architect. Built the labyrinth, designed wings.
     - anubis — Egyptian guide of souls.

2. To run Traefik and use https run the following command to create tls certificates for https to work properly

   ```openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout traefik/local_certs/traefik-selfsigned.key -out traefik/local_certs/traefik-selfsigned.crt -subj "/CN=*.<desired_local_domain_name>"```

## Production runtime

Production services run on a single Linode host managed by
[Dokploy](https://dokploy.com), provisioned end-to-end by the Terraform
config under [linode/](./linode/README.md). Dokploy's bundled Traefik
handles routing and TLS; application services are defined in the root
`docker-compose.yml` and deployed as a `dokploy_compose` stack.

## Modules

1. [Linode](./linode/README.md) - Terraform based IAC
2. [Iris](./iris/README.md) - React Router v7 web frontend (Node, pnpm-managed)
3. [Astarte](./astarte/README.md) - FastAPI backend (Python, uv-managed)
4. [Scripts](./scripts/README.md) - Scripts for building and developing in personal-infrastructure

Required CLI packages and initializing commands:

<!-- TODO: give install commands, possibly adding a script -->
<!-- TODO: include links to documentation -->

- Docker / Docker Compose
- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [chezmoi](https://www.chezmoi.io/) — dotfile / secret management
- [GnuPG](https://gnupg.org/) — encrypts secrets handled by chezmoi
- [Bitwarden CLI (`bw`)](https://bitwarden.com/help/cli/) — unlocks the
  vault used by the GPG/SSH workflow
- [Linode-Cli](https://github.com/linode/linode-cli)
    - `linode-cli configure --token`
- [pnpm](https://pnpm.io/) — frontend package manager
- [uv](https://docs.astral.sh/uv/) — Python package + project manager (for `astarte/` and future Python services)
- node

## Future Decisions

Topics noted here are not yet implemented. Each is at the "decided to
defer, not decided how" stage; resolve before the relevant service or
demand makes it urgent.

### Remote access topology (Tailscale / Cloudflare Tunnel)

Today the apply host SSHes to the Dokploy instance via its raw public
IPv4, embedded in a generated `dokploy.sshconfig`. The Dokploy dashboard
is also reachable on `vulcan.<HOSTNAME_TLD>:443` publicly, gated only by
Dokploy's own login. Adding Tailscale (or Cloudflare Tunnel) would let
the firewall drop port 22 from the world, move the dashboard off the
public internet, and remove the "raw IP in checked-in config" liability.
Worth doing before any user-facing service exposes a real attack surface.

### Observability baseline

There is no log aggregation, metrics scraping, or external uptime
checking. `docker logs --tail` is the only debugging tool today. Plausible
first cut: Loki + Grafana (deployed as a Dokploy compose stack) for log
storage and dashboards, plus `blackbox_exporter` (or an external service)
hitting wildcard subdomains for uptime. Pick before the second service
ships, because correlating two services with no log store is painful. Also
wanted: error tracking (client + server) via a self-hosted Sentry/GlitchTip,
so iris's browser + SSR errors surface without grepping container logs.

### Persistent data tier

Most future services will need a SQL store. Likely shape: a single
host-resident Postgres (separate from `dokploy-postgres`), one schema or
database per service, shared backups. Per-service Postgres containers
multiply the backup matrix without much isolation benefit on a
single-host deployment. Decide concretely (instance type, version pin,
backup strategy) before the first DB-backed service lands.

### Billing alerts

Linode emits cost data but doesn't notify on spend spikes by default.
A budget alert configured in the Linode dashboard (or via the API) is a
small thing to wire up before anything that can scale costs unexpectedly
goes live.

### CDN / WAF in front

If/when a service has public traffic worth fronting, putting Cloudflare
(or an alternative — explicitly looking for non-Cloudflare options
when this comes up) between the world and Traefik buys DDoS smoothing
and caching. Today it would only add a moving part. Open question:
which provider; reluctance to add Cloudflare specifically without
evaluating alternatives.

### Dokploy version upgrade workflow

`DOKPLOY_VERSION` is pinned with a default in the production
environment's variables, so rebuilds are reproducible. Bumping it
requires editing the default and re-applying — there is no test of the
new version against the current compose stack before promotion. Fine
while upgrades are rare; codify a "stage on a throwaway env, then
promote" flow if the cadence ever picks up or a Dokploy release breaks
a service.
