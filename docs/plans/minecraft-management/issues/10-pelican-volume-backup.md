# 10 — Pelican volume backup to Object Storage

**What to build:** Back up the panel's state nightly. Add a `dokploy_backup_destination` (the bucket from ticket 09) and a `dokploy_volume_backup` for `pelican-data` (the SQLite DB + `APP_KEY`-bearing `.env`). Credentials come from the dokploy env's chezmoi-managed `.env` as `TF_VAR_*`, matching how the API key is supplied. Verify a backup object lands in the bucket. (The dokploy provider is already at 0.4.0, so no version bump is needed.)

**Blocked by:** 07 (the compose stack must exist), 09 (the backup credentials).

**Status:** ready-for-human — copying the credentials into the encrypted env and triggering the backup are operator steps.

Source: ../spec.md (SP2 — volume backup to Object Storage)

- [ ] Backup destination + `pelican-data` volume backup resources added; backup vars declared
- [ ] The five `TF_VAR_*` backup credentials added to the Dokploy Layer's chezmoi `.env`
- [ ] `terraform validate` passes; apply creates both resources
- [ ] A triggered backup produces at least one `pelican-data` object in the bucket
