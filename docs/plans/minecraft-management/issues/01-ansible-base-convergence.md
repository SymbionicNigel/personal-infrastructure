# 01 — Ansible base convergence layer

**What to build:** A `homelab/ansible/` push layer (from the operator's machine over Tailscale SSH) that converges a home box past "on the tailnet" into a provisioned baseline. Stand up the Ansible skeleton (config, inventory for `mc-compute` + `mc-gateway`, `site.yml`) and the base roles that run on every box: `common` (base packages + unattended-upgrades), `tailscale` (a thin wrapper that ships and runs the existing shared `install-tailscale.sh` — no duplicated join logic), and `docker`. After this, converging the i7 leaves it with Docker running and reachable.

**Blocked by:** None — can start immediately.

**Status:** ready-for-agent

Source: ../spec.md (SP1 — connectivity foundation; only the homelab/ansible layer remains)

- [ ] `homelab/ansible/` skeleton parses: `ansible-playbook site.yml --syntax-check` succeeds with the roles this ticket adds
- [ ] `common`, `tailscale`, `docker` roles authored; `ansible-lint` passes for each
- [ ] The `tailscale` role consumes the repo's shared `install-tailscale.sh` (symlinked in), not a copy
- [ ] Base roles converge the i7: it is reachable and Docker is enabled and running
- [ ] `site.yml` references only roles that exist at this ticket's completion (stays green)
