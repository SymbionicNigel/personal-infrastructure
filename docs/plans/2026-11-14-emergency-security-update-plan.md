# Emergency security update plan

## Scope

Prepare and execute a coordinated security update for the declared production stack without changing production during planning. The stack is Ubuntu 22.04, Dokploy v0.29.4, Node 26, Python 3.14, PostgreSQL 17 through TimescaleDB, and the dependencies locked under `iris/` and `astarte/`.

Planning and pull-request validation must not modify Dokploy, running containers, Terraform state, PostgreSQL, TimescaleDB, Traefik, the host, or deployed services. A merge to `master` is a production action because CI builds and pushes service images and invokes the Dokploy Terraform deployment.

## Declared production state

| Component | Declared state | Evidence |
| --- | --- | --- |
| Host | Ubuntu 22.04 | `linode/modules/dokploy/main.tf` |
| Dokploy | v0.29.4 | `linode/environments/production/variables.tf` |
| Iris | `cf77078bc5f0f0322a068befe6ebe0ed553ca858` | GitHub repository variable `IRIS_IMAGE_TAG` |
| Astarte | `1c2fe74540d2324f3cf391061a619cc6a6bee424` | GitHub repository variable `ASTARTE_IMAGE_TAG` |
| Timescale bootstrapped | `9ef7f7a98aab8095a2a01c65e416cc7c782d5cfa` | GitHub repository variable `TIMESCALE_BOOTSTRAPPED_IMAGE_TAG` |
| Iris runtime family | `node:26-slim` | `iris/Dockerfile` |
| Astarte runtime family | `python:3.14-slim` | `astarte/Dockerfile` |
| Database family | `timescale/timescaledb:latest-pg17` | `postgres/Dockerfile` |

The referenced Iris image was built on 2026-07-16, Astarte on 2026-07-09, and Timescale on 2026-06-21. These immutable application tags preserve the base images resolved on those dates even when the corresponding upstream floating tags move.

## Exposure decisions

### Immediate remediation

| Issue | Assessment | Required state |
| --- | --- | --- |
| CVE-2026-111497, Brotli decoder/Node2Shell | The deployed Iris image predates the Node fix and must be treated as containing the vulnerable decoder. Current Iris code does not expose inbound Brotli decompression: React Router Serve uses outbound `createBrotliCompress`, does not register body-parser, and the application has no request-body actions. | Node 26.12.1 or newer, verified Brotli version, immutable base digest |
| CVE-2026-46300, Linux kernel privilege escalation/container escape | Ubuntu 22.04 is in scope. Unattended upgrades can install a fixed kernel, but automatic reboot is disabled. | Fixed kernel for the installed Jammy kernel flavor and one controlled reboot |
| CVE-2026-109518, APT remote code execution | Ubuntu 22.04 is in scope. Security updates are automated, but the installed package state must be checked during the approved window. | APT 2.4.15ubuntu0.1 or newer |
| CVE-2026-63374, AnyIO TLS spoofing | `astarte/uv.lock` contains AnyIO 4.14.1. The vulnerable TLSStream path is not directly used, but the production dependency is affected. | AnyIO 4.14.2 or newer |
| GHSA-6q48-6c7w-9gw2, certifi compromised roots | `astarte/uv.lock` contains certifi 2026.6.17. It currently enters through development HTTPX rather than the production export. | certifi 2026.10.18 or newer and proof it remains absent from production requirements |
| CVE-2026-87776, compression memory leak | Iris contains compression 1.8.1 and React Router Serve registers it on the public response path. | compression 1.8.2 or newer |
| TimescaleDB access-control advisory GHSA-hcfx-29v5-2rcw | The production image was built from a floating Timescale tag in June. The source declaration cannot prove a fixed Timescale release. | Explicit fixed PG17-compatible Timescale release and immutable digest |
| Docker Engine CVE-2026-92543 | Docker is installed from `get.docker.com`, outside the Ubuntu-only unattended-upgrade origins. The exact package is not declared. | Docker Engine 29.8.2 or newer if the installed package is affected |

### Dependency remediation

Iris currently locks React Router 8.1.0 and vulnerable transitive versions of body-parser 2.2.2, proxy-addr 2.0.7, morgan 1.11.0, and qs 6.15.2. React Router's reported RSC path is not enabled, body-parser is installed but not registered, and Express trust proxy is not configured. These reduced-reachability findings must still move to fixed versions as one refreshed production lock update.

Astarte currently locks Mako 1.3.12 through Alembic. Its known vulnerable path is Windows-specific while production is Linux, but the lock should move to Mako 1.4.2 or newer.

### Not exposed by the declared configuration

`CVE-2026-123158`, `*sshole`, requires conditions absent from the declared stack. The host is Ubuntu/glibc, password authentication is disabled, application containers are Debian-based, and the Timescale container does not run or expose SSH.

## Preparation

