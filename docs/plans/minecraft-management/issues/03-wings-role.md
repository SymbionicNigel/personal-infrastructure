# 03 — Wings role (authored, not yet converged)

**What to build:** A `wings` role that installs the Pelican Wings daemon on the i7: download the binary, write `/etc/pelican/config.yml` from a provided value, install and enable the systemd unit. The node config is produced later by the panel (ticket 08), so the role asserts loudly when the config is empty rather than converging with a broken node. Authored and lint-clean now; its live converge is the SP1↔SP2 seam handled in ticket 08.

**Blocked by:** 01 (needs the skeleton + the compute play in `site.yml`).

**Status:** ready-for-agent

Source: ../spec.md (SP1 — Wings role; node-token handoff is a documented risk)

- [ ] `wings` role (tasks, defaults, handlers, systemd unit template) authored; `ansible-lint` passes
- [ ] With no node config supplied, the role fails with a clear "create the node in the panel first" message
- [ ] `site.yml` syntax-check stays green with the role present
