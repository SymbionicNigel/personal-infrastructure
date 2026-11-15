# astarte wake-webhook auth — stub

Status: **stub, needs design.** Placeholder recording a deliberate pin taken during
the Minecraft management grilling session (2026-07-16). Not decomposed; no tickets
yet.

## The pin

`docs/plans/minecraft-management/` ticket 16 puts a wake endpoint on **astarte**:
mc-router POSTs `{"action":"up"|"down"}` when a player tries to join a sleeping
server, and astarte calls Pelican's client power API to start it.

Auth for that endpoint is pinned to a **static bearer token**, carried by
mc-router's `AUTO_SCALE_WEBHOOK_HEADERS` and checked against a chezmoi-managed
secret. That is a decision to defer, not a decision that this is right.

## Why it is tolerable for now

- The endpoint is **not exposed via Traefik**. mc-router reaches it by Docker
  service name on the Stack's network; it is not reachable from the internet.
- The caller and callee are both Services on the same Host, so the token never
  crosses an untrusted network.
- The blast radius of the token is bounded: it can start and stop game servers.

## Why it still needs design

- A static shared secret has no rotation story and no expiry.
- The token sits in the Stack's env alongside values with very different
  sensitivity.
- astarte is a *public-facing* Service. Today the wake route is unrouted by
  convention — nothing structurally prevents a future change from exposing it, and
  a bearer token is thin if that happens.
- astarte also needs a **Pelican client API key** to call the power API. That is a
  second long-lived credential with the same rotation gap, and it is strictly more
  powerful than the bearer token.

## Scope when picked up

Design auth for internal Service-to-Service calls on this Stack — this endpoint is
the first instance, not a special case. Worth deciding whether the answer is
per-caller credentials, mTLS, a signed payload, or simply "unrouted + a rotated
token is fine, written down."

Also settle rotation for the Pelican client API key, which the bearer-token
question does not by itself address.
