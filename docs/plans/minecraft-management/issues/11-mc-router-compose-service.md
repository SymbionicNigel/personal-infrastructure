# 11 — mc-router compose service + dokploy env vars

**What to build:** Add the `mc-router` service to the compose stack — unlike the HTTP services it has no Traefik labels and publishes raw TCP `25565` directly, forwarding each Minecraft handshake hostname to the matching Wings server port on the i7 over Tailscale. Routes are the **pre-allocated pool** (`survival` → `mc-compute:25566`, `creative` → `mc-compute:25567`, plus spare `mc1`..`mc3` slots), declared once as a single `MAPPING` env value so adding a server later needs no route change and no redeploy. Backends are **MagicDNS names**, not literal `100.x` IPs, so they survive an i7 rebuild. No host files, no compose `configs`, no `templatefile()` — `MAPPING` and the tuning values go through `dokploy_environment_variables` like every other env value.

Pool ports must sit inside the tailnet ACL's `game_port_range` (`25565-25600`) and match what Pelican's node hands out — the runbook (17) owns keeping those in step.

Two settings are load-bearing and are decisions, not defaults (see `../spec.md`):

- **`CONNECTION_RATE_LIMIT=60`** — the default of `1` *delays* the accept loop rather than dropping, so routine background scanning starves real players. Set high to make the limiter inert.
- **No `DEFAULT`** — leaving it unset is what makes mc-router drop unmatched hostnames at the Host instead of forwarding scanner traffic to a backend. Do not set it.

**Blocked by:** 05 (appended after the pelican block in compose).

**Status:** ready-for-agent

Source: ../spec.md (SP3 — mc-router ingress; pre-allocated pool; no Default route)

- [ ] `mc-router` service (no Traefik labels, publishes `25565/tcp`) added; YAML parses
- [ ] `MAPPING` declares the pool with MagicDNS backends; every port falls inside `game_port_range`
- [ ] `CONNECTION_RATE_LIMIT=60` set; `DEFAULT` unset; no `I7_TAILSCALE_IP` variable anywhere
- [ ] `MC_ROUTER_IMAGE_TAG` threaded through and landing in both rendered `compose/.env` and `compose/.env.prod`
- [ ] `docker compose config` resolves with no unset-variable warnings; `terraform validate` passes
