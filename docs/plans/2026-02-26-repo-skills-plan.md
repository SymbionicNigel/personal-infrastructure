# Repository Management Skills Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create three Claude Code skills (secrets-sync, tf-execute, infra-bootstrap) that encode the repo's chezmoi/Terraform/Dokploy workflows so Claude executes them correctly every time.

**Architecture:** Each skill is a standalone `SKILL.md` file in `.claude/skills/<name>/`. Skills are technique/reference type — they teach Claude the correct commands, argument order, and dependencies. The infra-bootstrap skill references the other two for execution.

**Tech Stack:** Claude Code skills (Markdown with YAML frontmatter), chezmoi, Terraform, Bitwarden CLI

---

### Task 1: Create skills directory structure

**Files:**
- Create: `.claude/skills/secrets-sync/SKILL.md` (placeholder)
- Create: `.claude/skills/tf-execute/SKILL.md` (placeholder)
- Create: `.claude/skills/infra-bootstrap/SKILL.md` (placeholder)

**Step 1: Create directory structure**

```bash
mkdir -p .claude/skills/secrets-sync .claude/skills/tf-execute .claude/skills/infra-bootstrap
```

**Step 2: Create placeholder files**

Create each `SKILL.md` with just a `# TODO` line so the structure exists.

**Step 3: Verify structure**

Run: `find .claude/skills -type f`
Expected: Three SKILL.md files listed.

---

### Task 2: Write secrets-sync skill

**Files:**
- Create: `.claude/skills/secrets-sync/SKILL.md`

**Reference files to consult:**
- `dotfile-utils/scripts/chezmoi-add-secret.sh` — the add-secret workflow
- `dotfile-utils/scripts/source_bitwarden_session.sh` — Bitwarden session setup
- `dotfile-utils/README.md` — full chezmoi usage docs
- `.chezmoi.toml` — config file location and GPG key
- `linode/environments/bootstrap/bootstrap.sh` — example of add_or_merge_to_chezmoi pattern

**Step 1: Write the SKILL.md**

The skill must cover:

1. **Frontmatter:** name `secrets-sync`, description starting with "Use when..." focused on triggering conditions (adding/editing secrets, syncing chezmoi, Bitwarden, GPG encryption)

2. **Overview:** One-sentence core principle — this skill ensures Claude uses the correct chezmoi commands with proper config flag and follows the right workflow for this repo's secrets management chain.

3. **Source-of-truth chain diagram** (flowchart): Bitwarden → `.env.bitwarden` → chezmoi templates → target files → `chezmoi apply`

4. **Quick Reference table** with three operations:
   - **Add new secret:** `./dotfile-utils/scripts/chezmoi-add-secret.sh [--encrypt] <path>`
   - **Edit existing secret:** Edit file → `chezmoi --config ./.chezmoi.toml merge <path>` → `chezmoi --config ./.chezmoi.toml git -- add/commit/push`
   - **List managed files:** `chezmoi --config ./.chezmoi.toml managed`
   - **Apply secrets:** `chezmoi --config ./.chezmoi.toml apply`
   - **Source Bitwarden session:** `source ./dotfile-utils/scripts/source_bitwarden_session.sh`

5. **Workflow section** with the checklist:
   - Determine operation (add/edit/list)
   - Source Bitwarden session if `.env.bitwarden` exists
   - Run correct command
   - Verify with `managed` or `diff`
   - Stage in `.secrets` submodule
   - Remind user to commit submodule pointer in parent repo

6. **Key facts:**
   - ALL chezmoi commands need `--config ./.chezmoi.toml`
   - GPG key ID: `9A4ABBA2F90BCF19`
   - `.secrets` is a git submodule — changes require committing the submodule pointer
   - `chezmoi-add-secret.sh` handles dot-prefix conversion (`.env` → `dot_env`) and `encrypted_` prefix automatically

7. **Common mistakes:**
   - Running bare `chezmoi` without `--config` flag
   - Forgetting to commit submodule pointer after changing `.secrets`
   - Using `chezmoi add` directly instead of `chezmoi-add-secret.sh` for project files

**Step 2: Word count check**

Run: `wc -w .claude/skills/secrets-sync/SKILL.md`
Target: Under 500 words.

