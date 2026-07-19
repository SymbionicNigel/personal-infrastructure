# 13 — Deploy mc-router + end-to-end player routing

**What to build:** Apply the Dokploy Layer to roll out mc-router and confirm the whole ingress path works: the container publishes `25565`, the pool routes load, the flat names resolve via the existing wildcard, and a real Java client connects through `survival.<tld>` and `creative.<tld>` to the correct backend servers.

The MagicDNS decision gets its verification here. Backends are named (`mc-compute:25566`), and container DNS resolution of MagicDNS depends on the Host's `resolv.conf` — it is a known coin-flip. **Confirm the container itself resolves `mc-compute` and reaches the game port**; if it cannot, fall back to the literal `100.x` IP in `MAPPING` and record that the fallback is in force.

Also verify the two hardening decisions actually hold in the deployed container, since both are silent when wrong: unmatched hostnames are dropped at the Host (never dialling Tailscale), and the rate limiter is inert.

**Blocked by:** 11 (the service), 12 (the open port), 17 (servers on the pool ports to route to).

**Status:** ready-for-human — connecting a real Minecraft client is an operator step.

Source: ../spec.md (SP3 — ingress verification; wildcard DNS, no new records)

- [ ] Apply rolls out `mc-router`; container publishes `25565/tcp`
- [ ] Logs show the pool routes loaded, with no route pointing at a literal `${...}`
- [ ] The container resolves `mc-compute` via MagicDNS and reaches the game port over Tailscale — or the IP fallback is in force and recorded
- [ ] A Java client connects end-to-end to both `survival.<tld>` and `creative.<tld>`, each landing on the right backend
- [ ] A connection with an unmatched handshake hostname is refused at the Host (`Unable to find registered backend`) and never dials the i7
- [ ] `CONNECTION_RATE_LIMIT` is 60 in the running container and `DEFAULT` is unset
