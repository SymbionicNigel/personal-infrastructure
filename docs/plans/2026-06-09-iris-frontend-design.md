# iris — React Router v7 frontend (replaces `solid/`)

## Context

The `solid/` directory was an early SolidStart playground that never left the
"dev playing around" phase. We're replacing it with a real frontend service,
`iris` (Greek messenger goddess / rainbow — "the visible link between gods and
mortals," the visible face of the stack, fitting the repo's pantheon naming).

This first cut delivers a **scaffold + design system + a few real pages + full
deploy wiring**, following the existing `astarte`/`janus` service patterns so it
slots into the Dokploy + Traefik + Terraform + CI pipeline already in place.

**Auth is explicitly out of scope.** It spans UI + API + Traefik and affects
integratability, so it gets its own investigation/spec later. No DB this round.

### Locked decisions

- **Framework:** React Router v7, framework mode (the official Remix successor;
  SSR by default + per-route `clientLoader`/`clientAction`).
- **Build tooling:** Vite (`@react-router/dev` plugin; Rollup prod / esbuild
  dev). No legacy bundler — no webpack, no Remix classic compiler. ESM, Node 24.
- **Styling:** Panda CSS (zero-runtime, type-safe tokens/recipes via
  `panda codegen`) + Park UI (own-your-components shells over Ark UI, added via
  CLI). All deps MIT.
- **Icons:** `lucide-react` (ISC).
- **Lint/format:** Biome — one fast tool for lint + format, mirroring astarte's
  `ruff` philosophy (single config, fast). ESLint + Prettier is the fallback.
- **Testing:** Vitest + React Testing Library, run in CI like astarte's pytest.
- **i18n:** `i18next` + `react-i18next` + `remix-i18next` (SSR-aware). v1 ships
  English with detection + structure in place; new languages = new JSON.
- **Package manager:** pnpm (repo standard).
- **Pages (v1):** landing/index, resume, design-system showcase (`/styleguide`),
  styled 404 catch-all.
- **Service name / routing:** iris reachable at `iris.<HOSTNAME_TLD>` (prod) and
  `localhost:3000` (local). Apex + `www` redirect to iris; undefined subdomains
  redirect to the branded 404 page.

## Salvage from `solid/` (before deleting it)

- **60s vintage dark palette** from `solid/src/themes.ts` → Panda semantic
  tokens. bg.default `#271e16`, bg.paper `#31281d`, primary `#669fb2`, secondary
  `#87aa7e`, warning `#edbf02`, error `#e06c21`, info `#0288d1`, success
  `#005427`, divider `#2f201b`. Dark mode default.
- **Layout component concepts** from `solid/src/components/`: `headerBar`,
  `sideMenu`, `breadCrumbs` — reimplemented as Panda/Ark layout components.
- **Resume route** concept (`solid/src/routes/resume.tsx`) — was a placeholder;
  rebuild as a real content page.
- **NOT salvaged: the Mantana font.** Licensed "Shareware, Non-Commercial"
  (`solid/public/fonts/mantana-font/info.txt`), which conflicts with this repo's
  Apache-2.0 publication. Replace with a self-hosted SIL-OFL retro/display face
  for headings + a neutral OFL/system sans for body (final face chosen during
  build / visual review). Keep the self-hosted `@font-face` approach (no
  external font CDN).

## Architecture

New top-level `iris/` directory (mirrors `astarte/` as a self-contained service
with its own README, Dockerfile, and CI).

```text
iris/
  app/
    root.tsx               # html shell, font + panda css imports, theme
    routes.ts              # config-based route table (@react-router/dev/routes)
    routes/
      _index.tsx           # landing page
      resume.tsx           # resume content page
      styleguide.tsx       # token + Park UI component showcase
      $.tsx                # splat → styled 404
      health.tsx           # resource route, 200 OK for healthchecks
    components/
      layout/              # headerBar, sideMenu, breadCrumbs
      ui/                  # Park UI components added via CLI (owned source)
    i18n.ts                # i18next config (shared)
    i18next.server.ts      # remix-i18next server instance + detection
    locales/en/common.json # translation namespaces (en seed)
    styles/app.css         # @layer order + font-face + panda entry
    theme/                 # panda token overrides (salvaged palette)
  panda.config.ts          # include globs, Park UI preset, token extensions
  postcss.config.cjs
  biome.json               # lint + format config
  vitest.config.ts         # test runner (jsdom env)
  package.json             # scripts incl. "prepare": "panda codegen"
  tsconfig.json
  vite.config.ts           # @react-router/dev + panda postcss
  Dockerfile               # multi-stage: dev / build / runtime (mirrors astarte)
  README.md
  .dockerignore
```

`package.json` scripts: `dev`, `build`, `start`, `typecheck`, `lint`
(`biome check`), `format` (`biome format --write`), `test` (`vitest run`),
`prepare` (`panda codegen`).

### Routing / data model

- Config-based routing in `app/routes.ts`. SSR on by default.
- Pages are static content this round; demonstrate one `clientLoader` on
  `/styleguide` (or resume) to establish the SSR + client-loader pattern, even
  though data is trivial now.
- `/health` resource route returns `200` for the Traefik + container healthcheck.

### Styling system

- `panda.config.ts`: base + Park UI presets, `include` globs over `app/`,
  `jsxFramework: 'react'`, dark mode default, salvaged palette as
  `theme.extend.tokens` + `semanticTokens`.
- `panda codegen` (wired to `prepare` + Vite watch) generates the typed
  `styled-system/` — the source of type safety.
- Park UI components pulled into `app/components/ui/` via its CLI; treated as
  editable starting points. Icons via `lucide-react`.

### i18n

- `remix-i18next` provides an SSR-aware i18next instance; locale detected from
  the request (header/cookie) and passed through the RR7 loader chain.
- Strings live in `app/locales/<lng>/<namespace>.json`. Ship `en` only in v1;
  the structure makes additional languages additive.

## Deploy wiring (mirrors astarte/janus exactly)

1. **`iris/Dockerfile`** — three targets like `astarte/Dockerfile`:
   - `dev`: `node:24-slim`, `pnpm install`, `react-router dev` (HMR), source
     bind-mounted, EXPOSE 3000.
   - `build`: install + `pnpm build` → `build/client` + `build/server`.
   - `runtime` (default): slim node, prod deps only, non-root UID 1000,
     `HEALTHCHECK` hitting `/health` via node, `CMD react-router-serve
     ./build/server/index.js`, EXPOSE 3000.

2. **`compose/docker-compose.yml`** — add an `iris` service following the
   `astarte` block:
   - `image: ghcr.io/${GHCR_OWNER}/iris:${IRIS_IMAGE_TAG}`.
   - primary router: rule `Host(iris.${HOSTNAME_TLD})`, websecure, tls
     letsencrypt, loadbalancer healthcheck `/health`, server.port `3000`.
   - apex/www redirect router: rule
     `Host(${HOSTNAME_TLD}) || Host(www.${HOSTNAME_TLD})`, websecure, tls
     letsencrypt, plus a `redirectregex` middleware (permanent) to
     `iris.${HOSTNAME_TLD}` (escape `$` as `$$` in compose).
   - catch-all 404 redirect router: `HostRegexp(...)` with low `priority` (e.g.
     1) so real routers always win; `redirectregex` (302) to
     `iris.${HOSTNAME_TLD}/404`. Wildcard cert `*.${HOSTNAME_TLD}` covers
     undefined single-level subdomains.
   - Keys alphabetical per the repo's mapKeyOrder linter.

3. **`compose/docker-compose.override.yml`** — add `iris`: `build` (context
   `../iris`, target `dev`), `image: iris:dev`, `ports: ['3000:3000']`, source
   bind-mount for HMR. Traefik redirect labels are inert locally (no local
   proxy) — expected per the asymmetric routing model in AGENTS.md.

4. **Terraform** — `linode/environments/dokploy/main.tf`: add
   `IRIS_IMAGE_TAG = var.IRIS_IMAGE_TAG` to the `templatefile()` vars;
   `variables.tf`: add `variable "IRIS_IMAGE_TAG"` (default `"latest"` so
   plan/apply works before the first build).

5. **CI** — `.github/workflows/iris.yml` mirroring `astarte.yml`: `changes`
   (paths-filter on `iris/**` + the workflow), `test` (pnpm install → typecheck
   → `biome check` → `vitest run` → `pnpm build` → npm license audit allowing
   only permissive licenses), `build-and-push` (reuses `_build-push.yml` with
   `service: iris`), and an `iris-gate` required check. The reusable build
   records `IRIS_IMAGE_TAG`; the `collect` job in `deploy.yml` already
   auto-discovers every `*_IMAGE_TAG` variable, so no change is needed there to
   render it.

6. **`.github/workflows/deploy.yml`** — extend the astarte-style dedupe so an
   iris-touching master push is left to the `workflow_run` deploy (avoid
   double-apply): add `iris` to the `changes` filter, add `iris` to the
   `workflow_run.workflows` list, and widen the `collect`/`prod`/`dokploy` skip
   conditions to also exclude `push && iris == 'true'`.

7. **`.github/dependabot.yml`** — add an `npm` ecosystem entry for `/iris` and a
   `docker` entry for `/iris` (base image), grouped/labelled like the astarte
   entries. Keep all YAML map keys alphabetical (root: `updates` before
   `version`).

8. **Docs** —
   - `README.md`: add `iris.localhost` to the hosts list; replace the "Solid"
     module bullet with "Iris"; drop the now-resolved "Apex redirect + catch-all
     404 router" item from Future Decisions; add error tracking (client +
     server, self-hosted Sentry/GlitchTip) to the Observability baseline Future
     Decisions item.
   - `AGENTS.md`: no plan-file references (per repo convention).

