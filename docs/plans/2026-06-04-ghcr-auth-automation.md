# Follow-up: Automate Dokploy → GHCR Authentication

## Context

The astarte service ships through a private GHCR repository. Dokploy
must `docker pull` from `ghcr.io/<owner>/<image>:<sha>` on every deploy,
which requires the Dokploy host's docker daemon to have GHCR credentials
configured.

Today this is handled by a **one-time manual SSH** to the host with a
fine-grained PAT (see [linode/README.md](../../linode/README.md), Stage 2
setup). The PAT is stored in chezmoi; the host's
`/root/.docker/config.json` is populated by hand once and survives reboots.

This is **acceptable for the current shape** (single Linode, pet host, one
maintainer) but is a known piece of out-of-band setup that breaks if:

- The host is destroyed and rebuilt (host config.json is gone).
- The PAT expires (default fine-grained max is 1 year).
- A second maintainer is onboarded who didn't run the SSH step.
- A second service ships under a different GHCR namespace.

## Why this isn't fixed now

Three automation paths were evaluated and rejected for this iteration:

| Path | Why rejected |
|---|---|
| **Make GHCR package public** | User wants images private. |
| **GitHub App + installation tokens on host** | Requires creating a GitHub App (still a one-time UI step), adds JWT/refresh tooling, broader blast radius via the App private key. ROI poor for a single host. |
| **`gh auth token` via TF local-exec** | The gh CLI token is account-wide and has broader scope than a fine-grained PAT. Persisting it through TF state is a worse security trade than a scoped PAT in chezmoi. |
| **Dokploy registry UI** | Still requires a PAT; adds a UI click; the credential is then stored both in chezmoi and Dokploy's DB. Marginal control-plane visibility gain over current approach. |

The current manual SSH path has the **smallest blast radius** (scoped PAT,
short-lived, revocable independently) and the **smallest code surface**
(zero new TF, zero new chezmoi entries beyond the PAT itself).

## Triggers for revisiting

Pick this back up when one or more of these is true:

- A second service ships under GHCR — same auth, but now you'd configure
  the host twice if you ever rebuild.
- You've rotated the PAT more than once and it's annoying.
- The Dokploy host needs to become cattle (auto-replaceable) rather than
  a pet — at that point `user_data.sh` baking or a registry-credentials
  TF resource becomes worth it.
- The `j0bIT/dokploy` provider gains a `dokploy_registry` resource (or
  upstream Dokploy ships a CLI/API for registry config). At that point
  the credential moves into TF state with a clean Dokploy-managed
  lifecycle.

## When the trigger fires

Most likely shape of the eventual fix, in rough order of preference:

1. **Dokploy registry resource via TF.** If the provider supports it,
   register the PAT once via `dokploy_registry`, lift it from chezmoi
   into TF state. Dokploy handles host-level docker login from there.
2. **TF remote-exec module on bootstrap.** New child module
   `linode/modules/ghcr-auth` that reads the PAT from a TF var (sourced
   from the encrypted `.env`) and SSH-pushes it to the host on apply.
   Idempotent via `triggers = { pat_hash = sha256(var.GHCR_PAT) }`.
3. **GitHub App, if multiple hosts/services need auth.** Justified once
   you have 3+ services or 2+ hosts pulling from the same namespace and
   PAT rotation across all of them becomes painful.

## Out of scope for this follow-up

- Public-package path (deliberate user decision; not revisiting).
- Pure-Terraform PAT *creation* — GitHub does not expose this API; no
  automation path exists today regardless of effort invested.
