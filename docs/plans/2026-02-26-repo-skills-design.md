# Design: Repository Management Skills

## Context

This repo has complex workflows spanning chezmoi, Bitwarden, GPG encryption,
Terraform, and Dokploy. Remembering the correct commands, argument order, and
dependencies between tools is error-prone. Three Claude Code skills will encode
these workflows so Claude executes them correctly every time.

## Architecture: Three Focused Skills

### 1. `secrets-sync`

Manages adding, editing, encrypting, and syncing secrets across the
chezmoi/Bitwarden/.env/TF variable chain.

**Invoked when:** User asks to add a secret, update an env file, encrypt
something, sync chezmoi, or mentions Bitwarden/GPG.

**Key knowledge encoded:**
- Source-of-truth chain: Bitwarden -> `.env.bitwarden` -> chezmoi templates ->
  `.env` / TF `.env` files -> `chezmoi apply` deploys them
- All chezmoi commands require `--config ./.chezmoi.toml`
- Adding secrets: `./dotfile-utils/scripts/chezmoi-add-secret.sh [--encrypt] <path>`
- Editing managed secrets: edit file, `chezmoi merge`, then `chezmoi git -- add/commit/push`
- Bitwarden session must be sourced first if `.env.bitwarden` exists
- GPG key ID: `9A4ABBA2F90BCF19`
- After modifying `.secrets` submodule, commit submodule pointer in parent repo

**Checklist:**
1. Determine operation type (add new / edit existing / list managed)
2. Ensure Bitwarden session is active if needed
3. Run the correct chezmoi command
4. Verify with `chezmoi managed` or `diff`
5. Stage changes in `.secrets` submodule
6. Remind user to commit submodule pointer

### 2. `tf-execute`

Runs Terraform against any environment directory with correct `.env` loading
and state backend configuration.

**Invoked when:** User wants to run `terraform init/plan/apply` or mentions
deploying infrastructure.

**Key knowledge encoded:**
- Pattern: load `.env` from TF directory, run TF with `-backend-config=backend.hcl`
- Two-stage architecture: Stage 1 (`production/`) provisions infra, Stage 2
  (`dokploy/`) configures Dokploy resources
- Bootstrap environment has its own script and local state (special case)
- Always `plan` before `apply` unless user explicitly overrides
- Post-apply: retrieve Dokploy API key via SSH, persist outputs via secrets-sync

**Checklist:**
1. Identify which TF environment to operate on
2. Verify `.env` exists (if not, guide through secrets-sync)
3. Verify `backend.hcl` exists
4. Run `terraform init -backend-config=backend.hcl`
5. Run `terraform plan` and present output
6. Only `apply` with user confirmation
7. Post-apply: handle outputs, offer to persist via secrets-sync

### 3. `infra-bootstrap`

Orchestrates the full first-time bootstrap sequence from PLAN.md Phase 4.

**Invoked when:** User mentions setting up infrastructure from scratch,
first-time deploy, or full bootstrap.

**Key knowledge encoded:**
- The exact 8-step sequence from PLAN.md Phase 4
- Dependencies between steps (Stage 2 requires API key from Stage 1)
- Cloud-init wait (~5 min after Stage 1 apply)
- Verification at each stage (SSH, Dokploy UI, whoami HTTPS)
- References secrets-sync and tf-execute for execution

**Checklist:**
1. Populate `production/.env` (guide through required variables)
2. Run Stage 1 via tf-execute against `production/`
3. Wait for cloud-init, verify SSH access
4. Retrieve Dokploy API key via SSH
5. Create `dokploy/.env` from `.env.example`
6. Add `dokploy/.env` to chezmoi via secrets-sync
7. Run Stage 2 via tf-execute against `dokploy/`
8. Verify `https://whoami.<HOSTNAME_TLD>` responds

## Skill Location

Skills will be created at `.claude/skills/` in the project repo, making them
available to any Claude Code session working in this project.

## Relationship to PLAN.md

The `infra-bootstrap` skill directly encodes PLAN.md Phase 4. The `tf-execute`
skill encodes the `scripts/tf.sh` pattern from Phase 3. The `secrets-sync`
skill encodes the chezmoi workflows used throughout all phases. Once PLAN.md
is executed and `scripts/tf.sh` exists, `tf-execute` will reference it.
