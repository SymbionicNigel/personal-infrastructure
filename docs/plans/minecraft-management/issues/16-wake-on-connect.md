# 16 — Wake-on-connect (mc-router → astarte → Pelican)

**What to build:** Let a sleeping server start when someone tries to join, and stop when idle. This is what makes 16 GB hold more worlds than it can run at once.

Two halves:

1. **astarte** gains an unrouted `POST` endpoint that accepts mc-router's `{"action":"up"|"down"}` payload and calls Pelican's **client** power API (`/api/client/servers/{uuid}/power`) to start or stop the mapped server. **Not exposed via Traefik** — mc-router reaches it by Docker service name, and a start/stop control surface has no business on the public API. Auth is a bearer token, checked against a chezmoi-managed secret.
2. **mc-router** gains `AUTO_SCALE_WEBHOOK_URL` pointed at that endpoint, `AUTO_SCALE_WEBHOOK_HEADERS` carrying the token, `AUTO_SCALE_DOWN_AFTER`, and `AUTO_SCALE_ALLOW_DENY`.

Three things are not optional (see `../spec.md`):

- **`AUTO_SCALE_ALLOW_DENY` ships with the webhook, not after it.** Waking is gated on a *login attempt* (`connector.go:577`), which is free for anyone to make — so without a player allow-list, any stranger who knows a hostname can spin your box up. Note this is the one mc-router config that does **not** hot-reload; changing it needs a router restart.
- **`AUTO_SCALE_WEBHOOK_WAKE_TIMEOUT` ~300s.** The 60s default is far shorter than a modded pack's 2–5 min to bind its port.
- **Per-server memory limits set in Pelican.** Nothing enforces mutual exclusion — two simultaneous logins wake two servers. Limits are the containment: an overcommit kills one container instead of the box and Wings with it. The runbook (17) owns the RAM budget.

Two secrets, both operator-generated: the bearer token, and a Pelican client API key for astarte to call the power API. Both chezmoi-managed, same pattern as `APP_KEY`.

The bearer token is a **deliberate pin** — real auth is designed separately in `../astarte-wake-webhook-auth/`.

**Blocked by:** 13 (mc-router deployed and routing end-to-end), 17 (servers exist to wake).

**Status:** ready-for-agent for the endpoint + wiring; the two secrets are operator-owned.

Source: ../spec.md (wake webhook in astarte; capacity and wake-UX risks)

- [ ] astarte endpoint accepts the scale payload, requires the bearer token, and calls Pelican's client power API
- [ ] The endpoint is **not** reachable through Traefik; mc-router reaches it by service name
- [ ] `AUTO_SCALE_ALLOW_DENY` populated with the player allow-list at rollout — not deferred
- [ ] `AUTO_SCALE_WEBHOOK_WAKE_TIMEOUT` ~300s; `AUTO_SCALE_DOWN_AFTER` set
- [ ] Every server carries a memory limit; their sum fits the box with headroom
- [ ] A login attempt to a stopped server starts it; a retry a few minutes later connects
- [ ] A status ping does **not** wake a server; a non-allow-listed player does **not** wake one
- [ ] The server stops after the idle window with the world saved
- [ ] Confirm whether `LoadingMOTD` applies to webhook scaling (its usage string says "Docker servers") before documenting a "waking" indicator in 14
