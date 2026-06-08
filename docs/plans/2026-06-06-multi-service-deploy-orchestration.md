# Multi-Service Deploy Orchestration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Git ops:** the maintainer performs all commits/pushes. Commit steps below are checkpoints — the agent stages/edits and hands the exact commands to the maintainer.

**Goal:** Let multiple services build concurrently and deploy through one
serialized, full-state Terraform apply that never reverts another service's
pinned image tag, with infra changes decoupled from service deploys.

**Architecture:** Per-service workflows run language-specific tests, then a
reusable `_build-push.yml` builds/pushes the image and records the built SHA as a
repo Variable `<SVC>_IMAGE_TAG`. A central `deploy-dokploy.yml` orchestrator
(triggered by `workflow_run` after a build, or by dokploy-config pushes) collects
*all* `*_IMAGE_TAG` Variables and runs the existing reusable `_terraform-apply.yml`
against `dokploy.sh`, rendering the whole compose. `infra.yml` (production env)
stays independent; all applies share the `linode-tf-apply` concurrency group.

**Tech Stack:** GitHub Actions (reusable workflows, `workflow_run`, repo
Variables), `gh` CLI, Terraform (`j0bIT/dokploy`, `germanbrew/dotenv`), GHCR,
chezmoi/GPG/Bitwarden secrets.

---

## Current state (already built + committed earlier this effort)

- `_terraform-apply.yml` — env-agnostic reusable apply (submodule checkout via
  `SUBMODULES_PAT`, GPG import, bw+chezmoi install, `chezmoi apply --no-tty`,
  setup-terraform, runs a wrapper script). Concurrency `linode-tf-apply`.
- `astarte.yml` — `test` + inline `build-and-push` + `deploy` (calls
  `_terraform-apply.yml`); deploy `if:` temporarily widened to the feature branch.
- `infra.yml` — calls `_terraform-apply.yml` with `production.sh`; triggers on
  `production/**`, `modules/**`, `.secrets` (+ temp feature branch).
- `null_resource.ghcr_login` in the production env (host GHCR login).
- `dokploy.sh` / `production.sh` derive the GHCR owner from the repo owner;
  `production.sh` skips its local bootstrap under `CI=true`.

This plan builds on that state.

## Locked decisions (brainstorm 2026-06-06)

| Question | Decision |
|---|---|
| Per-service tag store | Repo Variables `<SVC>_IMAGE_TAG`; every dokploy apply reads all of them, so clobbering is structurally impossible. |
| Deploy trigger | Central `deploy-dokploy.yml` via `workflow_run` (after any service build) + push to `compose/docker-compose.yml` / `linode/environments/dokploy/**`. |
| Build reuse | `_build-push.yml` reusable (build → GHCR push → set `<SVC>_IMAGE_TAG`); per-service test stays inline. |
| Tag-store auth | `GITHUB_TOKEN` can't manage Variables → reuse `SUBMODULES_PAT`, renamed `CI_PAT`, rescoped to dotfiles `Contents:Read` + this repo `Variables:Read and write`. |
| Service registry | Implicit: the orchestrator reads every repo Variable ending in `_IMAGE_TAG`. A service self-registers when its `_build-push` run sets the Variable. |
| `.secrets` trigger granularity | `paths:` can't see inside the submodule; `infra.yml` keeps `paths:[.secrets]` + an in-workflow gate that diffs the submodule pointer and applies only on `production/**` or `modules/**` changes inside it. |

## File structure

| File | Change | Responsibility |
|---|---|---|
| (GitHub repo secret `CI_PAT`) | create; delete `SUBMODULES_PAT` | submodule read + Variables write |
| `.github/workflows/_terraform-apply.yml` | modify | accept a multiline `tf_vars` input; drop `image_tag`/`tf_var_name`; reference `CI_PAT` |
| `.github/workflows/_build-push.yml` | create | reusable build→GHCR push→set `<SVC>_IMAGE_TAG` |
| `.github/workflows/deploy-dokploy.yml` | create | orchestrator: collect tags → call `_terraform-apply.yml` (dokploy.sh) |
| `.github/workflows/astarte.yml` | modify | test → call `_build-push.yml`; remove inline `build-and-push` + `deploy` |
| `.github/workflows/infra.yml` | modify | reference `CI_PAT`; add `.secrets` change-gate job |
| `.github/scripts/secrets-path-changed.sh` | create | reusable parent+submodule path-change detector for the infra gate |
| (repo Variable `ASTARTE_IMAGE_TAG`) | seed | first-deploy bootstrap |

No Terraform changes: `linode/environments/dokploy` already takes
`var.ASTARTE_IMAGE_TAG`; new services follow the "Adding a service" appendix.

