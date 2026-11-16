# Dokploy upgrade and rebuild readiness

## Scope and evidence

Source-only review, 2026-11-15. Repository baseline: master [`a941a7e`][baseline] (#64). Dokploy source: **v0.31.2**, commit [`a16cf893`][upstream]. No production connections, credential materialization, state-backed plans, installs, or workflow dispatches were performed. This note is preparation, not execution approval or a readiness certification.

The reported successful [deployment run 43757554315][run] is supplied context, not independently inspected operational evidence. It does **not** establish that the host or Dokploy was upgraded. Installed OS/package/kernel/Docker/Dokploy/Traefik versions, actual schedules, archive contents, and recovery success remain unverified.

## Confirmed source findings

### Existing-host changes and bootstrap are different operations

- The declared new-host target is Dokploy **v0.31.2**. Bootstrap uses its release-specific installer and pins Docker packages, but the instance ignores changes to `metadata`. Changing these declarations therefore does not rerun cloud-init or upgrade an existing instance. A successful Terraform apply is not an installed-version inventory. [Version][version], [installer/package pins][bootstrap-install], [metadata lifecycle][instance].
- Upstream `settings.updateServer` has no target-version input: it discovers an update and asynchronously requests `dokploy/dokploy:${data.latestVersion}`. It is not a pinned-v0.31.2 upgrade operation or a completion/health gate. [Upstream update route][update-route].
- Current CI converges production, then Dokploy/application resources. It has no dedicated in-place Dokploy upgrade, host package maintenance, or reboot operation. Its reusable apply runs only when the Terraform plan reports changes; it cannot be treated as an unconditional maintenance action. [Orchestrator][ci], [apply gating][apply-ci].

### Fresh-host bootstrap

- The prepared [instance module](../../linode/modules/dokploy/main.tf) connects as the deploy user with noninteractive sudo. [Bootstrap](../../linode/modules/dokploy/user_data.sh) establishes that user's sudo access before installing its SSH key and disabling root SSH.
- The waiter uses `set -eu`; cloud-init failure/degraded status and a missing/empty API-key sentinel fail provisioning. Rendered shell syntax, bootstrap ordering, and five mocked waiter cases pass locally. This is not a completed replacement-host test.

### Restore must precede final credential and resource handoff

- The prepared [production wrapper](../../linode/environments/production/production.sh) stops CI when provisioning has produced a new-host API-key file, preventing that run from continuing with stale Stage 2 credentials. It does not transport the key or restore the control plane. Existing-host CI still exits before the local developer `.env`/secret-sync flow. The first-run stop is not a durable restore-complete gate for later runs.
- Bootstrap creates a new admin/organization/API key. Control-plane restore replaces `/etc/dokploy` and drops/recreates the Dokploy database, bringing back the archive's accounts, API-key records, and resource IDs. The bootstrap key normally ceases to exist in that restored database; its `/root/.dokploy-api-key` sentinel is outside the restored tree and must not be mistaken for a valid post-restore credential. [Bootstrap key creation][bootstrap-key], [restore implementation][restore], [API-key storage][apikey-schema], [authentication lookup][auth].
- Use bootstrap credentials only for fresh-host preparation/restore. After restore, reconcile the restored project/compose/destination IDs with the existing Stage 2 Terraform state and supply a validated restored key or deliberately created post-restore key through the approved secret handoff. Do not deploy fresh Stage 2 resources first and expect their IDs/key to survive restore.

### Application backup defect is future-readiness work, not a current rebuild blocker

- `app_db_backup` sends `databaseType: postgres` with `composeId` and `serviceName`, but omits **`backupType: compose`** and **`metadata.postgres.databaseUser`**. Upstream defaults `backupType` to `database`. The scheduler's database branch requires a related native `postgres` resource, which this compose-only payload lacks; it does not fall through to compose handling. Thus a schedule created unchanged from this declaration on v0.31.2 does not run an application backup. Even with the type corrected, PostgreSQL compose command generation requires the missing metadata. This confirms a declaration defect, not the live schedule's actual contents or backup history. [Caller][backup-caller], [schema/defaults][backup-schema], [scheduler][scheduler], [command generation][backup-command].
- Correcting the payload alone does **not** repair an existing schedule: the module matches only `databaseType` + `prefix` and creates only when absent, without update/reconciliation. Upstream `backup.update` accepts metadata but not `backupType` or `composeId`, so it cannot convert a malformed record. [Module][backup-module], [update schema][backup-update], [update route][backup-update-route].
- **Future adoption, not implemented:** inventory the exact record/references/archive locations; review a correctly typed replacement and module identity/reconciliation change, validate it before enabling, then retire the old schedule without duplicate active jobs or lost archive discoverability. Do not silently delete/recreate based solely on prefix matching. This work is not a prerequisite for the current data-free application rebuild.

### Application PostgreSQL is recreatable

- The repository declares **no current business/user-data model**: Astarte's registry has no table classes, its baseline migration is empty, and its only routes are health checks (`SELECT 1` for DB readiness). Iris's generated schema contains only `alembic_version`; no application DB writes were found in `iris/app`. [Models][models], [baseline migration][migration], [routes][app], [generated schema][iris-schema].
- The user explicitly confirms **there is no production application data to preserve**, including manually added content. Application PostgreSQL roles/schema and Alembic baseline state can be recreated from source and approved credentials. No application-data restore is required for this rebuild. This conclusion uses the user's confirmation, not a live database inspection. [Role/schema reconciliation][roles], [migration][migration].

### Control-plane backup and cryptographic continuity remain essential

- Native web-server backup dumps `dokploy-postgres` and copies `/etc/dokploy` into a ZIP. It is not a general Docker-volume backup: the application's `postgres-data` named volume is outside that tree. Some bind-mounted content beneath `/etc/dokploy` can be included, so this is not equivalent to “configuration files only.” [Backup implementation][web-backup], [base path][paths], [application volume][volume].
- On v0.31.2, `includeEncryptionKey` defaults to **true**. Backup excludes any existing `encryption.key`, then writes `filesystem/encryption.key` from `exportEncryptionKeys()` when enabled. The file contains derived decryption keys, not the raw authentication secret; treat the archive as sensitive credential material. Do not infer this file exists in an older installed version's archive. [Schema][backup-schema], [archive assembly][web-backup], [key export][encryption].
- Encryption uses `ENCRYPTION_KEY` when configured, otherwise `BETTER_AUTH_SECRET`; restored file keys are a decryption fallback. A different new-host auth secret is not automatically interchangeable with old credentials, and a derived-key archive is not a backup of all raw authentication/Docker secrets. Recoverability needs an explicit auth/decryption credential plan, not an assumption based on a newly generated host secret. [Key derivation/fallback][encryption], [auth-secret resolution][auth-secret], [dedicated-key resolution][encryption-secret].
- **Second-generation backup hazard:** `exportEncryptionKeys()` exports current configured keys, **not restored fallback keys**. The backup copier excludes the restored `encryption.key` before writing that export. A post-restore backup can therefore omit keys still needed by unchanged old ciphertext. Even `encryptValue()` leaves already-encrypted values unchanged. Retain the original recovery keys/archive until preservation or complete re-encryption and another recovery cycle are verified. [Export, restored-key loading and encryption behavior][encryption], [archive exclusion/replacement][web-backup].
- `/etc/dokploy` includes Traefik/ACME state; the repo also declares a separate GPG-encrypted ACME backup. The current recovery requirement is the control-plane archive/configuration, required auth/decryption credentials, and usable ACME recovery material. No archive or GPG recovery was inspected here. [Paths][paths], [ACME backup][acme].

### Replacement changes routing before restore

- Production wires the instance IP directly into apex and wildcard DNS records, DNS-01 configuration and dashboard binding. Replacement can therefore move public routing as part of Stage 1, before control-plane restore is complete. The new-host CI stop prevents same-run Stage 2 continuation, but no durable restore-complete gate exists for later runs. [Production dependencies][production], [DNS records][dns], [CI ordering][ci].
- A rebuild needs an explicit maintenance/cutover decision and a hold on Stage 2 and competing deployments until restored control-plane identity, keys and routing are validated. Do not invent a duplicate rehearsal environment or assume existing CI provides a safe staged cutover.

## Recommended preparation and execution order

1. **Before execution approval:** review the prepared bootstrap/status changes, design post-restore key/ID handoff and durable CI maintenance holds, and prepare a separately reviewed pinned upgrade/host-maintenance operation. Keep `j0bIT/dokploy` **0.4.0**; this research is not a provider-upgrade proposal. Preserve the approved Timescale report-only scan deferral. [Provider pin][provider], [current report-only policy][scan].
2. **During a separately authorized inventory window:** record installed versions, service images, raw-secret configuration requirements without disclosing values, actual control-plane backup schedules, and archive provenance. Source declarations and #64's successful run cannot establish those operational facts.
3. **Establish recovery first:** validate the control-plane archive, authentication/decryption continuity and ACME recovery; protect the original key/archive chain. Application PostgreSQL will be recreated, per the user's confirmation that no application data needs preservation.
4. **In-place route:** review the inventoried-to-target upgrade path and recovery boundary; use an explicitly pinned target rather than `settings.updateServer`. Separate Dokploy upgrade from host package/kernel/Docker maintenance and reboot, checking control-plane access, decryption, workload health and routing between operations. Metadata edits and an ordinary Terraform apply do not perform these steps.
5. **Eventual rebuild route:** hold automatic Stage 2/deploys, enter the approved cutover window, provision the replacement through repaired bootstrap, restore the control plane, validate restored identities/credentials and complete final handoff. Release Stage 2 only after those gates, recreate declared application DB state, then check routing, health and a fresh recoverable control-plane backup, including the second-generation key issue.

No live inventory, schedule repair, maintenance operation, restore, cutover or rebuild is authorized or performed by this note.

## Prepared changes on this branch

- The cloud-init waiter connects as the deploy user and uses noninteractive sudo. Bootstrap establishes that user's sudo access before installing its SSH key and disabling root SSH.
- The waiter exits on either cloud-init failure or a missing/empty API-key sentinel. Local mocked checks cover success, cloud-init failure/degraded status, and sentinel failure.
- Production CI stops after provisioning a new host rather than proceeding with stale Stage 2 credentials. Restore and final credential handoff remain explicit operations; no automatic restore or new secret transport was introduced.
- These changes are not a tested rebuild or an in-place upgrade implementation. A reviewed state-backed CI plan and the control-plane recovery/cutover work above remain necessary.

## Pinned sources

[baseline]: https://github.com/SymbionicNigel/personal-infrastructure/commit/a941a7e40dbd2e330f40be45b34f9a3bce56dc54
[upstream]: https://github.com/Dokploy/dokploy/commit/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa
[run]: https://github.com/SymbionicNigel/personal-infrastructure/actions/runs/43757554315
[version]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/environments/production/variables.tf#L48-L52
[instance]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy/main.tf#L58-L82
[bootstrap-install]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy/user_data.sh#L92-L125
[bootstrap-ssh]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy/user_data.sh#L66-L90
[bootstrap-key]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy/user_data.sh#L127-L207
[handoff]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/environments/production/production.sh#L62-L120
[ci]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/.github/workflows/ci.yml#L107-L140
[apply-ci]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/.github/workflows/_terraform-apply.yml#L11-L49
[provider]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/environments/dokploy/main.tf#L1-L6
[backup-caller]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/environments/dokploy/main.tf#L216-L247
[backup-module]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy-scheduled-backup/main.tf#L43-L85
[production]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/environments/production/base.tf#L48-L135
[dns]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/domain/main.tf#L18-L32
[scan]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/.github/workflows/_build-push.yml#L55-L72
[acme]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/linode/modules/dokploy/user_data.sh#L215-L320
[volume]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/compose/docker-compose.yml#L102-L132
[models]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/astarte/src/astarte/db/models.py
[migration]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/astarte/alembic/versions/0001_baseline.py
[app]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/astarte/src/astarte/main.py#L53-L75
[iris-schema]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/iris/app/generated/schema.ts
[roles]: https://github.com/SymbionicNigel/personal-infrastructure/blob/a941a7e40dbd2e330f40be45b34f9a3bce56dc54/postgres/scripts/reconcile-roles.sql#L33-L60
[update-route]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/apps/dokploy/server/api/routers/settings.ts#L628-L660
[restore]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/utils/restore/web-server.ts#L53-L131
[apikey-schema]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/db/schema/account.ts#L257-L282
[auth]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/lib/auth.ts#L633-L683
[backup-schema]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/db/schema/backups.ts#L35-L104
[scheduler]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/utils/backups/utils.ts#L16-L54
[backup-command]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/utils/backups/utils.ts#L186-L200
[backup-update]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/db/schema/backups.ts#L212-L229
[backup-update-route]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/apps/dokploy/server/api/routers/backup.ts#L217-L280
[web-backup]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/utils/backups/web-server.ts#L55-L109
[paths]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/constants/index.ts#L124-L148
[encryption]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/lib/encryption.ts#L19-L102
[auth-secret]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/lib/auth-secret.ts#L1-L28
[encryption-secret]: https://github.com/Dokploy/dokploy/blob/a16cf89389f1bcb6fb5b9a78f7e8a28150c5efaa/packages/server/src/lib/encryption-secret.ts#L1-L15