### Iris security pull request

1. Pin a Node 26.12.1 or newer image by immutable digest in every Iris stage.
2. Update all React Router packages together to at least 8.3.0.
3. Resolve compression, body-parser, proxy-addr, morgan, and qs to fixed versions through the owning dependency rather than unrelated overrides where possible.
4. Record the Node and Brotli versions from the candidate runtime image.
5. Run type checking, linting, tests, the production build, license validation, and a production-only dependency audit.
6. Require no reachable critical or high production npm findings.

### Astarte security pull request

1. Update AnyIO to at least 4.14.2.
2. Update certifi to at least 2026.10.18.
3. Update Mako to at least 1.4.2.
4. Pin the Python runtime and uv builder bases by immutable digest.
5. Export production requirements and verify that development-only packages do not enter the runtime image.
6. Run formatting, linting, tests, migration tests, wheel construction, and the runtime image build.

### Timescale security pull request

1. Replace `latest-pg17` with an explicit fixed Timescale release and digest while preserving PostgreSQL major version 17.
2. Build the bootstrapped image and run the reconcile wrapper against a disposable database.
3. Restore a representative backup into a disposable instance.
4. Test the Timescale extension upgrade and application migrations.
5. Record whether the extension update is reversible. Treat it as restore-only rollback unless upstream guarantees downgrade compatibility.

### Infrastructure hardening pull request

1. Remove or constrain caller-controlled `ref`, `script`, and `working_directory` inputs in `.github/workflows/_terraform-apply.yml` before allowing secret-bearing jobs to check out code.
2. Prevent Bitwarden credentials, `CI_PAT`, and the GPG private key from reaching code selected through an arbitrary ref.
3. Pin `traefik/whoami`, Node, Python, uv, and Timescale image references by digest.
4. Replace the unpinned Docker installer with a declared package source and version policy.
5. Add explicit update coverage for Dokploy, Traefik, TimescaleDB, shell-pinned tools, and host packages that Dependabot cannot manage.

## Dependabot disposition

1. Rebase and rerun PR #60 for AnyIO.
2. Recreate PR #63 after the focused AnyIO, certifi, and Mako updates so it does not overwrite the security resolutions.
3. Refresh PR #62 as the single npm security and routine update. It supersedes PR #46.
4. Replace stale PR #58 with Vitest 4.1.12 or newer.
5. Review the provider updates against read-only plans for every Terraform environment.
6. Rerun all checks after rebasing. Existing green checks are stale and do not validate the final combined locks.
7. Merge nothing until the maintenance window begins.

## Preflight gates

Abort the maintenance window unless all of the following are true:

- The latest application PostgreSQL backup is present, decryptable where applicable, and successfully restored into a disposable PostgreSQL 17 and Timescale instance.
- The latest Dokploy control-plane and `/etc/dokploy` backup is present and restore instructions have been tested.
- The ACME backup is current and valid JSON after decryption.
- The old immutable application image SHAs and database image digest are recorded and pullable.
- Linode console access is available in case SSH or networking does not return after reboot.
- The reviewed Terraform plans contain no destruction, replacement, or unrelated mutation.
- Candidate images preserve expected architecture, non-root execution, health checks, ports, and PostgreSQL major version.
- No candidate contains a reachable critical or high vulnerability without an explicit accepted exception.

Linode backups are disabled in Terraform. Before host package changes, choose and verify either a recoverable Linode disk snapshot or the documented full rebuild path from Terraform plus restored control-plane, ACME, and PostgreSQL backups.

## Maintenance sequence

1. Freeze unrelated merges and manual workflow dispatches.
2. Collect the declared-versus-installed inventory after explicit approval: OS release, APT, running kernel, Docker Engine, Node and Brotli inside Iris, Python inside Astarte, PostgreSQL and Timescale extension, Dokploy, and Traefik.
3. Compare the inventory against this plan. Stop if an undeclared component or incompatible major version is found.
4. Apply Ubuntu security updates, install the fixed Docker package if required, and reboot once into the fixed kernel.
5. Verify SSH, Tailscale, UFW, fail2ban, Docker, Dokploy, Traefik, certificate routing, and all existing containers before proceeding.
6. Merge and deploy the Timescale security change. Confirm database readiness, role reconciliation, extension version, backup scheduling, and application connectivity.
7. Merge and deploy Astarte. Confirm migrations, container health, `/health`, database access, and external routing.
8. Merge and deploy Iris. Confirm the running Node and Brotli versions, container health, `/health`, SSR responses, redirects, compression, and external routing.
9. Apply the infrastructure hardening change only after its Terraform plans are re-reviewed against the now-current state.
10. Observe logs, resource use, restart counts, and scheduled backup status through the agreed stabilization period.

## Rollback