---

## Task 1: Rename `SUBMODULES_PAT` → `CI_PAT` (rescoped)

**Files:**
- Modify: `.github/workflows/_terraform-apply.yml`
- (Maintainer) GitHub repo secret + PAT

- [ ] **Step 1: Maintainer creates the rescoped PAT + secret**

Fine-grained PAT, resource owner = the repo owner:
- `personal-infrastructure-dotfiles` → `Contents: Read`
- `personal-infrastructure` → `Variables: Read and write`

```bash
gh secret set CI_PAT            # paste the token
gh secret delete SUBMODULES_PAT
```

- [ ] **Step 2: Point the reusable apply at `CI_PAT`**

In `_terraform-apply.yml`, the submodule-checkout step:

```yaml
      - env:
          CI_PAT: ${{ secrets.CI_PAT }}
        name: Checkout submodules
        run: |
          git config --global url."https://x-access-token:${CI_PAT}@github.com/".insteadOf "git@github.com:"
          git submodule sync --recursive
          git submodule update --init --recursive
```

- [ ] **Step 3: Validate it parses**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_terraform-apply.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 4: Commit (maintainer)**

```bash
git add .github/workflows/_terraform-apply.yml
git commit -m "ci: rename SUBMODULES_PAT -> CI_PAT in reusable apply"
```

---

## Task 2: `_terraform-apply.yml` — accept a `tf_vars` map

Replaces the single `image_tag`/`tf_var_name` inputs with a generic multiline
`tf_vars` (one `KEY=VALUE` per line) the run step exports before the script.

**Files:**
- Modify: `.github/workflows/_terraform-apply.yml`

- [ ] **Step 1: Swap the inputs (both `workflow_call` and `workflow_dispatch`)**

Replace the `image_tag` and `tf_var_name` input blocks (in *both* the
`workflow_call.inputs` and `workflow_dispatch.inputs` maps) with a single
`tf_vars` input, keeping the others (`label`, `script`, `working_directory`):

```yaml
      tf_vars:
        default: ""
        description: Newline-separated TF_VAR_* assignments (KEY=VALUE per line).
        required: false
        type: string
```

- [ ] **Step 2: Export `tf_vars` in the run step**

Replace the apply step's `env:` + `run:` with:

```yaml
      - env:
          BW_CLIENTID: ${{ secrets.BW_CLIENTID }}
          BW_CLIENTSECRET: ${{ secrets.BW_CLIENTSECRET }}
          BW_PASSWORD: ${{ secrets.BW_PASSWORD }}
          SCRIPT: ${{ inputs.script }}
          TF_VARS: ${{ inputs.tf_vars }}
        name: terraform apply (${{ inputs.script }})
        run: |
          if [ -n "$TF_VARS" ]; then
            while IFS= read -r line; do
              [ -n "$line" ] && export "$line"
            done <<< "$TF_VARS"
          fi
          bash "$SCRIPT"
        working-directory: ${{ inputs.working_directory }}
```

- [ ] **Step 3: Update `run-name` (drop the removed `image_tag`)**

```yaml
run-name: apply ${{ inputs.label }}
```

- [ ] **Step 4: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_terraform-apply.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 5: Commit (maintainer)**

```bash
git add .github/workflows/_terraform-apply.yml
git commit -m "ci: generic tf_vars input for reusable apply"
```

---

## Task 3: `_build-push.yml` reusable build + push + record tag

**Files:**
- Create: `.github/workflows/_build-push.yml`

- [ ] **Step 1: Write the workflow**

