# 06 — Pelican secrets + dokploy env wiring

**What to build:** Deliver every Pelican env value through a single `dokploy_environment_variables` resource (`create_env_file = true`) whose map merges the one true secret — `APP_KEY`, in a chezmoi-encrypted `.secrets/compose/pelican.env` — with Terraform-derived non-secret values (URLs, proxy CIDRs, `BEHIND_PROXY`). Add the `PELICAN_IMAGE_TAG` variable and thread it into the compose `templatefile()`. A committed `.example` documents the secret shape.

**Blocked by:** 05.

**Status:** ready-for-human — `APP_KEY` generation + creating the encrypted secret is operator-owned.

Source: ../spec.md (SP2 — env via dokploy_environment_variables; APP_KEY the only secret)

- [ ] `compose/pelican.env.example` committed; real `APP_KEY` secret created via chezmoi and tracked
- [ ] `dokploy_environment_variables.pelican` merges the decrypted secret with derived values
- [ ] `PELICAN_IMAGE_TAG` variable added and passed into the compose templatefile
- [ ] `terraform validate` succeeds in the Dokploy Layer