9. **Remove `solid/`** once the palette/concepts above are captured.

## Build order

1. Scaffold `iris/` (create-react-router) + pnpm + tsconfig/vite + Biome.
2. Panda + Park UI install, codegen wired, salvaged palette tokens, fonts.
3. i18n setup (remix-i18next + en locale).
4. Layout components (header/side/breadcrumbs) + `app.css` layers.
5. Pages: `_index`, `resume`, `styleguide`, `$` (404), `health`.
6. Vitest + RTL setup + smoke tests.
7. Dockerfile (3 targets) + `.dockerignore`; verify local dev via compose.
8. Terraform var + compose service/labels (incl. apex/www + catch-all redirects).
9. CI workflow + deploy.yml dedupe + dependabot.
10. Docs update; delete `solid/`.

## Verification

- **Local app:** `cd iris && pnpm install && pnpm dev` → pages render at
  `localhost:3000`; `/styleguide` shows tokens + Park UI components; a bad token
  reference fails `pnpm typecheck`; `pnpm test`, `biome check`, and `pnpm build`
  all pass.
- **Local container:** from `compose/`, `docker compose up --build iris` →
  `curl -f localhost:3000/health` returns 200; pages load.
- **CI (PR):** iris workflow runs typecheck/lint/test/build/license-audit and a
  no-push validation image build; `deploy.yml` plans without erroring on the new
  `IRIS_IMAGE_TAG`.
- **Prod (post-merge, manual check):** `iris.<HOSTNAME_TLD>` serves; the apex
  and `www.<HOSTNAME_TLD>` 301 → iris; an undefined subdomain 302 →
  `iris.<HOSTNAME_TLD>/404` showing the branded page.

## Out of scope (future specs)

- **Auth** across UI/API/Traefik (own investigation; pulls in the DB decision).
- **Persistent data tier** / any DB-backed feature.
- **Error tracking / observability** — error tracking is desired (client +
  server); it belongs to the existing Observability baseline epic (README Future
  Decisions: Loki + Grafana + blackbox_exporter), extended to include a
  self-hosted Sentry/GlitchTip. Not built this round.
