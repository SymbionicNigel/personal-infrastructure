#!/usr/bin/env bash

# Intended to be ran from /linode/environments/dokploy.
# Encryption of dokploy/.env into chezmoi is owned by production.sh (the
# script that creates it), matching the bootstrap.sh / production.sh pattern.
set -euo pipefail
set -a
# shellcheck source=/dev/null
source .env
set +a

terraform init -backend-config=backend.hcl
terraform apply -input=false -auto-approve
