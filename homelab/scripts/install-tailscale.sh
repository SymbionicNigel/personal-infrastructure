#!/usr/bin/env bash
# Install tailscaled (if absent) and bring the box onto the tailnet.
# Idempotent and re-runnable. Single source of truth for tailnet membership:
# invoked by the cloud host's Terraform null_resource, the Ansible `tailscale`
# role, and the flash-drive bootstrap.sh.
set -euo pipefail

AUTHKEY=""
ADVERTISE_TAGS=""
ADVERTISE_ROUTES=""
ENABLE_SSH=0

usage() {
  echo "Usage: $0 --authkey KEY --advertise-tags TAGS \
[--advertise-routes CIDR] [--ssh]" >&2
  exit 64
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --authkey)          AUTHKEY="${2:?}"; shift 2 ;;
    --advertise-tags)   ADVERTISE_TAGS="${2:?}"; shift 2 ;;
    --advertise-routes) ADVERTISE_ROUTES="${2:?}"; shift 2 ;;
    --ssh)              ENABLE_SSH=1; shift ;;
    *)                  usage ;;
  esac
done

if [ -z "$AUTHKEY" ] || [ -z "$ADVERTISE_TAGS" ]; then
  usage
fi

if ! command -v tailscale >/dev/null 2>&1; then
  curl -fsSL https://tailscale.com/install.sh | sh
fi

up_args=(--authkey "$AUTHKEY" --advertise-tags "$ADVERTISE_TAGS")
[ -n "$ADVERTISE_ROUTES" ] && up_args+=(--advertise-routes "$ADVERTISE_ROUTES")
[ "$ENABLE_SSH" -eq 1 ] && up_args+=(--ssh)

sudo tailscale up "${up_args[@]}"
