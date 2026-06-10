# Identity Audit: Decouple Codebase from Maintainer-Specific Strings

## Context

The repository is being licensed Apache-2.0 (see [LICENSE](../../LICENSE) and
[NOTICE](../../NOTICE)) and shared publicly as a reference for the same
stack. The goal of this audit is to make the published code *legible to a
reader who isn't the maintainer*: substitute hardcoded maintainer-specific
strings (hostname, GitHub handle, namespaces, system user) with
configurable variables so the patterns are clear without leaking branding,
and so a reader can adapt the repo without grep-and-replace.

A scan on 2026-06-03 found 76 occurrences across tracked files. Categories
are listed below with the recommended treatment for each.

## Categories and treatment

### 1. Hostname `symbionic.tech` (3 hits in code; ignore plan/docs hits)

**Where:** [linode/modules/dokploy-dns01/main.tf:219,221](../../linode/modules/dokploy-dns01/main.tf), [compose/.env.example:17](../../compose/.env.example) (comment).

**Already-correct pattern:** the compose stack reads `HOSTNAME_TLD` from
[compose/.env.prod](../../compose/.env.prod) (chezmoi-templated). The TF
DNS module duplicates the value as a literal string instead of using the
existing variable.

**Action:** thread `var.HOSTNAME_TLD` (or the module's existing equivalent)
through `dokploy-dns01` and replace the literal `symbionic.tech` and
`*.symbionic.tech` with interpolations. Drop the comment example in
`compose/.env.example` to a placeholder like `example.com`.

### 2. TF resource names (`symbionic-services`, `symbionic-tech-*`)

**Where:** [linode/environments/dokploy/main.tf:40](../../linode/environments/dokploy/main.tf)
(Dokploy project name), encrypted `backend.hcl` (S3 bucket name in
`.secrets/`), plan doc at
[docs/plans/2026-03-18-dokploy-provider-fork-plan.md:48](../../docs/plans/2026-03-18-dokploy-provider-fork-plan.md).

**Action:** promote `dokploy_project_name` to a TF variable with a generic
default like `services`. Bucket name change requires re-bootstrap (out of
scope; document for the next bootstrap). Leave the plan doc alone — plans
are historical records.

### 3. System user `symbionic_dokploy_user` (~30 hits)

**Where:** [linode/modules/dokploy/user_data.sh](../../linode/modules/dokploy/user_data.sh),
[linode/modules/dokploy/main.tf](../../linode/modules/dokploy/main.tf),
[linode/modules/acme-backup/main.tf](../../linode/modules/acme-backup/main.tf),
[linode/modules/dokploy-dns01/main.tf](../../linode/modules/dokploy-dns01/main.tf).

This is the cloud-init created sudoer used for SSH-tunneled Dokploy admin
calls. Hardcoded throughout.

**Action:** add `var.deploy_user` (default `"deploy"` or similar generic
name) to the `dokploy` module, surface it as an output, and pass it into
the modules that SSH back in (`acme-backup`, `dokploy-dns01`). Touches
many files but each change is mechanical.

### 4. Personal name / GitHub handle `SymbionicNigel`

**Where:** [.gitmodules](../../.gitmodules) (SSH submodule URLs);
[LICENSE](../../LICENSE) (copyright line); [NOTICE](../../NOTICE)
(maintainer attribution + trademark reservation).

**Action:** *do nothing.* These are correct as written:
- `.gitmodules` URLs point to the actual repos under that handle; rewriting
  them would break the submodule fetch.
- Copyright and trademark attribution must name the actual owner; that's
  what licenses are *for*.

### 5. Email `nphilmont2010@gmail.com`

**Where:** Only in `.claude/CLAUDE.md` (user's private instructions; not
tracked in this repo) and previously in
[astarte/pyproject.toml](../../astarte/pyproject.toml) authors — already
removed in the pyproject pass that accompanied this plan.

**Action:** verify no tracked file contains the email after this plan
lands. Add a grep gate to the audit script (see Verification).

## Out of scope

- The encrypted `.secrets/` submodule. It is private by design; anything in
  there does not appear in the public clone.
- Historical plan documents under [docs/plans/](.). Plans are immutable
  records; rewriting them retroactively is dishonest.
- Renaming the GitHub *repository* itself or moving it under a new org.
- Any change requiring re-bootstrap of TF state (e.g., S3 bucket rename).
  Document those as bootstrap-time decisions for next time.

## Verification

After the work in this plan is executed:

1. **Targeted grep returns zero hits in code (allowed: LICENSE, NOTICE,
   .gitmodules, docs/plans/*):**
   ```bash
   git grep -InE "symbionic|nphilmont" \
     -- ':!LICENSE' ':!NOTICE' ':!.gitmodules' ':!docs/plans/*'
   ```
   Expected output: empty.
2. **No reference to the literal hostname outside the compose template
   source:**
   ```bash
   git grep -In "symbionic\.tech" -- ':!.secrets'
   ```
   Expected: empty (the actual TLD lives only in the chezmoi template,
   which is in the encrypted submodule).
3. **TF plan still works** after variable substitutions:
   `cd linode/environments/dokploy && terraform init -backend-config=backend.hcl && terraform plan`
   Expected: no resource replacements unless intended.
4. **Compose still renders correctly** with the new variables:
   `GHCR_OWNER=symbionicnigel HOSTNAME_TLD=symbionic.tech ASTARTE_IMAGE_TAG=latest docker compose -f compose/docker-compose.yml config`
   Expected: same output as before the audit.

## Suggested execution order

1. TF Dokploy project name variable.
2. TF `deploy_user` variable across the three modules.
3. TF DNS hostname interpolation in `dokploy-dns01`.
4. Run verification grep and TF plan. Commit per category.

Each step is independently mergeable.
