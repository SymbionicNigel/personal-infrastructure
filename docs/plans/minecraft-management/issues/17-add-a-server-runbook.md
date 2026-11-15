# 17 — Add-a-server runbook (dry run: survival + creative)

**What to build:** The repeatable procedure for adding a Minecraft server, written down and exercised twice. `survival` and `creative` are the dry run; **the runbook is the deliverable.** Nothing else in the plan creates the servers, and three decisions from the architecture have nowhere else to live.

The runbook goes in `linode/README.md` (long-lived operator doc, referenced by ticket 14 rather than duplicated) and covers:

- **Pick a free pool port.** Allocations come from the pre-declared pool, inside the ACL's `game_port_range`.
- **Create the server in the panel** on that allocation.
- **`online-mode=true` + the username whitelist.** This is the entire access control story — the proxy cannot authenticate players, only the backend can.
- **Set the memory limit**, and check it against the **RAM budget**: nothing enforces mutual exclusion under wake-on-connect, so the *sum* of memory limits is the real constraint against 16 GB. The runbook is where that becomes operable — record the running total.
- **Pool exhaustion (the rare, expensive path):** expand `MAPPING` *and* the ACL's `game_port_range` **together**, then apply. Documented precisely because it is the one path that is easy to get half-right, and half-right fails silently at the ACL with no log on either end.

**The acceptance test for the pool decision lives here.** If adding `creative` needs no Terraform apply, no route edit, and no proxy restart, the pool paid for itself. If it doesn't, the pool decision was wrong and this is where we find out — cheaply, rather than in a year.

**Blocked by:** 08 (node registered and connected), 11 (the pool defined, so the ports are known).

**Status:** ready-for-human — panel UI work.

Source: ../spec.md (pre-allocated port pool; access control; capacity risk)

- [ ] Runbook written in `linode/README.md`: pool port → create → online-mode + whitelist → memory limit + budget
- [ ] Pool-exhaustion path documented as expanding `MAPPING` and `game_port_range` together
- [ ] `survival` and `creative` both exist on pool ports, whitelisted, with memory limits
- [ ] Adding the second server followed the doc with no deviation
- [ ] Adding the second server required **no** Terraform apply, **no** route edit, and **no** proxy restart
- [ ] The running RAM total is recorded and fits the box with headroom
