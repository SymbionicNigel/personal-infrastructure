# Secrets Injection Pattern for Compose Services

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task.

**Goal:** Establish the canonical mechanism for getting per-service
secrets (database URLs, third-party API keys, signing keys, etc.) into
the running containers in both local and prod, with secrets stored
encrypted in `.secrets/` via chezmoi+GPG and re-derivable from a fresh
checkout + GPG key alone.

**Architecture:** Per-service `.env` files live in
`.secrets/compose/<service>.env`, encrypted by chezmoi. At Terraform
apply time, the dokploy env reads each via `data "dotenv"`, exposes them
as locals, and threads them into the compose templatefile substitution
that already drives `dokploy_compose.compose_file_content`. Service
containers read the values via `environment:` entries in compose, NOT
via in-container `.env` files (so secrets never land on disk inside the
container; they live in the container's env block, set by Dokploy/Docker
at start). Local dev mirrors the same pattern via the existing
`docker-compose.local.yml` override + a `czm`-decrypted copy of the
service `.env` for `--env-file` use.

This extends the existing pattern for the compose-wide `HOSTNAME_TLD`
substitution; nothing about how Terraform talks to Dokploy changes.

**Tech Stack:** `germanbrew/dotenv` Terraform data source (already in
the dokploy env's required_providers); `templatefile()`; chezmoi+GPG via
the existing `chezmoi-add-secret.sh` helper; Docker Compose env
substitution.

---

## Context: Why This Approach

User chose this over Dokploy UI env vars and sops/age:

- **vs Dokploy UI env vars:** UI vars live only in Dokploy's postgres.
  Re-deriving from a fresh checkout is impossible without a working
  postgres backup. We don't want service config recovery to depend on
  the backup story being healthy. Also makes diffs reviewable in git.
- **vs sops/age:** chezmoi+GPG is already the secrets workflow for every
  other secret in the repo (`.env` files, backend.hcl, etc.). Adding a
  second encryption tool doubles the bootstrap requirements.

Tradeoff accepted: rotating a service secret means a TF apply (Dokploy
re-deploys the compose stack). This is fine for the cadence of service
secret rotation (low) and is no worse than rotating `HOSTNAME_TLD` is
today.

---

## File Structure

**Create per service** (`<service>` placeholder; concrete services are
out of scope for this plan — this is the template):

- `.secrets/compose/<service>.env` (chezmoi-managed, encrypted) — KV
  pairs only, no comments needed. Mirror of what a `<service>.env`
  outside the repo would look like.
- `compose/<service>.env.example` — uncommitted-secrets stand-in for
  local dev when the real `.env` hasn't been decrypted (and for new
  contributors / future-you on a fresh machine). Same keys, dummy
  values.

**Modify (one-time):**

- `linode/environments/dokploy/main.tf` — add a `for_each` `data "dotenv"`
  block that loads each `.secrets/compose/<service>.env` keyed by
  service name. Surface as `local.service_env = { <service> = {...} }`.
- `linode/environments/dokploy/main.tf` (`local.compose_content`
  templatefile call) — add `service_env` to the templatefile vars.
- `compose/docker-compose.yml` — for each service that needs secrets,
  use `environment:` map with `${VAR}` placeholders that templatefile
  substitutes at TF apply time. NOT `env_file:` — env_file would require
  the file to exist on Dokploy's host, which would mean another
  out-of-band push.
- `compose/docker-compose.local.yml` — `env_file: ./compose/<service>.env`
  per service. The local file is the chezmoi-decrypted copy (chezmoi
  apply puts it at `compose/<service>.env`).
- `linode/environments/dokploy/.env` (chezmoi-managed) — no change; the
  service `.env` files are separate per service.

**No new modules.** The pattern lives entirely in the `dokploy`
environment's main.tf templating; per-service files are flat.

**Critical reference:**
- `linode/environments/dokploy/main.tf:18-27` — existing `data.dotenv`
  + `local.compose_content` templatefile pattern that this extends.
- `compose/docker-compose.yml` — current shape (single service, no
  service-level secrets yet).

---

## Task 1: Pick a pilot service to drive the pattern

**Files:** none (decision).

