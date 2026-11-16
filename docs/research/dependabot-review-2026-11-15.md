# Dependabot review, 2026-11-15

## Scope and baseline

All 11 open Dependabot PRs are accounted for below. The reviewed master is `a941a7e40dbd2e330f40be45b34f9a3bce56dc54`, the merged security PR #64. Its [master CI run](https://github.com/SymbionicNigel/personal-infrastructure/actions/runs/43757554315) succeeded, including both Production and Dokploy applies.

These are recommendations, not submitted approvals, closures, or merges. No workflows were dispatched, dependencies installed, or infrastructure changed for this review. Production access is not authorized. Merging application updates to master invokes production CI and is therefore a separate execution decision.

## Complete disposition

| PR | Actual change | Recommendation | Evidence and qualification |
| --- | --- | --- | --- |
| [#46](https://github.com/SymbionicNigel/personal-infrastructure/pull/46) | React Router 8.1.0 to 8.3.0 | Close as superseded by #64 | Master already aligns the React Router packages at 8.4.0. Do not merge this older standalone target. |
| [#58](https://github.com/SymbionicNigel/personal-infrastructure/pull/58) | Vitest 4.1.9 to 4.1.11 | Close as superseded by #64 | Master already uses 4.1.12. |
| [#60](https://github.com/SymbionicNigel/personal-infrastructure/pull/60) | AnyIO 4.14.1 to 4.14.2 | Close as incorporated by #64 | Master already locks 4.14.2. |
| [#66](https://github.com/SymbionicNigel/personal-infrastructure/pull/66) | setup-uv 8.2.0 to 10.3.3 | Suitable to merge | Current CI passes application checks, image build, and type generation. Existing inputs remain supported. Cache-default changes are explained below. |
| [#67](https://github.com/SymbionicNigel/personal-infrastructure/pull/67) | Tailscale provider lock 0.29.2 to **0.30.0** | Hold for corrected description and reviewed CI plan | Title/body advertise 0.29.3, but the actual lock selects 0.30.0. Terraform jobs were skipped; the green gate is not plan evidence. |
| [#68](https://github.com/SymbionicNigel/personal-infrastructure/pull/68) | Python image 3.14.9 to 3.15.0 | Hold | Production image fails to install locked native dependencies. Keep the current 3.14.9 runtime until the full dependency/runtime upgrade builds and passes. |
| [#69](https://github.com/SymbionicNigel/personal-infrastructure/pull/69) | Five Python updates | Suitable to merge on Python 3.14.9 | Application checks, image build, and type generation pass. FastAPI breaking changes do not intersect the current health-only application. This does not fix #68. |
| [#70](https://github.com/SymbionicNigel/personal-infrastructure/pull/70) | Vite 8.3.2 to 8.3.3 | Suitable to merge, or supersede after #73 is validated | Current CI passes. Includes development-server filesystem access fixes. #73 targets the later 8.3.8, but is not ready yet. |
| [#71](https://github.com/SymbionicNigel/personal-infrastructure/pull/71) | Transitive Hono 4.12.25 to 4.13.18 | Suitable to merge | Current CI passes. Security fixes verified in upstream source. Not included in #73. |
| [#72](https://github.com/SymbionicNigel/personal-infrastructure/pull/72) | Transitive @hono/node-server 1.19.14 to 1.19.19 | Suitable to merge | Current CI passes. Backslash/path and static-serving security fixes verified in upstream source. Not included in #73. |
| [#73](https://github.com/SymbionicNigel/personal-infrastructure/pull/73) | Sixteen grouped Iris updates | Hold for formatting/configuration repair and complete CI | Lint fails on README table formatting. Biome also reports an outdated schema URL. Later checks/build did not complete. |

## Compatibility findings

### #66: setup-uv

Reviewed upstream [8.2.0 to 10.3.3](https://github.com/astral-sh/setup-uv/compare/v8.2.0...v10.3.3), including the shipped [action metadata](https://github.com/astral-sh/setup-uv/blob/68559e99cc807c1eb7e9238fd43a15bba460eec2/action.yml) and [input implementation](https://github.com/astral-sh/setup-uv/blob/68559e99cc807c1eb7e9238fd43a15bba460eec2/src/utils/inputs.ts).

- The action uses Node 24. Both repository call sites run on GitHub-hosted Ubuntu 26.04 and passed CI.
- Explicit uv 0.13.8, Python 3.14.9, `enable-cache: true`, and the existing dependency glob remain valid. A job's `defaults.run.working-directory` does not change the action's own working directory; the current `astarte/uv.lock` glob still resolves from the repository root.
- `prune-cache` defaults from true to false, persisting the full cache. `save-cache` defaults to auto, which still saves for the repository's push/PR events. Caching remains enabled; no cache-busting input is needed.
- Automatic caching excludes several sensitive event types, but these call sites explicitly enable caching and do not use those events. The download manifest now prefers Astral's mirror with GitHub fallback.

### #67: actual Tailscale 0.30.0 update

Reviewed [0.29.2 to 0.30.0](https://github.com/tailscale/terraform-provider-tailscale/compare/v0.29.2...v0.30.0), not merely the release advertised in the PR.

- ACL policy validation now calls Tailscale during planning. The real CI identity must be able to perform that validation.
- The tailnet-key update path handles a missing key without dereferencing it.
- Unified DNS split configuration changes from a list to a set, and tailnet settings add `route_selection` with a conflict against deprecated `regional_routing_on`.
- This repository declares ACLs, legacy DNS preferences, and tailnet keys, not the changed unified DNS or tailnet-settings resources. Static review found no required configuration migration for those declarations.
- A trusted, explicitly plan-only CI run against the exact reviewed change is still required. Review ACL/key changes and resource actions before permitting a master apply. Do not enable infrastructure secrets for Dependabot-controlled code as a shortcut.

### #68 and #69: Python

[#68's failed production build](https://github.com/SymbionicNigel/personal-infrastructure/actions/runs/43757685605/job/132945362570) attempts native builds for `httptools`, `pydantic-core`, and `uvloop`; compiler/linker tools are absent. The lock does not supply CPython 3.15 wheels for those selected versions. Test CI still selects Python 3.14.9, so its passing test job does not validate Python 3.15.

#69 updates Alembic 1.20.0 to 1.20.1, FastAPI 0.143.0 to 0.162.5, SQLModel 0.0.48 to 0.0.49, pytest 9.1.1 to 9.2.0, and Ruff 0.17.0 to 0.17.5. Its lock retains the same three native dependency versions and does not resolve #68.

The [FastAPI release notes](https://github.com/fastapi/fastapi/blob/5add7a458d629b07311d48261f696b5ac2bb9a5f/docs/en/docs/release-notes.md) include removal of deprecated constructor/request-parameter extras, root-path deprecation, and changed omitted/default/null handling for request bodies, forms, and parameter models. Astarte uses none of those affected interfaces: its constructor supplies title/lifespan, and its routes expose liveness and a dependency-injected `SELECT 1`. FastAPI's new AnyIO minimum is satisfied by the retained 4.14.2 lock. The upstream pytest-xdist compatibility note is not applicable to Astarte's declared test dependencies.

The safe disposition for #68 is an explicit hold, not adding compilers to runtime, dropping hash verification, or assuming that FastAPI's Python 3.15 support makes every dependency compatible. Newer native packages have CPython 3.15 wheels, but the locked Pydantic requires its exact existing pydantic-core version. Moving to those wheels requires a coordinated dependency upgrade with its own runtime validation.

### #70 through #73: overlapping Iris locks

Hono and its Node adapter enter this lock through `@modelcontextprotocol/sdk`; they are not direct Iris dependencies. Iris currently serves through React Router Serve/Express. This reduces current exposure but does not justify omitting the fixes.

The pinned [Hono validator](https://github.com/honojs/hono/blob/f6fbaf0299c48eea9e656e03e2ffe7ac755e8823/src/validator/validator.ts) consistently selects by media type, and [body-limit](https://github.com/honojs/hono/blob/f6fbaf0299c48eea9e656e03e2ffe7ac755e8823/src/middleware/body-limit/index.ts) uses a bounded growing buffer rather than retaining every transfer chunk. The pinned Node adapter [rejects raw path backslashes](https://github.com/honojs/node-server/blob/56c392f2cd7139683c8058021afbcb9c0ca16e7d/src/request.ts) and [guards static-path decoding](https://github.com/honojs/node-server/blob/56c392f2cd7139683c8058021afbcb9c0ca16e7d/src/serve-static.ts).

The exact #73 lock still contains Hono **4.12.25** and @hono/node-server **1.19.14**. Do not close #71 or #72 as superseded by #73. After either security PR merges, rebase the remaining Iris PRs and verify that their final lock retains both security targets.

All 16 #73 targets:

| Dependency | Target |
| --- | --- |
| @ark-ui/react | 5.40.0 |
| @react-router/node | 8.5.1 |
| @react-router/serve | 8.5.1 |
| i18next-browser-languagedetector | 8.3.0 |
| isbot | 5.2.3 |
| lucide-react | 1.72.0 |
| react | 19.3.1 |
| react-dom | 19.3.1 |
| react-router | 8.5.1 |
| @biomejs/biome | 2.6.7 |
| @react-router/dev | 8.5.1 |
| @testing-library/user-event | 14.6.10 |
| @types/node | 26.6.6 |
| @vitejs/plugin-react | 6.3.0 |
| drizzle-orm | 0.45.4 |
| vite | 8.3.8 |

The [React Router changelog](https://github.com/remix-run/react-router/blob/a2783e6612b8424e9e1a5e3e2d69435805ee51dc/packages/react-router/CHANGELOG.md) confirms view-transition APIs are deprecated but retained, plus manifest-work bounds and turbo-stream validation fixes. Iris does not use the deprecated transition APIs or unsafe router contexts. All four declared Router packages remain aligned. Lucide usage is limited to ChevronDown/ChevronRight; no broad icon migration is indicated by current imports.

[#73's failing job](https://github.com/SymbionicNigel/personal-infrastructure/actions/runs/43758059213/job/132946440096) reports exactly one formatting error in `iris/README.md` and informational schema drift in `iris/biome.json`. Update the schema to 2.6.7 and apply the formatter's table output, then rerun the complete existing lint/typecheck/test/build/license/audit/image-scan sequence. Passing type generation alone is not evidence that the grouped runtime update is ready.

## Review boundaries

- Prepared so far on this branch: #66's two action changes and #69's locked versions/hashes. The five corresponding minimums in `pyproject.toml` and the lock's requirement metadata are aligned with those versions. The Python runtime remains 3.14.9; #67 and #68 are not applied.
- Existing offline/no-sync Python lint, formatting, and the one local test pass, but the available environment uses older installed dependencies and Python 3.14.5. Those local results do not validate the updated lock or replace fresh CI.
- Current reviewed heads: #66 `dee77f7`, #67 `875f0be`, #68 `6bd9341`, #69 `d67209b`, #70 `02e46e2`, #71 `46c8f46`, #72 `d004195`, #73 `41bc901`.
- The package recommendations rely on existing CI results and source review, not a newly installed local dependency environment. Rebased or consolidated locks require fresh checks.
- Shell-pinned Docker and Dokploy versions are assessed separately in [Dokploy upgrade readiness](./dokploy-upgrade-readiness.md). The `dotfile-utils` submodule is not populated in this worktree, so its installer pins were not reviewed.
- Keep `j0bIT/dokploy` 0.4.0. Preserve the accepted Timescale report-only scan deferral and the policy of ignoring image findings without listed fixes.
