#!/usr/bin/env bash

# Intended to be ran from /linode/environments/production
set -euo pipefail
set -a
# shellcheck source=/dev/null
source .env
set +a

# Source Bitwarden session if available
PROJECT_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) \
        || { echo "Error: Not in a git repository"; exit 1; }
fi
if [ -f "$PROJECT_ROOT/.env.bitwarden" ] || [ -n "${BW_SESSION:-}" ]; then
    # shellcheck source=/dev/null
    source "$PROJECT_ROOT/dotfile-utils/scripts/source_bitwarden_session.sh" \
        || { echo "Error: Bitwarden session setup failed"; exit 1; }
fi

# Function to check if file is managed by chezmoi and add or merge accordingly
add_or_merge_to_chezmoi() {
    local file_path="$1"
    if chezmoi source-path --config ./.chezmoi.toml "$file_path" &>/dev/null; then
        echo "$file_path is already managed. Merging changes..."
        chezmoi merge --config ./.chezmoi.toml "$file_path"
    else
        echo "$file_path is not managed. Adding to chezmoi..."
        # shellcheck source=/dev/null
        source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt "$file_path"
    fi
}

terraform init -backend-config=backend.hcl
terraform apply -input=false -auto-approve

API_KEY_FILE="./.dokploy-api-key"

if [ ! -f "$API_KEY_FILE" ]; then
    echo "Error: API key file not found at $API_KEY_FILE"
    echo "The provisioner may not have run (instance already existed)."
    echo "To force re-provisioning: terraform taint module.dokploy-instance.linode_instance.dokploy_main"
    exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")

# Hand off to the dokploy stage by generating its .env
cat > "../dokploy/.env" << EOF
TF_VAR_DOKPLOY_API_KEY=$API_KEY
TF_VAR_HOSTNAME_TLD=$TF_VAR_HOSTNAME_TLD
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
EOF

# Move to root of repository to add files to secrets submodule
cd "$PROJECT_ROOT"

add_or_merge_to_chezmoi "./linode/environments/dokploy/.env"
