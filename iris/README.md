# iris

React Router v7 (framework mode) web frontend — the visible face of the stack,
served at `iris.<HOSTNAME_TLD>` in prod and `localhost:3000` in dev. The apex +
`www` redirect to it; undefined subdomains land on its branded 404.

## Stack

- **React Router v7** (SSR, framework mode) on **Vite 8 / Node 24**, ESM.
- **Panda CSS** (zero-runtime tokens/recipes) + **Park UI** (Ark UI) components,
  with a 60s vintage dark palette.
- **i18next** + remix-i18next middleware (SSR-aware locale; English seed).
- **Biome** (lint + format), **Vitest** + React Testing Library.
- Self-hosted fonts (SIL-OFL, plus one Apache-2.0), synced via `pnpm fonts:sync`
  — see `public/fonts/LICENSES.txt`.

## Scripts

| Script | Purpose |
|---|---|
| `pnpm dev` | Dev server (HMR) at `localhost:3000` |
| `pnpm build` | Production build (`build/client` + `build/server`) |
| `pnpm start` | Serve the production build |
| `pnpm typecheck` | `react-router typegen && tsc` |
| `pnpm lint` / `pnpm format` | Biome check / write |
| `pnpm test` | Vitest run |
| `pnpm fonts:sync` | Re-download the self-hosted fonts |
| `pnpm typegen:api` | Regenerate `app/generated/api.d.ts` from `../astarte/openapi.json` |
| `pnpm typegen:db` | `drizzle-kit pull` against `$DATABASE_URL` → `app/generated/{schema,relations}.ts` |

## Generated types

`app/generated/` is committed and verified by CI's `typegen` job:

- `api.d.ts` — `openapi-typescript` over `astarte/openapi.json`. Regenerate after
  any astarte route/model change (see `astarte/README.md`).
- `schema.ts` / `relations.ts` — `drizzle-kit pull` against a Postgres that has
  astarte's alembic migrations applied. Regenerate after any astarte migration.
  `typegen:db` needs `$DATABASE_URL`; locally point it at the compose Postgres.

CI fails on `git diff --exit-code` against these files; rerun the matching
script and commit.

## Docker

`Dockerfile` has three targets: `dev` (HMR, source bind-mounted), `build`
(intermediate), and `runtime` (default — slim, prod deps only, non-root,
container healthcheck on `/health`). The compose override runs the `dev` target
locally; the runtime image is what CI builds and Dokploy deploys.
