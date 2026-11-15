# 12 — Open inbound TCP 25565 on the firewall

**What to build:** Add a `minecraft` inbound rule (TCP `25565`, all sources) to the existing network firewall module, matching the `http`/`https` rule style, and apply the Production Layer so the port opens. The rule lives on the firewall resource so it survives instance replacement.

**Blocked by:** None — can start immediately.

**Status:** ready-for-human — the production apply is an operator step.

Source: ../spec.md (SP3 — one public port on the host firewall)

- [ ] `minecraft` inbound TCP `25565` rule added to the network module
- [ ] `terraform validate` passes; apply updates the firewall in place
- [ ] State shows the `minecraft` rule live with `ports = "25565"`
