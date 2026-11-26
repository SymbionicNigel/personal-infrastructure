# Terraform - IAC

## Initialization & Bootstrapping

If initializing again, in CI, or for another project:

1. Install prerequisite cli tools
   1. Follow the instructions at the following link to install [terraform](https://developer.hashicorp.com/terraform/install#linux)
   2. Follow the instructions at the following link to install the [linode-cli](https://techdocs.akamai.com/cloud-computing/docs/install-and-configure-the-cli)
   3. Create a [Tailscale account](https://login.tailscale.com/start) — the
   production stack manages your tailnet as code (`module.tailnet`) and joins
   the Dokploy host to it. Then generate an OAuth client (Tailnet settings →
   Trust credentials → OAuth clients) scoped to Auth Keys (write), DNS (write),
   Policy File (write), Devices (read); `bootstrap.sh` prompts for its ID and
   secret along with `HOME_LAN_CIDR`.
2. Setup the Bootstrap env file
   1. Copy the .example.env file located in `environments/bootstrap/` to `environments/bootstrap/.env`
   2. Run the following command `linode configure --token` and replace the
   placeholder token in the new environment file.
   3. replace the bucket name and region with your desired values.
   4. Run the add secret script from the root of the project to add this .env to
     your secrets submodule.
     `bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt "./linode/environments/bootstrap/.env"`
3. Run script to bootstrap the backend for the main terraform managed environment.
`cd linode/environments/bootstrap && bash ./bootstrap.sh` This script will perform
the following operations.
   1. Run the terraform init and apply.
   2. Configure target environment's terraform module with the bootstrap terraform
   outputs.
   3. Add the following files to the secrets submodule:
      1. The bootstrap module's `.tfstate` and `.tfstate.backup`.
      2. The `.env` and `backend.hcl` files for the target environment's terraform
      module.

## Deploying Dokploy (Stages 1 + 2)

After bootstrap, the stack deploys in two independent stages — each runnable
as its own CI step. They are split because the upstream `j0bIT/dokploy`
provider needs `host` and `api_key` at plan time, so Dokploy must exist
before any `dokploy_*` resource can be planned.

### Stage 1 — Production

```bash
cd linode/environments/production && bash production.sh
```

Stands up everything the host needs to exist before Dokploy can be talked
to as a Terraform provider: the Linode instance, firewall, DNS zone,
wildcard records, ACME DNS-01 config, and the encrypted `acme.json` backup
job. The native backup schedule is configured in Stage 2.
DNS-01 is configured up-front (rather than relying on Dokploy's
default HTTP-01) so the dashboard's first cert issuance and any future
wildcard certs don't depend on port-80 reachability or DNS propagation
ordering.

The dashboard is bound to `<DASHBOARD_SUBDOMAIN>.<HOSTNAME_TLD>` by calling
the Dokploy admin API over SSH from the apply host, using the host's
`/root/.dokploy-api-key`. Bootstrap creates this key. The admin API is loopback-only
on the instance, which is why the call tunnels over SSH rather than going
through the provider.

`production.sh` also writes a generated `dokploy.sshconfig` + `id_ed25519`
keypair and idempotently appends an `Include` line to `~/.ssh/config` so
`ssh dokploy-prod` works from the apply host. Its host-key alias includes the
instance ID, so a replacement reusing the same IP has a distinct known-host
entry without deleting the old one. The instance's raw IP is
embedded there today; a bastion / Tailscale / Cloudflare Tunnel endpoint
is the intended replacement (see TODO in `base.tf`).

**In CI:** Production runs first. Deployments wait for approval on the `dokploy`
environment before Stage 2 plans and applies. PR plans are read-only and do not
require deployment approval. If Production replaces the VM, follow the
[recovery playbook](../docs/guides/dokploy-recovery.md) before approving.
The local SSH-config Include and initial chezmoi bootstrap remain local-only.

### Stage 2 — Dokploy

```bash
cd linode/environments/dokploy && bash dokploy.sh
```

Configures Dokploy itself: project, compose stack, and any Dokploy-side
domains. Routing is driven by Traefik labels in the root `docker-compose.yml`,
not by `dokploy_domain` resources — labels are the single source of truth
across local and prod so the same compose file describes both.

**Deploy lever:** each service's image is pinned by a `TF_VAR_<SERVICE>_IMAGE_TAG`
(e.g. `TF_VAR_ASTARTE_IMAGE_TAG`). CI sets it to the built commit SHA; for a
manual deploy, export it (or set it in `linode/environments/dokploy/.env`) before
`dokploy.sh`. The `latest` default is intentionally unused so deploys are
explicit and reproducible.

Stage 2 uses Production's `dokploy.sshconfig` to identify the Linode and install
the managed key. CI renders the same SSH config on its fresh runner. A new
Linode gets a registry login and deployment even if the image tags are unchanged.

### Control-plane backup/restore

The control-plane backup is Dokploy's native Web Server backup: a nightly
`pg_dump` of `dokploy-postgres` plus `/etc/dokploy`, zipped and uploaded to
`s3://<infra-backups>/<appName>/control-plane/`. It is created by
`module.control_plane_backup` (dokploy env) on the shared `linode-object-storage`
destination, schedule `0 4 * * *` UTC.

Use the [VM recovery playbook](../docs/guides/dokploy-recovery.md) to restore
through Dokploy's UI and resume CI.

The shared backup access key is owned alongside the bucket in Production.
The instance module receives the shared backup configuration for ACME recovery.
Stage 2 uses the same bucket/key for native backups. ACME and DNS-01 resources live alongside the VM and follow
its replacement lifecycle directly, without an instance-identity proxy or
repeated identity triggers. Terraform `moved` blocks in
`environments/production/moved.tf` preserve the existing key and host
configuration state. Routing depends on completion of the instance module,
including ACME restoration.

The application database is recreatable; no application-data restore is
required. No VM snapshot or second backup system is involved. Retain the source
archive until a post-restore backup is proven usable, including stored
credential decryption. Native archives are not GPG-encrypted; the separate
ACME backup is.

### GHCR pull credential

The astarte image (and any future GHCR-hosted service) is published to a
private GHCR namespace, so the Dokploy host needs `docker login`
credentials before a deploy can pull. This is owned by the **dokploy**
environment via `terraform_data.ghcr_registry`, which calls Dokploy's
`registry.create`/`registry.update` — Dokploy then runs `docker login
ghcr.io` on the host (writing `/root/.docker/config.json`). Re-runs when the
credential or Linode instance changes, so rotation and replacement are automatic.

Setup:

1. Generate a fine-grained PAT in GitHub
   (Settings → Developer settings → Personal access tokens → Fine-grained):
   - Repository access: this repo only
   - Permissions: `Packages: Read-only` (use a classic PAT with
     `read:packages` if the fine-grained token won't authenticate to GHCR)
   - Expiration: 1 year
2. Add it to the dokploy `.env` via chezmoi: `TF_VAR_GHCR_PAT=<pat>`. The
   username is the repo owner, supplied automatically by `dokploy.sh` as
   `TF_VAR_GHCR_OWNER`.
3. `terraform apply` the dokploy environment — the host is logged in.

Survives reboots. PAT rotation re-applies automatically on the next
`bash dokploy.sh` (the cred hash is a `triggers_replace` value).

## Rationale

This project uses a **hybrid approach** to Terraform state management that
balances self-hosting with managed services. It is based on a single cloud
solution with as many portions manages within git or terraform as possible.
Initially terraform cloud and hashicorp vault was considered for use as a
backend and secrets store, but between conception and implementation its
service structure changed and is no longer viable for a self-hosted
infrastructure.

### Bootstrap Environment (Local State)

The `environments/bootstrap/` directory uses **local state** to solve the
chicken-and-egg problem of creating infrastructure for state storage. This
environment:

- Creates a Linode Object Storage bucket for remote state
- Generates access keys with appropriate permissions
- Produces configuration files for production environments
- Requires no pre-existing infrastructure

### Production Environment (S3-Compatible Backend)

The `environments/production/` directory uses **Linode Object Storage** as an
S3-compatible backend. This approach was chosen because:

- **Self-hosted**: All infrastructure remains within Linode, avoiding
  multi-cloud dependencies
- **Cost-effective**: No additional services required (unlike AWS S3 + DynamoDB
  or GCP Cloud Storage)
- **Simple recovery**: State files are versioned and encrypted in Object Storage
- **Standard protocol**: Uses the S3 API, making migration paths straightforward
  if needed

### Secrets Management Architecture

Sensitive material is kept in git via **chezmoi + GPG**: source files are
encrypted into the `.secrets/` submodule, and each environment's `.env` /
`backend.hcl` is added the first time the corresponding script runs. The
guiding rule is that re-deriving an environment from scratch should require
only what is in chezmoi plus the bootstrap `LINODE_TOKEN` — no out-of-band
state.

Object Storage credentials are deliberately not threaded through `.env` for
provider auth: `provider "linode"` is configured with `obj_use_temp_keys`,
which mints short-lived obj keys per apply. The only long-lived obj key in
the system is the infra-backups key (Production root), shared by the
host's `acme.json` backup job and Dokploy's native backup destination. It is
not rotated: Dokploy stores the destination credentials statically and can't
track a rotation, so the key is kept stable.

The canonical list of inputs for the production environment is the file
[environments/production/variables.tf](./environments/production/variables.tf);
read it rather than re-listing here. Two callouts worth keeping out of
the code:

- `DOKPLOY_VERSION` is pinned with a default so rebuilds are reproducible;
  override via `TF_VAR_DOKPLOY_VERSION` only for one-off testing and bump
  the default when promoting a new version.
- `GPG_RECIPIENT` must be a key already in the apply host's GPG keyring;
  the ACME backup job encrypts to it before upload, so losing the
  corresponding private key means losing recoverability of `acme.json`.

#### Multi-Environment Support

The `environments/` directory is structured so additional environments
(staging, dev) can sit alongside `bootstrap`, `production`, and `dokploy`
with their own state backend, vars, and secrets. There is currently no
non-production environment — the split exists to keep that path open
rather than to serve a current need.
