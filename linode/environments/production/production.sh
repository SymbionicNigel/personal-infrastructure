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

# TF_DETECT_CHANGES=true (CI plan job) runs plan with -detailed-exitcode and
# propagates terraform's rc (0 none, 2 changes, 1 error) for the apply gate.
if [ "${TF_DETECT_CHANGES:-false}" = "true" ]; then
    set +e
    terraform plan -input=false -detailed-exitcode
    rc=$?
    set -e
    exit "$rc"
fi

# TF_PLAN_ONLY=true is a read-only plan for local use; skips apply + bootstrap.
if [ "${TF_PLAN_ONLY:-false}" = "true" ]; then
    terraform plan -input=false
    exit 0
fi
terraform apply -input=false -auto-approve

# Remaining steps are local-developer bootstrap (SSH config Include, handing the
# provisioned API key to the dokploy stage, syncing it into chezmoi). CI runners
# set CI=true and are done after the apply.
if [ -n "${CI:-}" ]; then
    exit 0
fi

# Make `ssh dokploy-prod` work for this user by adding a one-line Include to
# ~/.ssh/config that points at the terraform-generated dokploy.sshconfig.
# Idempotent: only appended once per user.
SSH_CONFIG="$HOME/.ssh/config"
SSH_SNIPPET="$(pwd)/dokploy.sshconfig"
mkdir -p "$HOME/.ssh"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
INCLUDE_LINE="Include $SSH_SNIPPET"
if ! grep -Fxq "$INCLUDE_LINE" "$SSH_CONFIG"; then
    printf '\n# Added by personal-infrastructure production.sh\n%s\n' \
        "$INCLUDE_LINE" >> "$SSH_CONFIG"
    echo "Added Include for $SSH_SNIPPET to $SSH_CONFIG"
fi

API_KEY_FILE="./.dokploy-api-key"

if [ ! -f "$API_KEY_FILE" ]; then
    echo "Error: API key file not found at $API_KEY_FILE"
    echo "The provisioner may not have run (instance already existed)."
    echo "To force re-provisioning: terraform taint module.dokploy-instance.linode_instance.dokploy_main"
    exit 1
fi

API_KEY=$(cat "$API_KEY_FILE")

# Backup-destination creds for the dokploy stage are this env's outputs (the
# shared infra-backups key + bucket). Handed off so the dokploy stage's
# dokploy_backup_destination can authenticate without a separate secret entry.
DOKPLOY_BACKUP_BUCKET=$(terraform output -raw dokploy_backups_bucket)
DOKPLOY_BACKUP_ENDPOINT=$(terraform output -raw dokploy_backups_endpoint)
DOKPLOY_BACKUP_REGION=$(terraform output -raw dokploy_backups_region)
DOKPLOY_BACKUP_ACCESS_KEY_ID=$(terraform output -raw dokploy_backups_access_key)
DOKPLOY_BACKUP_SECRET_ACCESS_KEY=$(terraform output -raw dokploy_backups_secret_key)

# Hand off to the dokploy stage by generating its .env
cat > "../dokploy/.env" << EOF
TF_VAR_DOKPLOY_API_KEY=$API_KEY
TF_VAR_DOKPLOY_PROJECT_NAME=${TF_VAR_DOKPLOY_PROJECT_NAME:-services}
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
TF_VAR_DOKPLOY_BACKUP_BUCKET=$DOKPLOY_BACKUP_BUCKET
TF_VAR_DOKPLOY_BACKUP_ENDPOINT=$DOKPLOY_BACKUP_ENDPOINT
TF_VAR_DOKPLOY_BACKUP_REGION=$DOKPLOY_BACKUP_REGION
TF_VAR_DOKPLOY_BACKUP_ACCESS_KEY_ID=$DOKPLOY_BACKUP_ACCESS_KEY_ID
TF_VAR_DOKPLOY_BACKUP_SECRET_ACCESS_KEY=$DOKPLOY_BACKUP_SECRET_ACCESS_KEY
EOF

# Move to root of repository to add files to secrets submodule
cd "$PROJECT_ROOT"

add_or_merge_to_chezmoi "./linode/environments/dokploy/.env"
