# 09 — Object Storage backup key (Production Layer)

**What to build:** In the Production Layer, add a dedicated, non-rotating Linode Object Storage access key scoped to the existing `infra_backups` bucket, and surface its credentials (bucket, endpoint, region, access key, secret) as outputs. A separate key — not the acme/postgres key — keeps that key's 90-day rotation from breaking the Dokploy backup destination, which holds the credentials statically. The two Layers are separate state files, so this is an explicit credential handoff to ticket 10.

**Blocked by:** None — can start immediately.

**Status:** ready-for-human — the apply and reading the sensitive outputs for handoff are operator steps.

Source: ../spec.md (SP2 — volume backup to Object Storage)

- [ ] A dedicated `read_write` Object Storage key for the `infra_backups` bucket is added
- [ ] Five backup outputs (bucket, endpoint, region, access key, secret) are surfaced
- [ ] `terraform validate` passes; apply creates the key
