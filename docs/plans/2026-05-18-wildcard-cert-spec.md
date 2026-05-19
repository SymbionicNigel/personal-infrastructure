# Wildcard Cert via Default TLS Store

**Status:** Spec stub — awaiting full design pass. Captures the decision and direction; the step-by-step implementation plan is deferred until after the compose-module work ([2026-05-18-compose-module-spec.md](./2026-05-18-compose-module-spec.md)) lands.

**Goal:** Switch Dokploy's bundled Traefik from per-subdomain Let's Encrypt certs to a single wildcard cert covering `symbionic.tech` + `*.symbionic.tech`, using Traefik's default TLS store mechanism rather than per-router `tls.domains` labels.

---

## Why this is achievable

The Linode DNS-01 wiring is already in place via `linode/modules/dokploy-dns01/main.tf`:

- Scoped `domains:read_write` Linode token issued and rotated annually
- Traefik env pushed into Dokploy: `TRAEFIK_CERTIFICATESRESOLVERS_LETSENCRYPT_ACME_DNSCHALLENGE=true`, `..._PROVIDER=linode`, `..._RESOLVERS=1.1.1.1:53,8.8.8.8:53`
- Token injected as `LINODE_TOKEN` env so Traefik's lego client can authenticate

Wildcard certs require DNS-01; that's already the only challenge type configured. Switching to a wildcard is therefore a Traefik *config* change, not an infrastructure change.

---

## Design direction: default TLS store (not per-router labels)

Two patterns exist for requesting a wildcard cert in Traefik:

1. **Per-router `tls.domains` labels** on an anchor service. Simple but couples cert provisioning to a specific service's lifecycle.
2. **Default TLS store** via dynamic config (`tls.stores.default.defaultGeneratedCert`). Traefik provisions the wildcard at startup independent of any service, and reuses it for any router whose Host matches.

**Decision: pattern 2.** Reasoning:

- The DNS-01 wiring already happens at the `dokploy-dns01` module level — adding the default store at the same layer is a natural extension, not a new abstraction.
- Easy to verify success by inspecting the cert stored in the ACME backup bucket (one wildcard cert, not N per-host certs).
- Future frontend service will take the bare `symbionic.tech` apex *plus* its own subdomain — a wildcard cert covers both without per-service cert labels.
- Eventually a 404 page will catch unrouted `*.symbionic.tech` traffic, but until that exists, the wildcard cert with no explicit catch-all router prevents Traefik from accidentally serving unintended routes on undefined subdomains. The cert exists; routing still requires explicit Host rules.

---

## Implementation sketch (for the future full plan)

High-level shape — not a step-by-step plan, just enough to confirm direction:

1. **Extend `linode/modules/dokploy-dns01/`** (or split a sibling module) to push a Traefik *dynamic* config block in addition to the env. Likely uses the same SSH + tRPC API approach (`settings.writeTraefikDynamic` or equivalent — needs verification against current Dokploy API).
2. **Dynamic config content:**

   ```yaml
   tls:
     stores:
       default:
         defaultGeneratedCert:
           resolver: letsencrypt
           domain:
             main: symbionic.tech
             sans:
               - "*.symbionic.tech"
   ```

3. **Pre-step (manual or scripted):** SSH to the Dokploy host and delete `/etc/dokploy/traefik/dynamic/acme.json` to force a clean reissue. Per-host certs from the prior state aren't worth migrating.
4. **Post-step:** verify one wildcard entry appears in the ACME backup bucket; visit `https://janus.symbionic.tech` (or any subdomain) and confirm the served cert has `CN=symbionic.tech` with `*.symbionic.tech` SAN.
5. **Compose label simplification:** per-router `tls.certresolver: "letsencrypt"` labels can stay (no harm), but `tls.domains` labels are not added. The default store handles cert selection.

---

## Open questions (to resolve when writing the full plan)

- **Dokploy dynamic-config API surface.** Does Dokploy expose `settings.writeTraefikDynamic` analogous to `writeTraefikEnv`? If not, push the file to disk and let Traefik file-provider pick it up. Verify before designing the module changes.
- **Backup bucket layout.** The ACME backup module needs to confirm the new wildcard cert is captured. If the backup script targets specific per-host filenames, it may need adjusting for the wildcard's `acme.json` shape.
- **Sequencing with compose-module work.** This plan executes *after* `2026-05-18-compose-module-spec.md` is implemented. The compose file by then lives at `compose/docker-compose.yml` and the dokploy Terraform module reads its env via `germanbrew/dotenv`. Wildcard work doesn't touch those paths but should be aware they've moved.

---

## Out of scope

- Apex-domain HTTP redirect handling (e.g., `symbionic.tech` → `www.symbionic.tech`) — that's a routing decision, not a cert decision.
- Catch-all 404 router for undefined subdomains — explicitly deferred; the absence of this router is the safety mechanism preventing accidental routing.
- Multi-TLD support. Single `HOSTNAME_TLD` assumption is fine for the foreseeable future.
