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
3. **Restore in the UI.** Open the replacement dashboard and sign in with the
   bootstrap administrator. Under **S3 Destinations**, register the existing
   backup bucket, endpoint, region and credentials. Go to **Web Server →
   Backups → Restore Backup** and select the exact archive from step 1.
   Wait for Dokploy's restore result. If the outcome is unclear, inspect it
   before starting another restore.
4. **Finish host recovery.** Sign in with the restored administrator. Update
   the address under **Web Server → Server → Update IP** if it changed, then
   reload Dokploy and Traefik. Confirm the expected projects, registry
   and backup destination are present. In the restored organization, create
   a host provisioning API key with the bootstrap rate limit (1,000/hour).
   On the replacement host, in an interactive Bash shell, install it without
   putting it in shell history:

   ```bash
   read -rs -p 'Host provisioning key: ' key
   printf '\n'
   printf '%s' "$key" | sudo -n install -m 0600 -o root -g root /dev/stdin /root/.dokploy-api-key
   unset key
   ```

   The restore overwrites the bootstrap key's database record. **Keep Stage
   2's managed key unchanged** if its record was restored.
5. **Approve Deploy Dokploy.** Stage 2 plans and applies any changes. Check
   workload health and HTTPS. Keep the source archive until a post-recovery
   backup has been proven usable.

If Stage 2 fails, address the failure and rerun the failed job. A Stage 2
retry does not require repeating a successful UI restore.

[Dokploy's native backup and restore guide](https://docs.dokploy.com/docs/core/backups)
