#!/usr/bin/env bash

# Intended to be ran from /linode/environments/bootstrap
set -a
# shellcheck source=/dev/null
source .env
set +a

# Source Bitwarden session if available
# Get parent repository root (handles both submodule and parent repo contexts)
PROJECT_ROOT=$(git rev-parse --show-superproject-working-tree 2>/dev/null)
if [ -z "$PROJECT_ROOT" ]; then
    PROJECT_ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "Error: Not in a git repository"; exit 1; }
fi
if [ -f "$PROJECT_ROOT/.env.bitwarden" ] || [ -n "${BW_SESSION:-}" ]; then
    source "$PROJECT_ROOT/dotfile-utils/scripts/source_bitwarden_session.sh" || { echo "Error: Bitwarden session setup failed"; exit 1; }
fi

# Function to check if file is managed by chezmoi and add or merge accordingly
# Args: $1 = file path relative to repo root
add_or_merge_to_chezmoi() {
    local file_path="$1"
    # Check if file is already managed by chezmoi
    if chezmoi source-path --config ./.chezmoi.toml "$file_path" &>/dev/null; then
        echo "$file_path is already managed. Merging changes..."
        chezmoi merge --config ./.chezmoi.toml "$file_path"
    else
        echo "$file_path is not managed. Adding to chezmoi..."
        # shellcheck source=dotfile-utils/scripts/chezmoi-add-secret.sh
        source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt "$file_path"
    fi
}

# production/.env may already contain user-supplied TF_VAR_* values from a
# prior run (or chezmoi apply). Treat it as additive: replace keys in place
# or append missing ones, never wipe the file.
PROD_ENV="../production/.env"
touch "$PROD_ENV"
upsert_env_var() {
    local key="$1"
    local value="$2"
    if grep -q "^${key}=" "$PROD_ENV"; then
        # `|` chosen as delimiter — won't appear in AWS creds or TF_VAR values
        sed -i "s|^${key}=.*|${key}=${value}|" "$PROD_ENV"
    else
        echo "${key}=${value}" >> "$PROD_ENV"
    fi
}

# Prompt for any user-supplied TF_VAR that isn't already populated. Skips
# silently when a non-empty value is present, so reruns don't re-prompt.
prompt_if_missing() {
    local key="$1"
    local prompt_text="$2"
    local mode="${3:-plain}"  # "secret" hides input

    local current=""
    current=$(grep "^${key}=" "$PROD_ENV" | tail -n1 | cut -d= -f2-)
    if [ -n "$current" ]; then
        return 0
    fi

    local value=""
    if [ "$mode" = "secret" ]; then
        read -rsp "$prompt_text: " value
        echo
    else
        read -rp "$prompt_text: " value
    fi
    if [ -z "$value" ]; then
        echo "Error: $key is required" >&2
        exit 1
    fi
    upsert_env_var "$key" "$value"
}

# Capture user-supplied values up front so the rest of the run is hands-off.
prompt_if_missing "TF_VAR_LINODE_TOKEN"           "Linode API token"                        "secret"
prompt_if_missing "TF_VAR_DOKPLOY_ADMIN_EMAIL"    "Dokploy admin email"
prompt_if_missing "TF_VAR_DOKPLOY_ADMIN_PASSWORD" "Dokploy admin password"                  "secret"
prompt_if_missing "TF_VAR_HOSTNAME_TLD"           "Hostname/TLD (e.g. example.com)"
prompt_if_missing "TF_VAR_EMAIL_ADDRESS"          "Email for Let's Encrypt / domain owner"
prompt_if_missing "TF_VAR_REGION"                 "Linode region (e.g. us-ord)"

terraform init
terraform apply

AWS_ACCESS_KEY_ID=$(terraform output --raw access_key)
AWS_SECRET_ACCESS_KEY=$(terraform output --raw secret_key)
REGION=$(terraform output --raw region)
BUCKET_NAME=$(terraform output --raw bucket_name)
ENDPOINT=$(terraform output --raw endpoint)

upsert_env_var "AWS_ACCESS_KEY_ID" "$AWS_ACCESS_KEY_ID"
upsert_env_var "AWS_SECRET_ACCESS_KEY" "$AWS_SECRET_ACCESS_KEY"

cat << EOF > "../production/backend.hcl"
backend "s3" {
    endpoint                    = "${ENDPOINT}"
    bucket                      = "${BUCKET_NAME}"
    key                         = "terraform.tfstate"
    region                      = "${REGION}" # must match endpoint region
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    encrypt                     = true
}
EOF

cat << EOF > "../dokploy/backend.hcl"
backend "s3" {
    endpoint                    = "${ENDPOINT}"
    bucket                      = "${BUCKET_NAME}"
    key                         = "dokploy.tfstate"
    region                      = "${REGION}" # must match endpoint region
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    force_path_style            = true
    encrypt                     = true
}
EOF

# Move to root of repository to add files to secrets submodule
cd "$(git rev-parse --show-toplevel)"

# Add or merge files to chezmoi
add_or_merge_to_chezmoi "./linode/environments/production/.env"
add_or_merge_to_chezmoi "./linode/environments/production/backend.hcl"
add_or_merge_to_chezmoi "./linode/environments/dokploy/backend.hcl"
add_or_merge_to_chezmoi "./linode/environments/bootstrap/terraform.tfstate"
add_or_merge_to_chezmoi "./linode/environments/bootstrap/terraform.tfstate.backup"