---

### Task 3: Test secrets-sync skill

**Skill type:** Technique/Reference — test with application scenarios.

**Step 1: Run application scenario WITHOUT skill**

Use a subagent (Task tool) with this prompt:
> "I need to add the file `linode/environments/production/.env` as an encrypted secret managed by chezmoi in this project. What commands should I run?"

Document: Does the agent know about `--config ./.chezmoi.toml`? Does it use `chezmoi-add-secret.sh`? Does it mention the submodule commit?

**Step 2: Run application scenario WITH skill**

Same prompt, but instruct the subagent to read `.claude/skills/secrets-sync/SKILL.md` first.

Expected: Agent uses correct commands, mentions Bitwarden session, submodule pointer.

**Step 3: Run variation scenario**

Prompt: "I edited `linode/environments/production/.env` directly. How do I sync the changes back to chezmoi?"

Expected: Agent recommends `chezmoi merge` workflow, not `chezmoi-add-secret.sh`.

**Step 4: Fix gaps**

If any scenario reveals missing information, update the SKILL.md.

---

### Task 4: Write tf-execute skill

**Files:**
- Create: `.claude/skills/tf-execute/SKILL.md`

**Reference files to consult:**
- `PLAN.md` Phase 3 — `scripts/tf.sh` pattern
- `linode/environments/bootstrap/bootstrap.sh` — existing TF execution pattern
- `linode/environments/production/base.tf` — production TF config
- `linode/README.md` — TF state backend docs

**Step 1: Write the SKILL.md**

The skill must cover:

1. **Frontmatter:** name `tf-execute`, description "Use when..." focused on running Terraform commands against environment directories in this repo.

2. **Overview:** Core principle — this skill ensures Claude loads `.env` variables and configures the S3 state backend correctly before running any Terraform command.

3. **Environment map** (quick reference table):
   | Environment | Path | State | Special Notes |
   |---|---|---|---|
   | Bootstrap | `linode/environments/bootstrap/` | Local | Has own `bootstrap.sh`, run once |
   | Production | `linode/environments/production/` | S3 (`terraform.tfstate`) | Stage 1: Linode + DNS |
   | Dokploy | `linode/environments/dokploy/` | S3 (`dokploy.tfstate`) | Stage 2: Dokploy resources, depends on Stage 1 |

4. **Execution pattern** (the `tf.sh` pattern):
   ```bash
   # 1. Load .env
   set -a; source "$TF_DIR/.env"; set +a
   # 2. Init with backend config
   terraform init -backend-config=backend.hcl
   # 3. Plan (always before apply)
   terraform plan -input=false
   # 4. Apply (only with user confirmation)
   terraform apply -input=false
   ```

5. **Decision flowchart:** Which environment? → Bootstrap (use `bootstrap.sh`) vs Production/Dokploy (use tf.sh pattern). If Dokploy, verify Stage 1 was applied first.

6. **Post-apply actions:**
   - Production: Retrieve Dokploy API key via `ssh root@<ip> cat /root/.dokploy-api-key`
   - Either stage: Offer to persist sensitive outputs via secrets-sync skill

7. **Prerequisites checklist:**
   - `.env` file exists for the environment
   - `backend.hcl` exists for S3-backed environments
   - For Dokploy stage: Production stage must be applied first

8. **Common mistakes:**
   - Forgetting to source `.env` before running TF
   - Running `terraform init` without `-backend-config=backend.hcl`
   - Running `apply` without `plan` first
   - Trying to run Dokploy stage before Production stage

**Step 2: Word count check**

Run: `wc -w .claude/skills/tf-execute/SKILL.md`
Target: Under 500 words.

---

### Task 5: Test tf-execute skill

**Skill type:** Technique/Reference — test with application scenarios.

**Step 1: Run application scenario WITHOUT skill**

Prompt: "I want to deploy the production Terraform environment. What's the correct sequence of commands?"

Document baseline behavior.

**Step 2: Run application scenario WITH skill**

Same prompt with skill loaded.

Expected: Agent sources `.env`, uses `-backend-config=backend.hcl`, runs plan before apply.

**Step 3: Run variation scenario**

