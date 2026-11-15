# 05 — Pelican compose service + local dev

**What to build:** Add the `pelican` service to the base compose stack (single container, `BEHIND_PROXY=true` so Traefik terminates TLS and routes to container port 80 at `daedalus.<tld>`), with its named `pelican-data` / `pelican-logs` volumes. Every env value is a `$${VAR}` reference so no value lands in the rendered compose content. Wire local dev: an override host-port mapping and `PELICAN_IMAGE_TAG` through the shared chezmoi compose-env partial so both `.env` and `.env.prod` pick it up.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

Source: ../spec.md (SP2 — Pelican as a Dokploy stack, BEHIND_PROXY mode)

- [ ] `pelican` service + top-level `volumes:` added; `docker-compose.yml` parses
- [ ] Every env key in the service is a `$${VAR}` reference (nothing templated in at apply time)
- [ ] `PELICAN_IMAGE_TAG` lands in both rendered `compose/.env` and `compose/.env.prod`
- [ ] `docker compose config` resolves with no unset-variable warnings
