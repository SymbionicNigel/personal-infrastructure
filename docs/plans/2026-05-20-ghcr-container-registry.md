# Container Registry on GHCR

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task.

**Goal:** Stand up GitHub Container Registry (GHCR) as the source for
service images, with images built and pushed from this repo via GitHub
Actions, pulled by Dokploy on each deploy. Establishes the image-tagging
convention and registry-auth pattern that every future service will
inherit.

**Architecture:**

- Images live at `ghcr.io/<github-owner>/<image>:<tag>`.
- Build/push happens in GitHub Actions on push to `main` (or on tag —
  picked in Task 1). OIDC-based auth to GHCR (no long-lived PAT in
  Actions).
- Dokploy authenticates to GHCR for pull via a long-lived
  read:packages PAT, configured once via the Dokploy UI registry
  panel (or `dokploy_docker_registry` provider resource if the
  j0bIT provider exposes it — see Task 3 Step 2).
- `compose/docker-compose.yml` references images as
  `ghcr.io/<owner>/<image>:${IMAGE_TAG}` so a TF apply with a new tag
  triggers a Dokploy redeploy.

**Tech Stack:** GitHub Container Registry (free for public images,
read:packages PAT gates private pulls), GitHub Actions
(`docker/build-push-action@v5`, OIDC), Dokploy registry integration,
Docker Compose image references.

---

## File Structure

**Create:**

- `.github/workflows/build-images.yml` — matrix build over a list of
  services (initially one entry; pattern shape matters more than the
  pilot). Pushes to `ghcr.io/<owner>/<service>:sha-<short>` and
  `:latest` (on main).
- `.github/workflows/README.md` (optional) — short doc on tag
  conventions + how to add a new service to the matrix. Kept short
  enough to not rot.

**Modify:**

- `compose/docker-compose.yml` — change any service that's now built
  from this repo from a `build:` context (if applicable today) or a
  third-party `image:` (e.g., the current `traefik/whoami` for janus)
  to a `ghcr.io/<owner>/...` reference, only AFTER an image has been
  published. janus stays on `traefik/whoami:latest` because we don't
  build it.

- `linode/environments/dokploy/main.tf` — add `IMAGE_TAG` to the
  templatefile vars (default: a TF variable
  `var.IMAGE_TAG`, default `"latest"`). Setting `TF_VAR_IMAGE_TAG=...`
  becomes the deploy lever for "ship a specific image build."

**No new modules.**

---

## Task 1: Pick the tagging convention

**Files:** none (decision).

- [ ] **Step 1:** Pick one:

  - (a) Tag every build with `sha-<short>` + push `:latest` on main.
    Production deploy uses `:latest`. Simplest; loses ability to roll
    back to a specific image without retrieving the SHA from CI logs.
  - (b) Tag every build with `sha-<short>` only. Production deploy
    pins a SHA via `TF_VAR_IMAGE_TAG`. Slightly more friction (deploy
    requires bumping the var); explicit and reproducible.
  - (c) Semver tags from git tags + sha-<short> for unreleased main.
    Heaviest; reserve for when there's a service with a release
    process.

  Recommendation: **(b)** for personal infra — explicit is better than
  implicit when the deploy cadence is irregular, and a `:latest`
  consumer surprises you the first time you push a broken main.

- [ ] **Step 2:** Pin the chosen convention in
  `.github/workflows/README.md`.

---

## Task 2: Build/push workflow

**Files:**
- Create: `.github/workflows/build-images.yml`

