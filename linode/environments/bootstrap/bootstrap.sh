#!/usr/bin/env bash

# Intended to be ran from /linode/environments/bootstrap
set -a
source .env
set +a

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
        source ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt "$file_path"
    fi
}

terraform init
terraform apply

AWS_ACCESS_KEY_ID=$(terraform output --raw access_key)
AWS_SECRET_ACCESS_KEY=$(terraform output --raw secret_key)
REGION=$(terraform output --raw region)
BUCKET_NAME=$(terraform output --raw bucket_name)
ENDPOINT=$(terraform output --raw endpoint)

cat << EOF > "../production/.env"
AWS_ACCESS_KEY_ID=$AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY=$AWS_SECRET_ACCESS_KEY
EOF

cat << EOF > "../production/backend.hcl"
backend "s3" {
    endpoint                    = "${ENDPOINT}" # or your region
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

# Move to root of repository to add files to secrets submodule
cd ../../..

# Add or merge files to chezmoi
add_or_merge_to_chezmoi "./linode/environments/production/.env"
add_or_merge_to_chezmoi "./linode/environments/production/backend.hcl"
add_or_merge_to_chezmoi "./linode/environments/bootstrap/terraform.tfstate"
add_or_merge_to_chezmoi "./linode/environments/bootstrap/terraform.tfstate.backup"