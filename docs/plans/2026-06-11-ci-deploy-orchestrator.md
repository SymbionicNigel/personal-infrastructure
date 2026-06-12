# CI deploy orchestrator — single deploy after all builds

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the per-service-workflow + `workflow_run` deploy topology with a single `ci.yml` orchestrator so that one master push deploys **exactly once, after all changed services finish building** — and adding a new service is "drop in a reusable workflow + wire two lines."

**Architecture:** A top-level `ci.yml` runs on push/PR/dispatch. A `changes` job (paths-filter) decides which services changed; each changed service is built+tested via its own **reusable** workflow (`_astarte.yml`, `_iris.yml`); the `deploy` jobs (`collect` → `prod` → `dokploy`) `needs` all service jobs, so GitHub's native dependency graph guarantees deploy runs once, after every build. This removes `workflow_run` and its dedupe logic entirely.

**Tech Stack:** GitHub Actions (reusable workflows, `needs`, paths-filter), the existing `_build-push.yml` + `_terraform-apply.yml` reusables, `actionlint`.

---

## Why this over the alternatives

`workflow_run` fires per-workflow-completion, so two changed services → two deploys (serialized, eventually-consistent). Putting builds **and** deploy in one workflow lets `deploy` use `needs: [astarte, iris]` — a native "after all of them" with no polling, no race, no double-apply. The cost is a CI-topology rearchitecture (this plan), paid once.

## Target topology

```
ci.yml  (push: master | pull_request | workflow_dispatch)
  changes ───┬─> astarte (uses _astarte.yml)  ─┐   (gated: changes.outputs.astarte)
             ├─> iris    (uses _iris.yml)      ─┤   (gated: changes.outputs.iris)
             │                                  ▼
             ├─> collect (reads *_IMAGE_TAG vars; needs [changes, astarte, iris])
             ├─> prod    (uses _terraform-apply; needs [changes, astarte, iris])
             │                                  ▼
             └─> dokploy (uses _terraform-apply; needs [collect, prod])
  ci-gate (always(); needs all; single required check)

_astarte.yml (workflow_call): test (uv) -> build-and-push (uses _build-push.yml)
_iris.yml    (workflow_call): test (pnpm) -> build-and-push (uses _build-push.yml)
_build-push.yml      — UNCHANGED (records <SVC>_IMAGE_TAG variable on push)
_terraform-apply.yml — UNCHANGED (already has the environment/deployment tracking)
```

### Key behaviors (must be preserved)
- **Single-service master push:** that service builds → records its tag → deploy applies the full stack (all current `*_IMAGE_TAG` vars). One deploy.
- **Multi-service master push:** both build (in parallel), deploy `needs` both → runs once after both. **The fix.**
- **Infra-only master push:** no service builds (jobs skip), deploy still applies (gating includes `infra`).
- **Service-code master push (no compose change):** deploy still applies, because a new image tag must roll out — gating includes the per-service outputs, not just `infra`.
- **PR:** everything runs as validation; `prod`/`dokploy` run `terraform plan` (`plan_only`), gated to PRs that touched `infra` (and not Dependabot, which lacks `CI_PAT`).
- **workflow_dispatch:** re-applies current state (no rebuild).
- **Image tags stay in repo Variables** (`<SVC>_IMAGE_TAG`) — the persistent "currently-deployed tag" store. Because service jobs are `needs` of `collect`, the vars are fresh when read (single ordered workflow, no cross-workflow race).

