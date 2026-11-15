#!/usr/bin/env bash
# Fetch the current Ubuntu Server 24.04 LTS amd64 ISO to a stable tmp path,
# verify its SHA256 against Ubuntu's published SHA256SUMS, and print the
# build-thinkcentre-iso.sh command to run next. Idempotent: re-uses an already
# downloaded, hash-matching ISO instead of re-fetching ~3 GB.
set -euo pipefail

BASE="https://releases.ubuntu.com/24.04"
DEST_DIR="${TMPDIR:-/tmp}/mc-compute-iso"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$DEST_DIR"

# Resolve the exact point-release filename + hash from SHA256SUMS so this keeps
# working across 24.04.x bumps without editing the script.
SUMS="$(curl -fsSL "$BASE/SHA256SUMS")"
LINE="$(printf '%s\n' "$SUMS" | grep 'live-server-amd64.iso' | head -1)"
[ -n "$LINE" ] || { echo "could not find live-server-amd64 in $BASE/SHA256SUMS" >&2; exit 1; }
SHA="${LINE%% *}"
FILE="${LINE##* }"; FILE="${FILE#\*}"   # strip the leading '*' binary marker
ISO="$DEST_DIR/$FILE"

if [ -f "$ISO" ] && echo "$SHA  $ISO" | sha256sum -c - >/dev/null 2>&1; then
  echo "Already downloaded and verified: $ISO"
else
  echo "Downloading $FILE -> $ISO"
  curl -fL --progress-bar -o "$ISO" "$BASE/$FILE"
  echo "Verifying SHA256..."
  echo "$SHA  $ISO" | sha256sum -c -
fi

cat <<EOF

ISO ready: $ISO

Next — build the zero-touch installer (run from the production TF dir so the
compute auth key is readable, then invoke the builder):

  cd linode/environments/production
  set -a; source .env; set +a
  COMPUTE_KEY=\$(terraform output -raw tailnet_compute_auth_key)
  cd "\$(git rev-parse --show-toplevel)"
  $SCRIPT_DIR/build-thinkcentre-iso.sh --iso "$ISO" --authkey "\$COMPUTE_KEY"
EOF
