# 08 — Register Wings node + converge the i7 (SP1↔SP2 seam)

**What to build:** Close the loop between the panel and the compute box. Create the Wings node in the panel pointing at the i7's Tailscale IP over HTTP (daemon `8080`, SFTP `2022`, game-port range matching the ACL), copy the generated node config, and run the `wings` role (ticket 03) with that config to converge the i7. The node then shows **connected** in the panel and the panel reads its resource stats over Tailscale.

**Blocked by:** 03 (the wings role must exist), 07 (the panel must be live to mint the node config).

**Status:** ready-for-human — node registration and the live converge with the emitted token are operator steps.

Source: ../spec.md (build order + node-token handoff risk)

- [ ] Node created in the panel against the i7's `100.x` Tailscale IP over HTTP
- [ ] `wings` role converged with the panel-emitted config; `systemctl status wings` active
- [ ] Node shows connected (green heartbeat); panel resource stats populate over Tailscale