### Design decisions
1. **`deploy` jobs use `if: ${{ !cancelled() && !contains(needs.*.result, 'failure') && <gating> }}`** — `!cancelled()` makes them evaluate even when a service job was *skipped* (didn't change); `!contains(... 'failure')` blocks deploy if a build *failed*.
2. **PR plans show the real image update:** `collect` overrides each changed service's `*_IMAGE_TAG` with the commit SHA its build tags the image with, so the dokploy plan previews the image bump a merge would make (not the stale deployed tag). Combined with the hashed redeploy trigger (Task 0), the plan clearly shows `terraform_data.redeploy` firing. Terraform `plan` only diffs the rendered compose string — it never pulls the not-yet-pushed PR image; the *apply* still `needs` the builds so the image is pushed first.
3. **One required check (`ci-gate`)** replaces `astarte-gate` + `iris-gate` + `deploy-gate`. **Branch protection must be updated by hand** (Task 6) or merges will block on the now-nonexistent checks.
4. **Concurrency:** PRs coalesce per-branch (`cancel-in-progress: true`); master/dispatch share one non-cancellable `ci-main` group. The actual TF op still serializes on `_terraform-apply.yml`'s `linode-tf-apply` lock. **Never** cancel an in-flight apply.

## File structure

- **Create:** `.github/workflows/_iris.yml` — reusable iris CI (test + build-push).
- **Create:** `.github/workflows/_astarte.yml` — reusable astarte CI (test + build-push).
- **Create:** `.github/workflows/ci.yml` — orchestrator (changes + service jobs + deploy + gate).
- **Delete:** `.github/workflows/astarte.yml`, `.github/workflows/iris.yml`, `.github/workflows/deploy.yml`.
- **Modify:** `linode/environments/dokploy/main.tf` — hash the dokploy redeploy trigger (Task 0).
- **Unchanged:** `.github/workflows/_build-push.yml`, `.github/workflows/_terraform-apply.yml`, `.github/dependabot.yml` (the `github-actions` ecosystem auto-covers any `.github/workflows/*`).

---

## Task 0: Hash the dokploy redeploy trigger

Independent of the workflow restructure (can land first/separately). The `terraform_data.redeploy` resource currently keys its "content changed → redeploy" trigger on the **entire rendered compose string**, which bloats state and dumps the whole file into every plan diff. A `sha256` of the same content detects change identically with a clean one-line trigger — and makes the PR plan's "redeploy will fire" obvious once `collect` (Task 3) feeds the would-be image tag in.

**Files:**
- Modify: `linode/environments/dokploy/main.tf` (the `terraform_data "redeploy"` resource)

- [ ] **Step 1: Hash the trigger**

Replace `triggers_replace = local.compose_content` with the hash, and update the comment:

```hcl
# The provider's Update saves the compose but never redeploys, so a bumped image
# tag wouldn't roll out. Replicate its deploy call whenever the rendered content
# changes -- keyed on a content hash (not the raw compose) for a clean trigger.
resource "terraform_data" "redeploy" {
  triggers_replace = sha256(local.compose_content)

  provisioner "local-exec" {
```

(Leave the `provisioner`, `environment`, `command`, and `depends_on` blocks untouched — only the comment and the `triggers_replace` line change.)

- [ ] **Step 2: Validate**

Run: `terraform -chdir=linode/environments/dokploy fmt -check && terraform -chdir=linode/environments/dokploy validate` (or, if backend init is unavailable locally, just `terraform fmt -check`).
Expected: formatted, valid. `sha256()` is a built-in Terraform function — no provider/init change needed.

> First apply after this lands re-fires the trigger once (the stored value changes from full-content to a hash) → one harmless redeploy. Expected, not an error.

- [ ] **Step 3: Commit**

```bash
git add linode/environments/dokploy/main.tf
git commit -m "deploy: key dokploy redeploy trigger on a compose content hash"
```

---

## Task 1: Reusable iris CI (`_iris.yml`)

Extract iris's `test` + `build-and-push` from `iris.yml` into a reusable workflow with a `push_image` input. No `changes`/`if` here — the caller (`ci.yml`) gates it.

**Files:**
- Create: `.github/workflows/_iris.yml`

- [ ] **Step 1: Create the file**

```yaml
# Reusable iris CI: test then build+push. Called by ci.yml (gated on iris
# changes); the push_image input is false for PR validation builds.
concurrency:
  cancel-in-progress: false
  group: iris-${{ github.ref }}

jobs:
  build-and-push:
    needs: test
    secrets: inherit
    uses: ./.github/workflows/_build-push.yml
    with:
      context: iris
      push_image: ${{ inputs.push_image }}
      service: iris

  test:
    defaults:
      run:
        working-directory: iris
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - name: Install pnpm
        uses: pnpm/action-setup@v6
        with:
          package_json_file: iris/package.json

      - uses: actions/setup-node@v6
        with:
          cache: pnpm
          cache-dependency-path: iris/pnpm-lock.yaml
          node-version: 24

      - run: pnpm install --frozen-lockfile

      - run: pnpm typecheck

      - run: pnpm lint

      - run: pnpm test

      - run: pnpm build

      # Fail if any prod dependency ships a non-permissive license.
      - name: license audit
        run: >
          pnpm dlx license-checker-rseidelsohn --production --excludePrivatePackages
          --onlyAllow 'MIT;Apache-2.0;BSD-2-Clause;BSD-3-Clause;0BSD;ISC;Unlicense;MPL-2.0;CC0-1.0;Python-2.0'

name: _iris

on:
  workflow_call:
    inputs:
      push_image:
        default: false
        description: Push to GHCR + record IRIS_IMAGE_TAG. False = build-only validation (PRs).
        required: false
        type: boolean

permissions:
  contents: read
  packages: write
```

- [ ] **Step 2: Validate**

Run: `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest .github/workflows/_iris.yml`
Expected: no output, exit 0. (A "workflow_call reachable" warning is fine — it's called by ci.yml, created in Task 3.)

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_iris.yml
git commit -m "ci: add reusable _iris workflow (test + build-push)"
```

---

## Task 2: Reusable astarte CI (`_astarte.yml`)

Same shape, astarte's toolchain (copy the `test` steps + license allow-list **verbatim** from `astarte.yml`).

**Files:**
- Create: `.github/workflows/_astarte.yml`

- [ ] **Step 1: Create the file**

```yaml
# Reusable astarte CI: test then build+push. Called by ci.yml (gated on astarte
# changes); push_image is false for PR validation builds.
concurrency:
  cancel-in-progress: false
  group: astarte-${{ github.ref }}

jobs:
  build-and-push:
    needs: test
    secrets: inherit
    uses: ./.github/workflows/_build-push.yml
    with:
      context: astarte
      push_image: ${{ inputs.push_image }}
      service: astarte

  test:
    defaults:
      run:
        working-directory: astarte
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v6

      - uses: astral-sh/setup-uv@v8.2.0
        with:
          cache-dependency-glob: astarte/uv.lock
          enable-cache: true

      - run: uv sync --frozen

      - run: uv run ruff check

      - run: uv run ruff format --check

      - run: uv run pytest

      - name: license audit
        run: >
          uv run pip-licenses --allow-only='Apache Software
          License;Apache 2.0;Apache-2.0;BSD
          License;BSD-2-Clause;BSD-3-Clause;0BSD;ISC License
          (ISCL);ISC;MIT License;MIT;Mozilla Public License 2.0 (MPL
          2.0);MPL-2.0;Python Software Foundation
          License;PSF-2.0;The Unlicense (Unlicense);Unlicense;Apache-2.0
          OR BSD-2-Clause'

name: _astarte

on:
  workflow_call:
    inputs:
      push_image:
        default: false
        description: Push to GHCR + record ASTARTE_IMAGE_TAG. False = build-only validation (PRs).
        required: false
        type: boolean

permissions:
  contents: read
  packages: write
```

- [ ] **Step 2: Validate**

Run: `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest .github/workflows/_astarte.yml`
Expected: no output, exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/_astarte.yml
git commit -m "ci: add reusable _astarte workflow (test + build-push)"
```

---

## Task 3: Orchestrator (`ci.yml`)

The single entry point. `changes` → service jobs → `collect`/`prod`/`dokploy` (`needs` the service jobs) → `ci-gate`.

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create the file**

```yaml
# Single CI orchestrator. One run per push/PR builds only the changed services
# (reusable _astarte/_iris workflows), then the deploy jobs `needs` all service
# jobs -- so a master push deploys exactly once, after every build finishes.
# Replaces the old per-service workflows + workflow_run deploy.

# PRs coalesce per-branch (cancel-in-progress). master/dispatch share one
# non-cancellable group; the TF op also serializes on _terraform-apply's lock.
concurrency:
  cancel-in-progress: ${{ github.event_name == 'pull_request' }}
  group: ci-${{ github.event_name == 'pull_request' && format('pr-{0}', github.ref) || 'main' }}

jobs:
  # Build+test each changed service via its reusable workflow. push_image is
  # true off PRs, so PRs validate the image without pushing or touching the
  # <SVC>_IMAGE_TAG variable.
  astarte:
    if: ${{ needs.changes.outputs.astarte == 'true' }}
    needs: changes
    secrets: inherit
    uses: ./.github/workflows/_astarte.yml
    with:
      push_image: ${{ github.event_name != 'pull_request' }}

  iris:
    if: ${{ needs.changes.outputs.iris == 'true' }}
    needs: changes
    secrets: inherit
    uses: ./.github/workflows/_iris.yml
    with:
      push_image: ${{ github.event_name != 'pull_request' }}

  # Which services / infra changed. Defaults to 'false' on workflow_dispatch
  # (the filter only runs on PR/push); the deploy gating handles dispatch
  # explicitly. Push needs a checkout for the paths-filter base comparison.
  changes:
    outputs:
      astarte: ${{ steps.filter.outputs.astarte || 'false' }}
      infra: ${{ steps.filter.outputs.infra || 'false' }}
      iris: ${{ steps.filter.outputs.iris || 'false' }}
    runs-on: ubuntu-latest
    steps:
      - if: ${{ github.event_name == 'push' }}
        uses: actions/checkout@v6
      - id: filter
        if: ${{ github.event_name == 'pull_request' || github.event_name == 'push' }}
        uses: dorny/paths-filter@v4
        with:
          filters: |
            astarte:
              - 'astarte/**'
            infra:
              - '.github/workflows/_terraform-apply.yml'
              - '.github/workflows/ci.yml'
              - '.secrets'
              - 'compose/docker-compose.yml'
              - 'linode/environments/dokploy/**'
              - 'linode/environments/production/**'
              - 'linode/modules/**'
            iris:
              - 'iris/**'

  # Single required status check for branch protection. Always runs so it always
  # reports; fails only if a triggered job actually failed/was cancelled.
  ci-gate:
    if: ${{ always() }}
    needs: [changes, astarte, iris, collect, prod, dokploy]
    runs-on: ubuntu-latest
    steps:
      - if: ${{ contains(needs.*.result, 'failure') || contains(needs.*.result, 'cancelled') }}
        run: |
          echo "A triggered job failed: ${{ join(needs.*.result, ', ') }}"
          exit 1
      - run: |
          echo "ok: ${{ join(needs.*.result, ', ') }}"

  # Gather every <SVC>_IMAGE_TAG repo Variable into TF_VAR_* lines. needs the
  # service jobs so just-built tags are already recorded when read.
  collect:
    if: ${{ !cancelled() && !contains(needs.*.result, 'failure') && (github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && (needs.changes.outputs.infra == 'true' || needs.changes.outputs.astarte == 'true' || needs.changes.outputs.iris == 'true')) || (github.event_name == 'pull_request' && needs.changes.outputs.infra == 'true' && github.actor != 'dependabot[bot]')) }}
    needs: [changes, astarte, iris]
    outputs:
      tf_vars: ${{ steps.tags.outputs.tf_vars }}
    runs-on: ubuntu-latest
    steps:
      - env:
          ASTARTE_CHANGED: ${{ needs.changes.outputs.astarte }}
          GH_TOKEN: ${{ secrets.CI_PAT }}
          IRIS_CHANGED: ${{ needs.changes.outputs.iris }}
        id: tags
        name: Collect service image tags
        run: |
          {
            echo "tf_vars<<TFVARS_EOF"
            # Base: current deployed tags for every service (unchanged ones use these).
            gh variable list --repo "${GITHUB_REPOSITORY}" --json name,value \
              --jq '.[] | select(.name | endswith("_IMAGE_TAG")) | "TF_VAR_\(.name)=\(.value)"' || true
            # Changed services: override with the commit SHA their build tags the
            # image with (appended last -> wins in the export loop), so the
            # dokploy PR plan reflects the image update a merge would make. No-op
            # on push, where it equals the just-recorded variable.
            [ "${ASTARTE_CHANGED}" = "true" ] && echo "TF_VAR_ASTARTE_IMAGE_TAG=${GITHUB_SHA}"
            [ "${IRIS_CHANGED}" = "true" ] && echo "TF_VAR_IRIS_IMAGE_TAG=${GITHUB_SHA}"
            echo "TFVARS_EOF"
          } >> "$GITHUB_OUTPUT"

  # Provision/converge the host. Runs after all service builds; skipped (not
  # failed) builds are fine, a failed build blocks the deploy. plan_only on PRs.
  prod:
    if: ${{ !cancelled() && !contains(needs.*.result, 'failure') && (github.event_name == 'workflow_dispatch' || (github.event_name == 'push' && (needs.changes.outputs.infra == 'true' || needs.changes.outputs.astarte == 'true' || needs.changes.outputs.iris == 'true')) || (github.event_name == 'pull_request' && needs.changes.outputs.infra == 'true' && github.actor != 'dependabot[bot]')) }}
    needs: [changes, astarte, iris]
    secrets: inherit
    uses: ./.github/workflows/_terraform-apply.yml
    with:
      label: production
      plan_only: ${{ github.event_name == 'pull_request' }}
      script: production.sh
      working_directory: linode/environments/production

  # Render + deploy the compose stack from the collected tags, after the host
  # converges. Default needs-gating: skipped if collect/prod skipped or failed.
  dokploy:
    needs: [collect, prod]
    secrets: inherit
    uses: ./.github/workflows/_terraform-apply.yml
    with:
      label: dokploy
      plan_only: ${{ github.event_name == 'pull_request' }}
      script: dokploy.sh
      tf_vars: ${{ needs.collect.outputs.tf_vars }}
      working_directory: linode/environments/dokploy

name: ci

on:
  pull_request:
  push:
    branches: [master]
  workflow_dispatch:

permissions:
  contents: read
  deployments: write
  packages: write
  pull-requests: read
```

- [ ] **Step 2: Validate (now that _iris/_astarte exist)**

Run: `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest .github/workflows/ci.yml .github/workflows/_iris.yml .github/workflows/_astarte.yml`
Expected: exit 0, no errors. actionlint resolves all four `uses: ./.github/workflows/*` references (`_iris`, `_astarte`, `_terraform-apply`, `_build-push`).

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml
git commit -m "ci: add single orchestrator (deploy once after all service builds)"
```

---

## Task 4: Remove the old workflows

`astarte.yml`, `iris.yml`, and `deploy.yml` are fully superseded by `ci.yml` + the reusables. Deleting them also removes the `workflow_run` trigger and its dedupe logic.

**Files:**
- Delete: `.github/workflows/astarte.yml`, `.github/workflows/iris.yml`, `.github/workflows/deploy.yml`

- [ ] **Step 1: Delete + confirm nothing else references them**

```bash
git rm .github/workflows/astarte.yml .github/workflows/iris.yml .github/workflows/deploy.yml
grep -rn 'astarte.yml\|iris.yml\|deploy.yml\|workflow_run' .github/ || echo "no dangling references"
```
Expected: the three files staged-deleted; no `workflow_run`/old-filename references remain.

- [ ] **Step 2: Validate the whole workflows dir**

Run: `docker run --rm -v "$PWD":/repo --workdir /repo rhysd/actionlint:latest`
Expected: exit 0 across all remaining workflows.

- [ ] **Step 3: Commit**

```bash
git add -A .github/workflows/
git commit -m "ci: remove per-service workflows + workflow_run deploy (superseded by ci.yml)"
```

---

## Task 5: Verify dependabot + docs need no change

- [ ] **Step 1: Confirm dependabot still covers the new workflows**

Run: `grep -A2 'package-ecosystem: github-actions' .github/dependabot.yml`
Expected: the `github-actions` entry has `directory: /` — it auto-discovers every `.github/workflows/*`, including the new `ci.yml`/`_iris.yml`/`_astarte.yml`. **No edit needed.**

- [ ] **Step 2: Confirm no docs reference the deleted workflow names**

Run: `grep -rn 'astarte.yml\|iris.yml\|deploy.yml' README.md AGENTS.md docs/ 2>/dev/null || echo "clean"`
Expected: `clean` (the plan files under `docs/plans/` may mention them historically — that's fine; do not edit long-lived docs to reference plans).

---

## Task 6: Update branch protection (MANUAL — repo admin)

The required status checks changed names. **Until this is done, PRs will block on missing checks.**

- [ ] **Step 1: Repo → Settings → Branches → `master` rule → Require status checks.**
  - **Remove:** `astarte-gate`, `iris-gate`, `deploy-gate`.
  - **Add:** `ci-gate`.
- [ ] **Step 2:** (Optional) Make the `ci` workflow the lone required workflow.

> The single-string status check name produced by the orchestrator is `ci-gate` (the job id). Confirm it appears in the checks list after the first PR run from Task 7, then mark it required.

---

## Task 7: Verification

- [ ] **Step 1: Open a PR touching two services + infra**

Make a trivial change in `astarte/`, `iris/`, and `compose/docker-compose.yml` on a branch; open a PR.

- [ ] **Step 2: Confirm one `ci` run, correct graph**

Run: `gh pr checks` and `gh run view <ci-run-id> --json jobs --jq '.jobs[].name'`
Expected: a **single** `ci` run with `changes`, `astarte`, `iris`, `collect`, `prod` (plan), `dokploy` (plan), `ci-gate`. `prod`/`dokploy` start **after** `astarte` and `iris` complete (check `startedAt`). All pass. In the `dokploy` plan log, confirm the `collect` override fed the changed services' SHA as `TF_VAR_*_IMAGE_TAG` and that `terraform_data.redeploy` shows its hashed trigger changing (i.e. the plan previews a redeploy), not "no changes".

- [ ] **Step 3: Confirm the multi-service master deploy is single**

After merge to master (or on a throwaway master-targeting test), run:
`gh run list --workflow ci.yml --branch master --limit 3` and open the run.
Expected: **one** `ci` run; `astarte` + `iris` build in parallel; `prod`/`dokploy` **apply** once, after both; the GitHub **Environments** tab shows single `production` + `dokploy` deployments for that SHA (not two).

- [ ] **Step 4: Confirm an infra-only and a single-service push each deploy once**

Push an infra-only change, then a single-service change (separately); each should produce one `ci` run that applies once (service jobs skip where unchanged, deploy still runs).

---

## Adding a new service later (the payoff)

1. Create `.github/workflows/_<svc>.yml` (copy `_iris.yml` or `_astarte.yml`; swap toolchain/context/service).
2. In `ci.yml`: add a `<svc>:` job (`if: needs.changes.outputs.<svc> == 'true'`, `uses: ./.github/workflows/_<svc>.yml`), add `<svc>` to the `changes` filters + outputs, add `<svc>` to the `needs` of `collect`/`prod` and the `(... outputs.<svc> ...)` clauses + `ci-gate`, and add the `<SVC>_CHANGED` env + the `[ "${<SVC>_CHANGED}" = "true" ] && echo "TF_VAR_<SVC>_IMAGE_TAG=${GITHUB_SHA}"` override line in `collect`.
3. Add the service to `compose/docker-compose.yml` and a `<SVC>_IMAGE_TAG` Terraform var (the `collect` job auto-discovers any `*_IMAGE_TAG`).

No new deploy wiring, no `workflow_run`, no ordering concerns.

---

## Self-review notes (risks / rollback)

- **Branch protection (Task 6) is the one out-of-band step** — if skipped, merges block. Do it right after the first PR surfaces `ci-gate`.
- **Reusable-workflow permission capping:** `ci.yml` grants the union (`contents:read`, `packages:write`, `deployments:write`, `pull-requests:read`); each reusable requests a subset. Verified by actionlint + the Task 7 run.
- **`!cancelled()` on deploy jobs** is required so they evaluate when service jobs *skip*; the `!contains(needs.*.result, 'failure')` clause blocks deploy on a failed build. Confirm in Task 7 by failing a build intentionally (optional).
- **Rollback:** revert the commits from Tasks 1–4 and restore the branch-protection checks; the old `astarte.yml`/`iris.yml`/`deploy.yml` return intact.
