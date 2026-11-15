# Citadel

Citadel is a self-hosted personal infrastructure: one live system, built up from sequential Terraform Layers on a single cloud host.

## Language

**Citadel**:
The running product-system as a whole — the self-hosted personal infrastructure that every Layer builds up to. There is exactly one, and it is live.
_Avoid_: production (that names a Layer, not the system), the platform, the homelab

**Layer**:
A Terraform root configuration with its own backend and state, applied in sequence to build up the Citadel.
_Avoid_: environment, stage

### Layers

**Bootstrap Layer**:
The Layer that provisions the preconditions for applying and iterating the Production Layer.
_Avoid_: init, stage 0

**Production Layer**:
The Layer holding the iterable cloud infrastructure and the body of the Citadel; the primary Layer.
_Avoid_: prod (prod refers to the live Citadel, never this Layer)

**Dokploy Layer**:
The Layer encompassing the systems and integrations that belong to the Dokploy instance itself.
_Avoid_: stage 2

### Runtime

**Host**:
The single Linode virtual machine that runs Dokploy and hosts the Stack. There is exactly one.
_Avoid_: server, box, node

**Stack**:
The full set of Services deployed together as one unit — locally via Docker Compose, in the Citadel as a single Dokploy compose deployment.
_Avoid_: app, project, deployment

**Service**:
A single application or dependency that runs as part of the Stack (e.g. astarte, iris, janus, postgres). A Service may be *routed* (reachable at its own subdomain via a Traefik Host rule) or *backing* (internal-only) — "routed" is a property, not a separate kind.
_Avoid_: app, microservice
