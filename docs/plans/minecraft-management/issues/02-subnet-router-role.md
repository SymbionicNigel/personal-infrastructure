# 02 — Subnet-router role (Pi gateway)

**What to build:** A `subnet-router` role that turns the Pi (`mc-gateway`) into a Tailscale subnet router for the home LAN: enable IPv4/IPv6 forwarding and advertise the home CIDR. Because the tailnet ACL auto-approves `tag:mc-gateway` routes, the advertised `192.168.18.0/24` route comes up **approved** with no manual click.

**Blocked by:** 01 (needs the Ansible skeleton + base roles + the gateway play in `site.yml`).

**Status:** ready-for-human — converge step needs the physical Pi on the tailnet.

Source: ../spec.md (SP1 — Pi subnet router; ACL auto-approves tag:mc-gateway routes)

- [ ] `subnet-router` role authored; `ansible-lint` passes
- [ ] Converging `mc-gateway` enables forwarding and advertises the home CIDR
- [ ] The route shows **approved** in `tailscale status` / the admin console with no manual approval