- Host: use Linode console access to select the previous kernel or recover from the pre-change disk snapshot. Do not continue application deployment while host health is uncertain.
- Iris and Astarte: restore their previous repository-variable image SHAs and run the Dokploy deployment verification.
- Timescale before extension upgrade: restore the previous immutable image digest.
- Timescale after extension or catalog upgrade: restore the verified pre-change PostgreSQL backup into a clean PostgreSQL 17 and Timescale instance. Do not attempt an unsupported image downgrade against upgraded data.
- Dokploy or Traefik: restore the control-plane and `/etc/dokploy` backup and verify ACME state before reopening traffic.

Every failed health gate stops the sequence. Later services are not deployed until the current component is healthy or rolled back.

## Implementation status

Branch preparation on 2026-11-14, without production access:

- Iris uses digest-pinned Node 26.13.1 with verified Brotli 1.2.1, aligned React Router 8.3.0 packages, compatible remix-i18next 8, pnpm 11.28.9, and Vitest 4.1.12. The refreshed production lock audit reports no known vulnerabilities and needs no dependency overrides.
- Astarte locks AnyIO 4.14.2, certifi 2026.10.18, and Mako 1.4.2. Python 3.14.9 and uv 0.13.8 images are digest-pinned. Runtime checks verify that certifi, HTTPX, pytest, Ruff, and pip are absent.
- Application builds install current distro package updates and remove APT indexes. Package managers are removed from runtime images.
- CI builds only changed custom service images and retains their JSON scan reports. Each publishing job scans its exact image before push. High/critical findings with listed fixes block publishing; findings without listed fixes are ignored. Build caches remain enabled and are scoped per service.
- Trivy reports inherited Debian findings without listed fixes in both rebuilt application images. These are ignored by the maintainer's publishing policy, not claimed to be remediated.
- TimescaleDB 2.32.0 on PG17 is an explicitly pinned candidate, not an approved deployment. Disposable tests pass an upgrade from 2.28.0, cross-owner permission rejection, role reconciliation, application migrations, dump/restore, restart persistence, and application health/SSR/Brotli checks. Existing installed extensions, including `template1`, are upgraded before database readiness is reported.
- PR validation no longer loads infrastructure secrets for Terraform plans. Trusted `master` push/dispatch runs use a constrained environment target and triggering commit SHA; arbitrary checkout ref, script, and working-directory inputs are removed. Manual `ci` dispatch defaults to plan-only.
- New-host bootstrap uses Docker's signed Jammy repository with declared Engine 29.9.3 and companion package pins. This does not upgrade the existing host because cloud-init metadata is ignored after creation.
- The Dokploy bootstrap target is v0.31.2, published 2026-11-13, using its version-specific release installer. The multi-platform image is published; the Terraform provider remains at 0.4.0. This is a rebuild-only pin update, not an in-place upgrade of the running installation.
- Docker Dependabot coverage includes `postgres/` and `compose/`. A weekly read-only release report covers unmanaged components.
- Janus's public router accepts only the exact `/` path, excluding the vulnerable `/data` Range-header handler. The upstream binary remains unpatched; additional Docker-network isolation is deferred.

### Gates still blocking deployment

- The Timescale candidate scan reports PostgreSQL fixes in 17.12. Upstream's 2.32.0 release limits compatibility to PG17.11; the required 2.32.1 image was not available during preparation. Do not upgrade PostgreSQL independently or suppress the database findings.
- Representative production backup restore, control-plane/ACME recovery checks, installed-host inventory, reviewed state-backed Terraform plans, host package maintenance, reboot, and external routing verification require the approved CI maintenance window. None were executed from this branch.
- Static Terraform validation passes for bootstrap and Dokploy. Production validation stops at the missing chezmoi-managed SSH public-key file; no infrastructure secrets were materialized.
- Non-Dokploy provider constraints and locks are updated to Linode 4.9.0, HTTP 3.6.3, Local 2.9.1, Null 3.3.2, Random 3.9.1, and Time 0.14.2. Signed checksums cover Linux and macOS on amd64 and arm64. Dotenv remains at its current release, 1.2.10; the Dokploy provider remains unchanged at 0.4.0. Bootstrap and Dokploy static validation pass; production validation still requires its managed SSH public key. State-backed upgrade plans have not been run.

## Completion criteria

- Iris runs Node 26.12.1 or newer with the fixed Brotli decoder and fixed production transitive dependencies.
- Astarte runs the fixed AnyIO lock and the production export contains no unintended development packages.
- TimescaleDB is on an explicit fixed PostgreSQL 17-compatible release and digest.
- The host runs the fixed APT, kernel, and Docker versions.
- Dokploy and Traefik versions are recorded and checked against applicable advisories.
- Critical and high Dependabot findings are either resolved or documented as unreachable with reproducible evidence.
- All four services remain healthy across consecutive deployment verification samples.
- External TLS routes, redirects, application health endpoints, database access, and scheduled backups pass.
- Rollback artifacts remain available until the stabilization period ends.
