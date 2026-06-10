# Security

## Reporting a vulnerability

Open a [private security advisory](https://github.com/SymbionicNigel/personal-infrastructure/security/advisories/new),
or email the maintainer. Please do not file public issues for security reports.

## Enabled controls

- **Secret scanning + push protection** — commits pushed with a detectable
  credential are blocked; historical leaks are flagged in the Security tab.
- **Dependabot** — weekly version updates (`.github/dependabot.yml`: GitHub
  Actions, Docker, uv/Python, Terraform, submodules) plus automatic security
  updates for vulnerable dependencies.
- **Branch protection on `master`** — changes land via pull request;
  force-pushes and deletions are disabled and conversations must be resolved.
  Required checks are the `astarte-gate` and `deploy-gate` aggregate jobs: each
  runs on every PR but only fails when a job its workflow actually triggered
  (service tests/build, or the terraform plan) fails. A PR that triggers no CI
  (e.g. a docs change) passes both gates and merges freely.
- **Merged branches are auto-deleted.**

Secrets are never committed in cleartext: environment files and keys are
chezmoi-managed and GPG-encrypted in the private `.secrets` submodule.
