#!/usr/bin/env bash
# Install local toolchain for personal-infrastructure development.
# Idempotent: safe to re-run.
set -euo pipefail

REPO_ROOT="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"

# --- pnpm + Node 24 (frontend) ---
# pnpm must be the *standalone* build for `pnpm env` to manage Node; a pnpm
# installed via npm/nvm/corepack errors with ERR_PNPM_CANNOT_MANAGE_NODE.
install_standalone_pnpm() {
  curl -fsSL https://get.pnpm.io/install.sh | sh -
  # shellcheck disable=SC1090
  source ~/.bashrc 2>/dev/null || true
  hash -r # drop any cached path to the previous pnpm
}
if ! command -v pnpm >/dev/null 2>&1; then
  install_standalone_pnpm
else
  echo "pnpm already installed: $(pnpm --version)"
fi
# Pin the Node runtime pnpm manages to 24 (matches iris + CI). If the existing
# pnpm can't manage Node (non-standalone install), swap in the standalone build
# and retry. Idempotent.
if ! pnpm env use --global 24; then
  echo "pnpm cannot manage Node; installing standalone pnpm and retrying..."
  install_standalone_pnpm
  pnpm env use --global 24
fi

# --- uv (Python services) ---
# Mirrors CI's astral-sh/setup-uv@v3 so local + runner stay aligned.
if ! command -v uv >/dev/null 2>&1; then
  curl -LsSf https://astral.sh/uv/install.sh | sh
  # Make uv available in this shell so the sync loop below works on
  # first install. Persistent PATH updates land in ~/.bashrc via the
  # installer.
  if [ -f "$HOME/.local/bin/env" ]; then
    # shellcheck disable=SC1091
    source "$HOME/.local/bin/env"
  fi
else
  echo "uv already installed: $(uv --version)"
fi

# --- gh (GitHub CLI; required by the chezmoi + bw installers below) ---
if ! command -v gh >/dev/null 2>&1; then
  bash "$REPO_ROOT/dotfile-utils/scripts/install_gh_cli.sh"
else
  echo "gh already installed: $(gh --version | head -1)"
fi

# --- chezmoi (secrets/dotfile management; needs gh) ---
# Not command-v guarded: the installer pins an exact version and owns its own
# upgrade + fork-mirror path, so it must run even when an older chezmoi exists.
# It self-short-circuits ("Nothing to do") when already at the pinned version.
bash "$REPO_ROOT/dotfile-utils/scripts/install_chezmoi.sh"

# --- bw (Bitwarden CLI; needs gh) ---
if ! command -v bw >/dev/null 2>&1; then
  bash "$REPO_ROOT/dotfile-utils/scripts/install_bw_cli.sh"
else
  echo "bw already installed: $(bw --version)"
fi

# --- Python project sync (each top-level pyproject.toml) ---
# Generates uv.lock and .venv for every service. New Python services get
# picked up automatically without touching this script.
while IFS= read -r pyproject; do
  service_dir="$(dirname "$pyproject")"
  echo "uv sync in ${service_dir#"$REPO_ROOT"/}"
  (cd "$service_dir" && uv sync)
done < <(find "$REPO_ROOT" -maxdepth 2 -name pyproject.toml -not -path '*/node_modules/*')

# --- Node project install (each top-level package.json) ---
# Installs node_modules and runs each package's prepare script (e.g. iris's
# panda codegen) for every frontend service. New Node services get picked up
# automatically without touching this script.
while IFS= read -r pkgjson; do
  service_dir="$(dirname "$pkgjson")"
  echo "pnpm install in ${service_dir#"$REPO_ROOT"/}"
  (cd "$service_dir" && pnpm install)
done < <(find "$REPO_ROOT" -maxdepth 2 -name package.json -not -path '*/node_modules/*')
