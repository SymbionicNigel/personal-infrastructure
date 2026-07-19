# Rename `linode/environments/` to match the "Layer" glossary term

Status: needs-triage

The domain glossary (`docs/CONTEXT.md`) now names the concept **Layer**, but the code still calls the directories `linode/environments/{bootstrap,production,dokploy}`. Resolve the code↔glossary drift by renaming to `linode/layers/` (or keep `environments/` and revise the glossary — decide at triage).

## Scope — pure rename + reference updates, no infra changes

Confirmed **no infrastructure changes, no `terraform apply`, and no state migration**: the remote state key lives in each Layer's `backend.hcl` as a literal (`key = "production.tfstate"`, `key = "dokploy.tfstate"`), independent of the directory path. Leave those `key` values untouched and state is unaffected.

It is **not** a bare `git mv`, though — sweep every path reference:

- **CI (functional — breaks if missed):**
  - `.github/workflows/ci.yml` — path filters (`linode/environments/dokploy/**`, `.../production/**`) and `working_directory:` values
  - `.github/dependabot.yml` — the three `environments/*` directory entries
  - `.github/workflows/_terraform-apply.yml` — example text in input descriptions
- **Scripts:**
  - `linode/environments/bootstrap/bootstrap.sh` — the `chezmoi add` source paths (`environments/production/.env`, `.../backend.hcl`, `.../dokploy/backend.hcl`, `.../bootstrap/terraform.tfstate*`) → these chezmoi-managed source entries move (a chezmoi re-target, not infra)
  - `dokploy.sh` / `bootstrap.sh` "intended to be run from …" comments
- **Docs:** `AGENTS.md` (deploy commands), `linode/README.md`, `homelab/README.md`

## Note

If renaming to `layers/`, also update AGENTS.md's "Stage 1 / Stage 2" deploy-step language, which conflates the deploy step with the Layer.