- [ ] **Step 1:** Workflow triggers: `push` to `main`, `pull_request`
  (build-only, don't push), and `workflow_dispatch` for manual rebuilds.
  Matrix `services:` initially empty or with one placeholder service
  (the pilot from the secrets plan if one exists by now).

- [ ] **Step 2:** Job permissions: `packages: write`, `contents: read`,
  `id-token: write` (for OIDC if used). Use `docker/login-action@v3`
  with `username: ${{ github.actor }}`, `password: ${{ secrets.GITHUB_TOKEN }}`
  — GITHUB_TOKEN scoped to packages:write via the `permissions:` block
  is sufficient; no PAT needed for push.

- [ ] **Step 3:** Build + push step uses
  `docker/build-push-action@v5` with `context: ./services/<service>`,
  `tags: ghcr.io/${{ github.repository_owner }}/<service>:sha-${{
  github.sha }}` (truncate sha if desired). Push only when
  `github.event_name == 'push'`.

- [ ] **Step 4:** Add a job summary that prints the image ref so it's
  one click to find in PR / commit views.

---

## Task 3: Dokploy auth to GHCR (for pull)

**Files:** depends on Step 2 outcome.

- [ ] **Step 1:** Mint a fine-grained GH PAT scoped read:packages only,
  store the value in chezmoi as
  `.secrets/dokploy/ghcr-pull-token` (or similar). Document expiry
  cadence (max 1 year on fine-grained PATs); flag a rotation reminder.

- [ ] **Step 2:** Check whether `j0bIT/dokploy` exposes a
  `dokploy_docker_registry` resource. Two outcomes:

  - (a) If it does: declare the registry in
    `linode/environments/dokploy/main.tf`, reading the token via
    `data.dotenv` from the secrets path. Fully TF-managed.

  - (b) If it doesn't: configure once via the Dokploy UI (Settings →
    Docker Registries), document the steps in `linode/README.md`'s
    "Future Decisions" or a follow-up subsection. The token still
    lives in chezmoi; the UI just consumes it on first boot.

  v1: (b) is fine if the provider doesn't have it. The deploy is rare;
  re-doing it on instance replacement (after dokploy-postgres-backups
  is in place) is automatic via the postgres restore.

- [ ] **Step 3:** Validate auth by pulling a private image manually
  from the host: `ssh dokploy-prod 'docker pull
  ghcr.io/<owner>/<svc>:sha-...'`. Expect success.

---

## Task 4: Reference a real image in compose

**Files:**
- Modify: `compose/docker-compose.yml`
- Modify: `linode/environments/dokploy/main.tf` (templatefile vars)
- Modify: `linode/environments/dokploy/variables.tf` (new TF_VAR)

- [ ] **Step 1:** Add `variable "IMAGE_TAG"` with `type = string`,
  `default = "latest"` (Task 1 (b) — overridable per deploy via
  `TF_VAR_IMAGE_TAG`).

- [ ] **Step 2:** In `local.compose_content` templatefile, add
  `IMAGE_TAG = var.IMAGE_TAG`.

- [ ] **Step 3:** Pick a pilot service to migrate from a `build:` or
  third-party `image:` to a GHCR reference. If no service is ready,
  end this plan at Task 3 and resume Task 4 when one is.

- [ ] **Step 4:** Update the service's `image:` to
  `ghcr.io/<owner>/<service>:${IMAGE_TAG}`. `terraform plan` will show
  `dokploy_compose.stack` replace; apply.

- [ ] **Step 5:** Confirm Dokploy successfully pulls and starts the
  image: `ssh dokploy-prod 'docker ps | grep <service>'`.

---

## Task 5: Document the deploy lever

**Files:**
- Modify: `linode/README.md` (or a new `services/README.md`).

- [ ] **Step 1:** Short paragraph: "To deploy a specific image build,
  set `TF_VAR_IMAGE_TAG=sha-<short>` in
  `linode/environments/dokploy/.env` (or `export` it) and run
  `dokploy.sh`. Default `latest` is intentionally unused so deploys
  are explicit."

  Per the no-plan-refs-in-docs rule, describe the lever directly, not
  "see plan 2026-05-20-ghcr".

---

## Out of Scope

- Multi-arch builds (arm64). Add when the host or any service
  requires it.
- Image-vulnerability scanning (Trivy/Snyk in CI). Defer.
- Artifact attestations / SBOM. Defer.
- Self-hosted registry. Explicitly rejected at choice-time; GHCR is
  the canonical path.
- Migrating Dokploy's bundled Traefik image to GHCR-mirrored. Pointless
  — it's pulled directly by Dokploy from its own configuration.
