# Terraform - IAC

## Initialization & Bootstrapping

If initializing again, in CI, or for another project:

1. Install prerequisite cli tools
   1. Follow the instructions at the following link to install [terraform](https://developer.hashicorp.com/terraform/install#linux)
   2. Follow the instructions at the following link to install the [linode-cli](https://techdocs.akamai.com/cloud-computing/docs/install-and-configure-the-cli)
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

After bootstrap is complete, the full stack — Linode instance, DNS, Dokploy
admin/API key, and Dokploy projects/apps/domains — is deployed in two
independent stages, each with its own script in its environment directory.
The stages are designed to run as separate steps in a CI pipeline.

### Stage 1 — Production (Linode + DNS + Dokploy bootstrap)

```bash
cd linode/environments/production && bash production.sh
```

Performs:

- `terraform init` + `apply` — provisions Linode + DNS.
- The instance's `remote-exec` provisioner blocks until cloud-init completes;
  `local-exec` retrieves the Dokploy API key to
  `linode/environments/production/.dokploy-api-key`.
- Generates `linode/environments/dokploy/.env` (API key, S3 creds, and
  `HOSTNAME_TLD`) so the next stage has its inputs.
- Adds `production/.env` to chezmoi (encrypts into `.secrets/`).

### Stage 2 — Dokploy (projects, apps, domains)

```bash
cd linode/environments/dokploy && bash dokploy.sh
```

Performs:

- `terraform init` + `apply` against the `j0bIT/dokploy` provider — creates
  the `symbionic-services` project, the `janus` smoke-test app, and a
  Let's Encrypt domain at `janus.<HOSTNAME_TLD>`.
- Adds `dokploy/.env` to chezmoi.

### Subsequent changes

- **Dokploy config only** (new apps, domains, env vars): re-run Stage 2.
- **Application code**: push to GitHub — Dokploy redeploys automatically when
  the `dokploy_application` has `auto_deploy = true`.

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

This project uses **chezmoi with GPG encryption** for secrets management,
providing a git-based, encrypted approach that keeps sensitive data under
version control while maintaining security.

#### Secret Categories

Secrets are divided into two tiers:

**1. Bootstrap Secrets** (stored in chezmoi)

- `LINODE_TOKEN`: API token for creating infrastructure
- Terraform state files from bootstrap environment
- Required for initial infrastructure setup

#### Required Configuration Values

Environment-specific variables are managed through:

- **Environment files** (`.env`): Terraform variables (e.g., `TF_VAR_*`)
- **Backend configuration** (`backend.hcl`): S3 backend credentials and
  endpoints

Required configuration values:

1. `LINODE_TOKEN` - Linode API authentication
2. `HOSTNAME_TLD` - Base domain for infrastructure
3. `EMAIL_ADDRESS` - Administrative contact

#### Multi-Environment Support

The `environments/` directory structure supports multiple isolated environments:

- **bootstrap**: One-time setup for Object Storage backend
- **production**: Primary infrastructure deployment
- Additional environments (staging, dev) can be added as needed

Each environment maintains its own:

- State backend configuration
- Environment variables
- Terraform variable values
- Isolated infrastructure resources
