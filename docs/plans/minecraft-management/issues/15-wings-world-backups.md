# 15 — World backups from Wings to Object Storage

**What to build:** Back up the thing that actually matters. Ticket 10 backs up `pelican-data` — the panel's SQLite and `APP_KEY`, i.e. users, node registration, and server definitions. That is the cheap-to-recreate half. The **world data lives in Wings' data directory on the i7**, on a single consumer box with no disk redundancy. Without this ticket, a drive failure restores a panel that knows about two servers whose worlds are gone.

Configure Wings' S3 backup driver in `/etc/pelican/config.yml` (via the `wings` role) against the existing `infra_backups` bucket, reusing the dedicated Object Storage key from ticket 09 — no second key. Then set a backup schedule per server in the panel.

Credentials reach the i7 as role variables, not baked into the repo; the key itself is operator-generated per ticket 09.

**Blocked by:** 08 (Wings converged and the node connected), 09 (the backup credentials), 17 (servers exist to schedule backups for).

**Status:** ready-for-human — the credential handoff to the role and the panel-side schedules are operator steps.

Source: ../spec.md (SP2 — world backups; the panel volume backup is only half the story)

- [ ] Wings' S3 backup driver configured against `infra_backups` via the `wings` role
- [ ] The ticket-09 key is reused; no second Object Storage key is created
- [ ] A backup schedule exists for each server
- [ ] A triggered backup lands a world archive object in the bucket
- [ ] A restore is exercised once — an archive is pulled back and opens as a valid world