Prompt: "I want to deploy the Dokploy Terraform stage but I haven't set up the production stage yet."

Expected: Agent warns that Production must be applied first before Dokploy.

**Step 4: Fix gaps**

Update SKILL.md if scenarios reveal missing information.

---

### Task 6: Write infra-bootstrap skill

**Files:**
- Create: `.claude/skills/infra-bootstrap/SKILL.md`

**Reference files to consult:**
- `PLAN.md` Phase 4 — the 8-step bootstrap sequence
- `.claude/skills/secrets-sync/SKILL.md` — for cross-referencing
- `.claude/skills/tf-execute/SKILL.md` — for cross-referencing

**Step 1: Write the SKILL.md**

The skill must cover:

1. **Frontmatter:** name `infra-bootstrap`, description "Use when..." focused on first-time infrastructure setup, full deploy from scratch, or rebuilding the Linode instance.

2. **Overview:** Core principle — this skill orchestrates the full first-time deploy sequence, calling secrets-sync and tf-execute at the right points.

3. **The 8-step sequence** (numbered list with clear dependencies):
   1. Populate `linode/environments/production/.env` — list all required `TF_VAR_*` and `AWS_*` variables
   2. Run Stage 1: **REQUIRED SUB-SKILL:** Use tf-execute against `production/`
   3. Wait ~5 min for cloud-init to complete
   4. Verify: `ssh root@<linode-ip>` works with key auth
   5. Retrieve API key: `ssh root@<linode-ip> cat /root/.dokploy-api-key`
   6. Create `linode/environments/dokploy/.env` from `.env.example`, add API key
   7. Add to chezmoi: **REQUIRED SUB-SKILL:** Use secrets-sync to encrypt `dokploy/.env`
   8. Run Stage 2: **REQUIRED SUB-SKILL:** Use tf-execute against `dokploy/`

4. **Verification checklist:**
   - SSH access works (key auth only)
   - Dokploy UI at `http://<linode-ip>:3000`
   - `https://whoami.<HOSTNAME_TLD>` responds with HTTPS

5. **Required variables reference** for `production/.env`:
   ```
   TF_VAR_LINODE_TOKEN=
   TF_VAR_DOKPLOY_ADMIN_EMAIL=
   TF_VAR_DOKPLOY_ADMIN_PASSWORD=
   TF_VAR_HOSTNAME_TLD=
   TF_VAR_EMAIL_ADDRESS=
   TF_VAR_REGION=
   AWS_ACCESS_KEY_ID=
   AWS_SECRET_ACCESS_KEY=
   ```

6. **Common mistakes:**
   - Not waiting long enough for cloud-init (check with `ssh root@<ip> cloud-init status`)
   - Forgetting to add `dokploy/.env` to chezmoi after creating it
   - Missing S3 backend credentials in `dokploy/.env`

**Step 2: Word count check**

Run: `wc -w .claude/skills/infra-bootstrap/SKILL.md`
Target: Under 500 words.

---

### Task 7: Test infra-bootstrap skill

**Skill type:** Technique — test with application scenarios.

**Step 1: Run application scenario WITHOUT skill**

Prompt: "I need to set up the Linode infrastructure from scratch. Walk me through the full process."

Document baseline behavior — does the agent know the correct order, variables, and verification steps?

**Step 2: Run application scenario WITH skill**

Same prompt with skill loaded.

Expected: Agent follows the 8-step sequence exactly, references the other two skills, lists all required variables.

**Step 3: Fix gaps**

Update SKILL.md if scenarios reveal missing information.

---

### Task 8: Final review and cleanup

**Step 1: Cross-reference consistency check**

Verify that:
- infra-bootstrap references secrets-sync and tf-execute correctly using `**REQUIRED SUB-SKILL:**` format
- No `@` file links (those force-load and burn context)
- All three skills use consistent terminology

**Step 2: Verify all skills are discoverable**

Run: `find .claude/skills -name "SKILL.md" -exec head -5 {} \;`
Expected: All three skills have valid YAML frontmatter with `name` and `description`.

**Step 3: Final word counts**

Run: `wc -w .claude/skills/*/SKILL.md`
Target: Each under 500 words.
