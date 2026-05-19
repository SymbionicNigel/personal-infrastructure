# AGENTS.md

## What this repo is

Self-hosted personal infrastructure on Linode, driven end-to-end by
Terraform. A single Dokploy host fronts every long-running service; routing
is handled by Dokploy's bundled Traefik. There is no Kubernetes, no managed
control plane, and no external state backend — bucket-stored TF state +
chezmoi-encrypted secrets are the recovery story.

Application services are defined as Docker Compose in the repo root and
deployed to Dokploy via `dokploy_compose`. The same compose file is
combined with `docker-compose.local.yml` for local development.

## Where to read before editing

Prefer per-directory documentation over guessing — these are kept current:

- [linode/README.md](./linode/README.md) — Terraform layout, bootstrap,
  Stage 1 / Stage 2 deploy, secrets architecture.
- [dotfile-utils/README.md](./dotfile-utils/README.md) — chezmoi + GPG
  secret workflow.
- [README.md](./README.md) — host-side setup (local hosts file, certs).

## Conventions worth knowing

- **No commits or pushes from agents.** The maintainer is the only one who
  commits. Stop at "changes ready"; do not run `git commit` or `git push`.
- **Secrets stay in `.secrets/`** (a submodule), encrypted via chezmoi +
  GPG. Never write a plaintext secret into the working tree, even
  temporarily. Use `dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt`.
- **Use `czm` instead of raw `chezmoi`** for any chezmoi operation in this
  repo. `czm` is a wrapper that points at this project's `.chezmoi.toml`
  and is sourced into the shell by the Bitwarden session script — run
  that script first, then `czm <subcommand>`.
- **Terraform state is remote** (Linode Object Storage, S3-compatible).
  Do not commit `.tfstate*` files; the bootstrap stage's state is the one
  exception and lives in `.secrets/` via chezmoi.
- **Routing source of truth is Traefik labels** in `docker-compose.yml`,
  not `dokploy_domain` resources.
- **Routing model is asymmetric between local and prod.** Locally, each
  service is reached at `http://localhost:<port>` via a published port
  in the local-override compose file — there is no local reverse proxy,
  so Traefik labels are inert metadata. In prod, each service is reached
  at `https://<service>.<HOSTNAME_TLD>` via Dokploy's bundled Traefik,
  which reads the labels and provisions Let's Encrypt certs. Same
  compose file describes both; only how traffic reaches the container
  differs.

## Common commands

| Task | Command |
|---|---|
| Local stack | `docker compose -f docker-compose.yml -f docker-compose.local.yml up -d` |
| Stage 1 deploy | `cd linode/environments/production && bash production.sh` |
| Stage 2 deploy | `cd linode/environments/dokploy && bash dokploy.sh` |
| SSH to prod host | `ssh dokploy-prod` (after Stage 1 has run on this machine) |
| Add an encrypted secret | `bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt <path>` |
