# 04 — Homelab CI lint

**What to build:** A reusable `_homelab-lint.yml` workflow (shellcheck over `homelab/scripts/`, ansible-galaxy install, ansible-lint, and `site.yml --syntax-check`) wired into `ci.yml` behind a `homelab/**` path filter and added to the required `ci-gate` checks — matching the repo's per-service CI pattern and alphabetical key convention.

**Blocked by:** 01, 02, 03 — the `site.yml` syntax-check only passes once every referenced role (`common`, `tailscale`, `docker`, `subnet-router`, `wings`) exists.

**Status:** ready-for-agent

Source: ../spec.md (SP1 — convergence layer)

- [ ] `_homelab-lint.yml` runs shellcheck, ansible-lint, and syntax-check green
- [ ] `ci.yml` gains a `homelab` path filter + job, added to `ci-gate.needs`
- [ ] Both workflow files are valid YAML and keys are alphabetical per repo convention
