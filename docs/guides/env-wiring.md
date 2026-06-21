# Service environment variable wiring

How environment variables are sourced, named, and delivered to each compose
service in dev and in prod. This is a steady-state reference: follow it when
adding a new service or a new env-bearing concern to an existing service.

## Model

One compose file at `compose/docker-compose.yml` defines every service for both
environments. A second file at `compose/docker-compose.override.yml` is auto-
loaded by `docker compose up` locally and is never shipped to prod. The two
environments source secrets through different mechanisms but the base compose
file does not branch on environment.

- **Prod.** Terraform reads per-service `.env.<service>.prod` files on the
  operator's machine via the `germanbrew/dotenv` data source, merges them into
  one map, and pushes that map to Dokploy's compose-scoped environment via the
  Dokploy provider. Dokploy materializes the map as a `.env` file beside the
  rendered compose; compose's standard `${VAR}` interpolation resolves
  references at deploy time.
- **Dev.** The override declares one `env_file:` per service pointing at
  `compose/.env.<service>`, which chezmoi has rendered. Compose loads it at
  container start. Each service gets only the keys it owns.

The base file declares `env_file: [{ path: .env, required: false }]` per
service. In prod that file is the Dokploy-written stack env; in dev it is
typically absent and the override's per-service `env_file:` supplies values
instead. `required: false` makes the dev case clean.

## Naming

Files live flat in `compose/` until volume warrants a subdirectory:

```
compose/.env.<service>          # dev defaults, plaintext, gitignored
compose/.env.<service>.prod     # prod secrets, plaintext on operator box only, gitignored
```

The `.prod` suffix is the only environment suffix used. Add other environment
suffixes (`.staging`, `.testing`) only when a real second deploy target exists.

Aggregated multi-record files (multiple tenants, multiple API keys for the same
service) follow the same shape with a sub-scope qualifier:

```
compose/.env.<service>.<scope>          # e.g. compose/.env.astarte.tenants
compose/.env.<service>.<scope>.prod
```

## Base compose responsibilities

The base file is the union of every service's runtime contract. It must not
embed environment-specific values.

- `environment:` blocks contain **only literal constants** that are the same in
  every environment (`POSTGRES_HOST: postgres`, `POSTGRES_PORT: '5432'`, fixed
  log levels, etc.). They do not enumerate `${VAR}` keys — those collide with
  override `env_file:` per compose precedence (`environment:` beats `env_file:`
  on conflict).
- Each service that consumes env declares `env_file:` listing the compose-level
  `.env` with `required: false`:
  ```yaml
  env_file:
    - path: .env
      required: false
  ```
  This is the hook Dokploy's stack env plugs into in prod and the no-op slot in
  dev.
- `${VAR}` references that survive in the base file are limited to deploy
  wiring Terraform substitutes via `templatefile()`: `HOSTNAME_TLD`, image
  tags, GHCR owner. These are not secrets and are computed by Terraform at
  apply time.

## Override responsibilities

The override is dev-only and exists to layer per-service env files onto the
base. For each service:

```yaml
services:
  <service>:
    env_file:
      - path: .env.<service>
        required: true
      # plus any aggregated files this service owns:
      - path: .env.<service>.<scope>
        required: true
```

Compose merges `env_file:` lists additively between base and override, so the
base's `path: .env required: false` entry stays in place and the override's
entries append. No `environment:` block is declared in the override for these
keys; doing so would shadow the env files.

The override is also where local-only concerns live (host port mappings, dev
build targets, source bind mounts). Keep those separate from env wiring.

## Chezmoi pattern

One partial per service holds the schema; two thin wrappers render dev and
prod variants. Bitwarden is the prod secret source — partials never carry
literal prod secrets, and `.chezmoitemplates/` files are not covered by the
`encrypted_` prefix.

For service `<svc>`:

- `.secrets/.chezmoitemplates/<svc>-env` — plaintext partial. Takes `"local"`
  or `"production"` as the dot context. Dev branch emits literal defaults
  (e.g. `local-dev-only`). Prod branch calls `bitwardenFields` (or the
  repo's standard BW helper) per secret. Same key names in both branches.
- `.secrets/compose/dot_env.<svc>.tmpl` — plaintext wrapper, renders to
  `compose/.env.<svc>`. One line: `{{ template "<svc>-env" "local" -}}`.
- `.secrets/compose/dot_env.<svc>.prod.tmpl` — plaintext wrapper, renders to
  `compose/.env.<svc>.prod`. One line: `{{ template "<svc>-env" "production" -}}`.

When a service grows an aggregated scope (tenants, API keys, etc.), add a
second partial (`<svc>-<scope>-env`) and a second pair of wrappers. The shape
is identical; only the data model inside the partial differs.

Whole-file encryption (`encrypted_dot_env.<svc>.prod.tmpl`) is available if
you ever need to commit a literal secret rather than fetch from BW. The
default is plaintext wrappers + BW lookup; reach for `encrypted_` only when
BW is not the right source.

## Terraform pattern

In `linode/environments/dokploy/main.tf`:

- One `data "dotenv"` per service reading `compose/.env.<service>.prod`. Use
  the dotenv provider so values land in TF state without being declared as
  TF variables.
- A `locals` block merges per-service maps into one `compose_env` map.
- A Dokploy provider resource (or, if the provider lacks one, a
  `terraform_data` + `curl` against the compose env endpoint, following the
  redeploy pattern already in `main.tf`) writes `compose_env` to Dokploy's
  compose-scoped environment.
- `templatefile()` on the compose YAML substitutes only `HOSTNAME_TLD`, image
  tags, and `GHCR_OWNER`. No per-service secret enters `templatefile()`.

The dokploy `.env.example` carries only genuinely TF-scoped values: Dokploy
API key, backup bucket credentials, GHCR PAT. Service secrets do not appear.

## Adding a new service

1. Define the service in `compose/docker-compose.yml`. Put only literal
   constants in `environment:`. Declare
   `env_file: [{ path: .env, required: false }]`.
2. Add a `services.<svc>` block in `compose/docker-compose.override.yml`
   with an `env_file:` entry for `.env.<svc>` (`required: true`). Add any
   local-only concerns (ports, build, mounts).
3. Create `.secrets/.chezmoitemplates/<svc>-env` with `local` and `production`
   branches.
4. Create `.secrets/compose/dot_env.<svc>.tmpl` and
   `.secrets/compose/dot_env.<svc>.prod.tmpl` invoking the partial.
5. In `linode/environments/dokploy/main.tf`, add a `data "dotenv"` reading
   the new `.prod` file and merge its `entries` into the aggregated map fed
   to the Dokploy env resource.
6. Run `czm apply` to render the new env files, then `docker compose up` to
   verify the dev path and `terraform plan` to verify the prod push.

## Known properties

- **TF state holds rendered prod values.** The `dotenv` data source records
  values in TF state. The S3 backend is encrypted at rest. If state
  readability becomes a concern, switch the push to a `terraform_data` +
  `curl` pattern that keeps values out of state.
- **`.prod` files exist only on the operator box.** They are rendered by
  `czm apply` from the chezmoi source, are gitignored, and are never shipped
  to the server. Their only consumer is the local `terraform apply`.
- **Compose runtime ignores `.prod` filenames.** The base file references
  `.env`; the override references `.env.<svc>`. No mechanism in compose loads
  a `.prod`-suffixed file, so the presence of those files in `compose/` has
  no runtime effect.
- **Base `environment:` blocks do not enumerate secret keys.** Adding a
  `${VAR}` entry there reintroduces the precedence conflict that prevents
  override `env_file:` values from taking effect in dev.