- [ ] **Step 1:** Pick one service to be the first consumer of this
  pattern. `janus` is fine as a no-op (whoami doesn't need secrets) —
  better to wait until the first real service lands and shape the
  pattern around its needs. If no real service is queued, pick a stub
  (e.g., a placeholder Postgres-backed service) and implement the
  pattern end-to-end so it's proven before the first real service
  inherits it.

- [ ] **Step 2:** Document the chosen pilot in this plan as a comment
  before continuing. The choice affects exactly one thing: which set of
  env keys the pilot `<service>.env.example` will contain.

---

## Task 2: Encrypted file scaffolding

**Files:**
- Create: `.secrets/compose/<pilot>.env` (via chezmoi)
- Create: `compose/<pilot>.env.example` (committed)

- [ ] **Step 1:** Decide the env keys the pilot needs. For an empty
  pilot, a single dummy key (`PILOT_SECRET=...`) is fine. For a real
  service, list every env var the container reads from outside.

- [ ] **Step 2:** Create the example file with dummy values:

  ```bash
  cat > compose/<pilot>.env.example <<'EOF'
  PILOT_SECRET=replace-me
  EOF
  ```

- [ ] **Step 3:** Add the real, encrypted version to chezmoi:

  ```bash
  bash ./dotfile-utils/scripts/chezmoi-add-secret.sh --encrypt \
    compose/<pilot>.env
  ```

  Confirm with `czm managed | grep compose/<pilot>.env` that chezmoi
  tracks it.

---

## Task 3: Wire `data.dotenv` for the pilot into the dokploy env

**Files:**
- Modify: `linode/environments/dokploy/main.tf`

- [ ] **Step 1:** Add a `data "dotenv" "<pilot>"` block alongside the
  existing `data.dotenv.compose`, pointing at
  `${path.root}/../../../.secrets/compose/<pilot>.env`. Path includes
  `.secrets` because chezmoi-decrypted secrets surface at the same paths
  as their encrypted source.

- [ ] **Step 2:** Extend `locals.compose_content` templatefile vars to
  include the pilot's env keys:

  ```hcl
  compose_content = templatefile(
    "${path.root}/../../../compose/docker-compose.yml",
    {
      HOSTNAME_TLD   = local.hostname_tld
      PILOT_SECRET   = data.dotenv.<pilot>.entries["PILOT_SECRET"]
    }
  )
  ```

  Run `terraform fmt`.

- [ ] **Step 3:** `terraform plan` — should show
  `dokploy_compose.stack` as a replace if and only if the existing
  `compose/docker-compose.yml` references the new variables. If the
  compose file is untouched at this stage, no plan diff is expected;
  proceed to Task 4 before re-planning.

---

## Task 4: Reference the secret(s) in the compose file

**Files:**
- Modify: `compose/docker-compose.yml`

- [ ] **Step 1:** For the pilot service, add an `environment:` block:

  ```yaml
  services:
    <pilot>:
      image: ...
      environment:
        PILOT_SECRET: "${PILOT_SECRET}"
      ...
  ```

  `${PILOT_SECRET}` is consumed by Terraform's `templatefile()`, NOT by
  Docker Compose at runtime — by the time Dokploy receives the compose
  YAML, the literal value is inlined. This is intentional: it means the
  Dokploy host never sees a separate env file, and rotation is "TF
  apply" rather than "push a new file."

- [ ] **Step 2:** Add the same key to `compose/docker-compose.local.yml`
  via `env_file: ./compose/<pilot>.env`. Local dev uses the
  chezmoi-decrypted copy at the project root; chezmoi apply places it
  there after Bitwarden session is sourced. (Alternative: also use
  `environment:` + shell substitution locally, with `set -a; source
  compose/<pilot>.env; set +a; docker compose ... up` — pick one
  pattern and commit to it.)

- [ ] **Step 3:** `terraform plan` — expect `dokploy_compose.stack`
  replace (compose_file_content hash changed). Apply.

---

## Task 5: Verify end-to-end

**Files:** none (operational).

- [ ] **Step 1:** SSH to dokploy-prod, exec into the pilot container:
  `docker exec -it <container> env | grep PILOT_SECRET`. Expect the
  literal value from `.secrets/compose/<pilot>.env`.

- [ ] **Step 2:** Confirm the value does NOT appear in
  `docker inspect <container>` for the running container's labels or
  in any file on the host outside of Dokploy's compose definitions
  (which are already considered "as private as Dokploy's postgres").

- [ ] **Step 3:** Locally, `chezmoi apply` (via `czm`), then
  `docker compose -f docker-compose.yml -f docker-compose.local.yml up
  <pilot>` and confirm the same env var is set inside the local
  container.

---

## Task 6: Document the pattern

**Files:**
- Modify: `linode/README.md` (or `compose/README.md` if/when created)

- [ ] **Step 1:** Add a short subsection — "Service secrets" — that
  states the pattern in 3-5 sentences: per-service `.env` in
  `.secrets/compose/`, surfaced via `data.dotenv` into the dokploy env,
  inlined into compose at apply time. Include the example.example file
  convention and the local-dev decryption step.

  Per the "no plan refs in long-lived docs" memory: describe the
  pattern itself, not "see plan 2026-05-20-...".

---

## Out of Scope

- Per-service secret rotation tooling (a script that bumps one key
  across `.secrets/compose/<svc>.env` and triggers a targeted apply).
  Can be layered on later.
- Secret pinning into Terraform state (TF state contains the secret
  values today because `data.dotenv` reads them at plan time). State is
  already in encrypted Object Storage with a short-lived key per
  apply; acceptable for now. If state-as-secret becomes a concern,
  switch to writing secrets into Dokploy via a side-channel and
  passing only references through `compose_file_content`.
- A central `dokploy_env_var` resource per key (alternative pattern
  the j0bIT provider may or may not support). Reserved for later if
  inlining via templatefile becomes painful at scale (10+ services).
- Vault / external secret stores. Explicitly rejected: chezmoi+GPG is
  the chosen path; revisit only when the personal-infra constraint
  shifts.