```yaml
# Reusable build + push of a service image to GHCR, recording the built SHA as a
# repo Variable so the deploy orchestrator can render the full compose.
# Required repo secret: CI_PAT (this repo Variables: Read and write).

concurrency:
  cancel-in-progress: false
  group: build-${{ inputs.service }}-${{ github.ref }}

jobs:
  build:
    outputs:
      image_tag: ${{ github.sha }}
    permissions:
      contents: read
      packages: write
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - id: meta
        name: Compute lowercased image ref
        run: |
          owner="${GITHUB_REPOSITORY_OWNER,,}"
          image="${{ inputs.image_name }}"
          [ -n "$image" ] || image="${{ inputs.service }}"
          echo "image=ghcr.io/${owner}/${image,,}" >> "$GITHUB_OUTPUT"

      - uses: docker/setup-buildx-action@v3

      - uses: docker/login-action@v3
        with:
          password: ${{ secrets.GITHUB_TOKEN }}
          registry: ghcr.io
          username: ${{ github.actor }}

      - uses: docker/build-push-action@v6
        with:
          cache-from: type=gha
          cache-to: type=gha,mode=max
          context: ${{ inputs.context }}
          push: true
          tags: |
            ${{ steps.meta.outputs.image }}:${{ github.sha }}
            ${{ steps.meta.outputs.image }}:latest

      # GITHUB_TOKEN can't manage Variables, so use CI_PAT. The orchestrator
      # reads every *_IMAGE_TAG variable.
      - env:
          GH_TOKEN: ${{ secrets.CI_PAT }}
          SERVICE: ${{ inputs.service }}
        name: Record image tag variable
        run: gh variable set "${SERVICE^^}_IMAGE_TAG" --repo "${GITHUB_REPOSITORY}" --body "${GITHUB_SHA}"

name: _build-push

on:
  workflow_call:
    inputs:
      context:
        description: Docker build context directory (e.g. astarte).
        required: true
        type: string
      image_name:
        default: ""
        description: GHCR image name (lowercased). Defaults to `service`.
        required: false
        type: string
      service:
        description: Service id; uppercased -> <SVC>_IMAGE_TAG repo Variable.
        required: true
        type: string
    outputs:
      image_tag:
        description: Commit SHA the image was tagged with.
        value: ${{ jobs.build.outputs.image_tag }}
```

- [ ] **Step 2: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/_build-push.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit (maintainer)**

```bash
git add .github/workflows/_build-push.yml
git commit -m "ci: reusable build-push that records <SVC>_IMAGE_TAG"
```

---

## Task 4: `deploy-dokploy.yml` orchestrator

**Files:**
- Create: `.github/workflows/deploy-dokploy.yml`

- [ ] **Step 1: Write the orchestrator**

```yaml
# Central dokploy deploy. Collects every <SVC>_IMAGE_TAG repo Variable and runs
# one full-state apply, so a single service's deploy never reverts another.
# Add each new service build workflow to on.workflow_run.workflows.

jobs:
  collect:
    if: ${{ github.event_name != 'workflow_run' || github.event.workflow_run.conclusion == 'success' }}
    outputs:
      tf_vars: ${{ steps.tags.outputs.tf_vars }}
    runs-on: ubuntu-latest
    steps:
      - env:
          GH_TOKEN: ${{ secrets.CI_PAT }}
        id: tags
        name: Collect service image tags
        run: |
          {
            echo "tf_vars<<TFVARS_EOF"
            gh variable list --repo "${GITHUB_REPOSITORY}" --json name,value \
              --jq '.[] | select(.name | endswith("_IMAGE_TAG")) | "TF_VAR_\(.name)=\(.value)"'
            echo "TFVARS_EOF"
          } >> "$GITHUB_OUTPUT"

  deploy:
    needs: collect
    secrets: inherit
    uses: ./.github/workflows/_terraform-apply.yml
    with:
      label: dokploy
      script: dokploy.sh
      tf_vars: ${{ needs.collect.outputs.tf_vars }}
      working_directory: linode/environments/dokploy

name: deploy-dokploy

on:
  push:
    branches: [master]
    paths:
      - .github/workflows/_terraform-apply.yml
      - .github/workflows/deploy-dokploy.yml
      - compose/docker-compose.yml
      - linode/environments/dokploy/**
  workflow_dispatch:
  workflow_run:
    branches: [master]
    types: [completed]
    workflows: [astarte]

permissions:
  contents: read
```

- [ ] **Step 2: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/deploy-dokploy.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 3: Commit (maintainer)**

```bash
git add .github/workflows/deploy-dokploy.yml
git commit -m "ci: central dokploy deploy orchestrator"
```

---

## Task 5: `.secrets` change-gate in `infra.yml`

