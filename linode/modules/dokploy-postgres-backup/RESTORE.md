# Manual restore runbook

Daily encrypted `pg_dump`s land in `s3://<infra-backups-bucket>/dokploy-postgres/<UTC>.sql.gpg`. Restore is operator-driven.

## Prereqs

- Your laptop has the GPG private key matching `var.GPG_RECIPIENT`.
- `s3cmd` configured for the backups bucket (acme-backup already wrote `/root/.s3cfg` on the host; you can use a local config or `scp` that file down for one-shot use).
- SSH to the target instance as `symbionic_dokploy_user`.

## Steps

1. List backups, pick the one you want (newest by default):

   ```
   s3cmd ls s3://<bucket>/dokploy-postgres/
   ```

2. Stream decrypt → psql inside the container:

   ```
   s3cmd get --force s3://<bucket>/dokploy-postgres/<TS>.sql.gpg - \
     | gpg --batch --decrypt \
     | ssh dokploy-prod 'sudo docker exec -i dokploy-postgres psql -U dokploy -d dokploy --single-transaction -v ON_ERROR_STOP=1'
   ```

   The dump is taken with `pg_dump --clean --if-exists`, so it drops and recreates each table — safe to apply on top of a freshly-bootstrapped DB.

3. The restore wipes the bootstrap admin row and the API key that `user_data.sh` minted. Mint a fresh key against the restored admin:

   ```
   ssh dokploy-prod
   sudo bash
   COOKIE=$(mktemp)
   curl -sf -X POST http://localhost:3000/api/auth/sign-in/email \
     -H 'Content-Type: application/json' -H 'Origin: http://localhost:3000' \
     -c "$COOKIE" -d '{"email":"<ADMIN_EMAIL>","password":"<ADMIN_PASSWORD>"}'
   ORG=$(curl -s http://localhost:3000/api/auth/organization/list -b "$COOKIE" | jq -r '.[0].id')
   curl -s -X POST http://localhost:3000/api/trpc/user.createApiKey \
     -H 'Content-Type: application/json' -H 'Origin: http://localhost:3000' -b "$COOKIE" \
     -d "{\"json\":{\"name\":\"terraform\",\"rateLimitEnabled\":true,\"rateLimitTimeWindow\":3600000,\"rateLimitMax\":1000,\"metadata\":{\"organizationId\":\"$ORG\"}}}" \
     | jq -r '.result.data.json.key' > /root/.dokploy-api-key
   chmod 600 /root/.dokploy-api-key
   ```

4. Optional: purge orphaned api keys from the prior instance:

   ```
   sudo docker exec -i dokploy-postgres psql -U dokploy -d dokploy \
     -c "DELETE FROM apikey WHERE name = 'terraform' AND key != (SELECT key FROM apikey ORDER BY \"createdAt\" DESC LIMIT 1);"
   ```

5. Re-run `terraform apply` to reconcile anything that watches `/root/.dokploy-api-key` (e.g. `bind_dokploy_domain`).
