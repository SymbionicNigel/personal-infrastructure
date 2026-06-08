#!/usr/bin/env bash

# Intended to be ran from /linode/environments/dokploy.
# Encryption of dokploy/.env into chezmoi is owned by production.sh (the
# script that creates it), matching the bootstrap.sh / production.sh pattern.
set -euo pipefail
set -a
# shellcheck source=/dev/null
source .env
set +a

# Owner of this repository drives the GHCR image namespace. CI provides it
# directly; locally `gh repo view` resolves it from the origin remote.
# Lowercased because GHCR paths must be lowercase.
OWNER="${GITHUB_REPOSITORY_OWNER:-$(gh repo view --json owner --jq '.owner.login')}"
: "${OWNER:?could not determine repo owner (set GITHUB_REPOSITORY_OWNER or run gh auth login)}"
export TF_VAR_GHCR_OWNER="${OWNER,,}"

terraform init -backend-config=backend.hcl
terraform apply -input=false -auto-approve