Only run the production apply when a change touches production-relevant paths —
directly in the parent repo OR inside the `.secrets` submodule (GitHub `paths:`
can't see inside a submodule). The diff logic lives in a standalone, reusable
script (it also serves future dokploy-path routing).

**Files:**
- Create: `.github/scripts/secrets-path-changed.sh`
- Modify: `.github/workflows/infra.yml`

- [ ] **Step 1: Create the diff script**

`.github/scripts/secrets-path-changed.sh`:

```bash
#!/usr/bin/env bash
# True if files matching <regex> changed between two parent commits — either in
# the parent repo directly, or inside the .secrets submodule (GitHub path
# filters can't see into submodules). Prints "true"/"false".
# Fails open ("true") on first push / zero before-sha.
#
# Usage: secrets-path-changed.sh <before-sha> <after-sha> <path-regex>
# Requires: CI_PAT in env (fetches the private .secrets repo over HTTPS).
# Requires: parent checked out with fetch-depth: 0 (both commits present).
set -euo pipefail

before="${1:?before sha required}"
after="${2:?after sha required}"
regex="${3:?path regex required}"
zero='0000000000000000000000000000000000000000'

if [ -z "$before" ] || [ "$before" = "$zero" ]; then echo true; exit 0; fi

# Direct change in the parent repo.
if git diff --name-only "$before" "$after" | grep -Eq "$regex"; then
  echo true; exit 0
fi

# Change inside the .secrets submodule: resolve its pointer at each commit.
old=$(git rev-parse "${before}:.secrets" 2>/dev/null || true)
new=$(git rev-parse "${after}:.secrets" 2>/dev/null || true)
if [ -z "$old" ] || [ -z "$new" ] || [ "$old" = "$new" ]; then echo false; exit 0; fi

url=$(git config -f .gitmodules submodule..secrets.url \
  | sed -E "s#git@github.com:#https://x-access-token:${CI_PAT:?CI_PAT required}@github.com/#")
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
git clone --quiet --filter=blob:none "$url" "$tmp"
git -C "$tmp" fetch --quiet origin "$old" "$new"
if git -C "$tmp" diff --name-only "$old" "$new" | grep -Eq "$regex"; then
  echo true
else
  echo false
fi
```

- [ ] **Step 2: Verify the script is shellcheck-clean**

Run: `shellcheck .github/scripts/secrets-path-changed.sh && echo ok`
Expected: `ok`

- [ ] **Step 3: Add a `detect` gate job in `infra.yml` and gate `apply` on it**

Replace the `jobs:` block with (note `fetch-depth: 0` so both commits are
present for the diff):

```yaml
jobs:
  detect:
    outputs:
      run: ${{ steps.gate.outputs.run }}
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0

      # Non-push events (workflow_dispatch) always run; pushes run only when a
      # production/modules path changed in the parent OR inside .secrets.
      - env:
          CI_PAT: ${{ secrets.CI_PAT }}
        id: gate
        name: Gate on production-relevant changes
        run: |
          run=true
          if [ '${{ github.event_name }}' = 'push' ]; then
            run=$(bash .github/scripts/secrets-path-changed.sh \
              '${{ github.event.before }}' '${{ github.sha }}' \
              '^(linode/environments/production/|linode/modules/)')
          fi
          echo "run=$run" >> "$GITHUB_OUTPUT"

  apply:
    if: ${{ needs.detect.outputs.run == 'true' }}
    needs: detect
    secrets: inherit
    uses: ./.github/workflows/_terraform-apply.yml
    with:
      label: production
      script: production.sh
      working_directory: linode/environments/production
```

- [ ] **Step 4: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/infra.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 5: Commit (maintainer)**

```bash
git add .github/scripts/secrets-path-changed.sh .github/workflows/infra.yml
git commit -m "ci: gate infra apply on production-relevant changes (separate diff script)"
```

---

## Task 6: Restructure `astarte.yml`

Use `_build-push.yml`; remove the inline `build-and-push` and `deploy` jobs
(deploys now flow through the orchestrator).

**Files:**
- Modify: `.github/workflows/astarte.yml`

- [ ] **Step 1: Replace the `build-and-push` job with a reusable call**

```yaml
  build-and-push:
    needs: test
    secrets: inherit
    uses: ./.github/workflows/_build-push.yml
    with:
      context: astarte
      service: astarte
```

(The caller job takes no `permissions:` — they come from `astarte.yml`'s
workflow-level `permissions: { contents: read, packages: write }` intersected
with `_build-push.yml`'s own job-level permissions.)
```

- [ ] **Step 2: Delete the entire `deploy:` job** (it now lives in
  `deploy-dokploy.yml`). Leave `test` unchanged.

- [ ] **Step 3: Validate**

Run: `python3 -c "import yaml; yaml.safe_load(open('.github/workflows/astarte.yml')); print('ok')"`
Expected: `ok`

- [ ] **Step 4: Commit (maintainer)**

```bash
git add .github/workflows/astarte.yml
git commit -m "ci: astarte uses reusable build-push; deploy via orchestrator"
```

---

## Task 7: Seed the `ASTARTE_IMAGE_TAG` Variable

So the first orchestrated apply has a value rather than the `latest` default.

**Files:** none (maintainer command).

- [ ] **Step 1: Seed it to the latest built SHA**

```bash
sha=$(gh api /user/packages/container/astarte/versions \
  --jq '.[0].metadata.container.tags[]' | grep -E '^[0-9a-f]{40}$' | head -1)
gh variable set ASTARTE_IMAGE_TAG --body "$sha"
gh variable get ASTARTE_IMAGE_TAG     # confirm
```

(If no SHA tag exists yet, this is set automatically by the first `_build-push`
run; seed manually only to bootstrap before that run.)

---

## Task 8: End-to-end validation cutover

Each step gates the next.

- [ ] **Step 1: Confirm secrets present** — `GPG_PRIVATE_KEY`, `BW_CLIENTID`,
  `BW_CLIENTSECRET`, `BW_PASSWORD`, `CI_PAT`; `TF_VAR_GHCR_PAT` in the production
  `.env` (chezmoi); `.secrets` + `dotfile-utils` branches pushed; parent submodule
  pointers bumped.

- [ ] **Step 2: Establish host GHCR login** — run `infra.yml` (workflow_dispatch
  once on master, or a local `production.sh`). Expect `Login Succeeded`.

- [ ] **Step 3: Push the feature branch.** Expect: `astarte` `test` +
  `_build-push` green; `ASTARTE_IMAGE_TAG` Variable updated; image SHA tag in
  GHCR (`gh api /user/packages/container/astarte/versions`).

- [ ] **Step 4: Exercise the dokploy apply via the orchestrator's push path.**
  Temporarily add the feature branch to `deploy-dokploy.yml` `on.push.branches`
  (the restructure touches `linode/environments/dokploy/**`, so the push triggers
  it). Watch: collect job emits `TF_VAR_ASTARTE_IMAGE_TAG=<sha>`; apply renders
  the compose; `docker ps | grep astarte` on the host; `curl https://astarte.<TLD>/health`
  → `{"status":"ok"}`.

- [ ] **Step 5: Revert temporary triggers** — remove the feature branch from
  `astarte.yml`, `infra.yml`, and `deploy-dokploy.yml`.

- [ ] **Step 6: PR → FF/rebase merge.** On master: build is a cache hit; the
  `workflow_run`-after-build orchestrator path fires (confirmable only on master);
  apply is a no-op (same tags). `/health` still `{"status":"ok"}`.

---

## Adding a service (appendix, not a task today)

1. `compose/docker-compose.yml`: add the service with
   `image: ghcr.io/${GHCR_OWNER}/<svc>:${<SVC>_IMAGE_TAG}`.
2. `linode/environments/dokploy/{main.tf,variables.tf}`: add `variable
   "<SVC>_IMAGE_TAG"` and pass it into the `templatefile` vars.
3. `.github/workflows/<svc>.yml`: per-service `test` → `_build-push.yml`
   (`service: <svc>`, `context: <dir>`).
4. `deploy-dokploy.yml`: add `<svc>` to `on.workflow_run.workflows`.
5. Seed `gh variable set <SVC>_IMAGE_TAG` once.

## Out of scope / risks

- **`workflow_run` default-branch quirk** — fires from the default branch's
  definition and only for default-branch workflows; the orchestrator's
  workflow_run path is confirmable only post-merge on master. Feature-branch
  validation uses the push path (Task 8 Step 4).
- **First-deploy bootstrap** — a service's Variable must exist before its first
  orchestrated apply (Task 7).
- **`.secrets` gate clones the submodule with `CI_PAT`** — value is masked in
  logs; relies on the old/new submodule commits being fetchable (they are, on the
  `.secrets` branch).
- **Identity-leak hits** (e.g. `dokploy_project.main.name`) — tracked in
  `2026-06-03-identity-audit-plan.md`.
- **Stage 1 bootstrap from CI** — still local-only (`production.sh` CI guard).
- **`.chezmoi.toml.tmpl` `project.mode` prompt** — deliberately left as-is; CI and
  `czm` use the static root `./.chezmoi.toml` and the value is unused. Don't "fix" it.

## Verification

1. Two service deploys (or a deploy + a dokploy-config push) never revert another
   service's tag — the rendered compose carries every current `<SVC>_IMAGE_TAG`.
2. `_build-push` sets the repo Variable (repo → Variables) and pushes `:sha` +
   `:latest`.
3. Orchestrator triggers on a build completion and on `compose/`/`dokploy/**`
   pushes; queues on `linode-tf-apply`.
4. An `infra.yml` apply and a `deploy-dokploy.yml` apply run back-to-back queue
   rather than race.
5. `CI_PAT` reads the private `.secrets` submodule and writes Variables;
   `SUBMODULES_PAT` removed.
6. A dokploy-only `.secrets` change does NOT run the prod apply; a
   production-path `.secrets` change does.
7. GHCR host login persists across deploys (no per-deploy `docker login`).
8. `curl https://astarte.<TLD>/health` → `{"status":"ok"}` after the cycle.
