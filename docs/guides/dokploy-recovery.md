# Replace and restore the Dokploy VM

Use this runbook when a reviewed Production plan replaces the existing VM.

1. **Before replacement:** check the effective `DOKPLOY_VERSION` for the
   replacement ([Production default](../../linode/environments/production/variables.tf),
   unless overridden). If the existing host needs an upgrade, retain its
   pre-upgrade archive and upgrade it first. Confirm the running version
   matches the replacement, then run the existing **Web Server** backup with
   encryption keys included. Record the exact successful S3 object under
   `control-plane/` before provisioning proceeds.
2. **After replacement:** leave **Deploy Dokploy** waiting for approval.
   Production has provisioned the host; Stage 2 has not started its plan.
3. **Restore in the UI.** Sign in to the replacement dashboard with the
   bootstrap administrator. In **Web Server → Backups → Restore Backup**, select
   **Restore from infra-backups** and the exact archive from step 1.
   Wait for Dokploy's restore result. If the outcome is unclear, inspect it
   before starting another restore.
4. **Approve Deploy Dokploy.** Stage 2 authenticates with its existing managed
   key, sets Dokploy's server IP to the Linode address, installs the working
   key on the host, logs into the registry and deploys the stack.
   The archive must contain the managed key's record. If authentication fails,
   the deployment stops; don't repeat the restore just to retry a deployment.

Keep the source archive until a post-recovery backup has been proven usable.

[Dokploy's native backup and restore guide](https://docs.dokploy.com/docs/core/backups)
