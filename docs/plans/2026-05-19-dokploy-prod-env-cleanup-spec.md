# Drop the Duplicate `production` Environment in the Dokploy Project

**Status:** Spec — design captured; implementation deferred until the upstream `dokploy_environment` data source lands or the cost of carrying the dupe becomes real.

**Source conversation:** Claude Code session transcript at `~/.claude/projects/-home-nigel-krajcer-personal-infrastructure/1314fdd7-9a96-4e40-8643-54939e753554.jsonl` — grep for `data source` or `production env` for the discussion that produced this spec.

**Goal:** Remove the empty, Dokploy-auto-created `production` environment from the `symbionic-services` project so the Terraform-managed `stack` env (which owns `dokploy_compose.stack`) is the only environment in the UI. Do this **without forking the j0bIT/dokploy provider**, by using a Terraform `http` data source to look up the auto-created env's ID and feeding it directly into `dokploy_compose`.

---

## Why this exists

When `dokploy_project.main` is created, Dokploy's `project.create` handler auto-provisions a `production` environment for the new project (see [`apps/dokploy/server/api/routers/project.ts`](https://github.com/Dokploy/dokploy/blob/v0.29.4/apps/dokploy/server/api/routers/project.ts) — `createProject` returns `{ project, environment }` and the env is bound implicitly).

`dokploy_compose.stack` needs an `environment_id`. The j0bIT/dokploy provider (v0.3.0) ships **no data sources at all** — only resources. So Terraform has no native way to read the ID of the auto-created `production` env, and the current workaround is to create a *second* env (`stack`) explicitly and use that.

Result in the Dokploy UI: two envs per project (`production` empty, `stack` populated). Functionally harmless, visually messy, and a small ongoing source of confusion when reading the UI.

---

## Target State

```
Dokploy UI → Projects → symbionic-services
  └── Environments
       └── production       ← used by dokploy_compose.stack
            └── stack (compose)
```

One environment. `dokploy_environment.stack` resource is gone. The auto-created `production` env's ID is discovered at apply time and threaded into `dokploy_compose.stack.environment_id`.

---

## Design

### Look up the auto-created environment via `http` data source

Terraform's built-in `hashicorp/http` provider can issue arbitrary requests at plan/apply time. Dokploy's `project.one` OpenAPI shim accepts `GET /api/project.one?projectId=<id>` with the same `x-api-key` header used everywhere else, and returns the project plus its environments.

```hcl
terraform {
  required_providers {
    dokploy = { source = "j0bIT/dokploy", version = "0.3.0" }
    dotenv  = { source = "germanbrew/dotenv", version = "~> 1.2" }
    http    = { source = "hashicorp/http",   version = "~> 3.4" }
  }
  backend "s3" {}
}

# ... dokploy_project.main unchanged ...

data "http" "project_one" {
  url    = "https://vulcan.${local.hostname_tld}/api/project.one?projectId=${dokploy_project.main.id}"
  method = "GET"
  request_headers = {
    "x-api-key"    = var.DOKPLOY_API_KEY
    "Content-Type" = "application/json"
  }

  # Halt the apply if the shim ever changes shape — better to surface a clear
  # error than silently feed an empty string into compose creation.
  lifecycle {
    postcondition {
      condition     = self.status_code == 200
      error_message = "project.one returned ${self.status_code}: ${self.response_body}"
    }
  }
}

locals {
  project_envs = jsondecode(data.http.project_one.response_body).environments
  production_env_id = one([
    for env in local.project_envs : env.environmentId if env.name == "production"
  ])
}

resource "dokploy_compose" "stack" {
  project_id           = dokploy_project.main.id
  environment_id       = local.production_env_id
  name                 = "stack"
  source_type          = "raw"
  compose_file_content = local.compose_content
  deploy_on_create     = true
}
```

`dokploy_environment.stack` and the corresponding output are deleted.

### Why `http` instead of the dokploy provider

The provider could be forked to add `data "dokploy_environment"`. That's the structurally correct answer but a much larger change: fork, add a data source backed by the same `project.one` call, vendor the fork in Terraform's `required_providers`, and accept the maintenance burden. The `http` data source achieves the same outcome with no fork and no extra surface area to maintain.

If the provider eventually gains a `dokploy_environment` data source upstream, swapping the `data "http"` block for `data "dokploy_environment"` is a 5-line change.

### Response-shape assumption

The plan assumes `project.one` returns an envelope with an `environments` array, each entry having `environmentId` and `name`. This matches the schema we already saw in the provider source for the `Environment` Go struct (`json:"environmentId"`, `json:"name"`). The `postcondition` on the http data source catches a wrong status code; an empty `one([...])` result from a shape change would error with "no element of expression matched" at apply time, which is a clear-enough failure mode.

---

## Migration

This change is destructive in the small: it removes the Terraform-managed `dokploy_environment.stack` and re-targets `dokploy_compose.stack` at the auto-created `production` env. Plan output should be:

| Resource | Action | Notes |
|---|---|---|
| `dokploy_environment.stack` | destroy | Empty env; safe to remove |
| `dokploy_compose.stack` | replace (destroy + create) | `environment_id` is force-new on this resource — recreating the compose stack is unavoidable |
| `dokploy_project.main` | no change | |

Recreating `dokploy_compose.stack` means Dokploy briefly tears down the running services before redeploying them. Acceptable for our current single-`janus` smoke service; will need a smarter migration once real services live in the stack (likely: deploy a parallel stack under `production` first, cut traffic, then destroy the old `stack` env).

### Steps

1. Add `hashicorp/http` to `required_providers` and run `terraform init -upgrade`.
2. Add the `data "http" "project_one"` block, `locals`, and rewire `dokploy_compose.stack.environment_id`.
3. Delete the `dokploy_environment "stack"` resource and the matching `environment_id` output.
4. `terraform plan` and verify the action set matches the table above.
5. Apply during a quiet window; confirm `janus` returns to running under the `production` env in the Dokploy UI.

---

## Out of Scope

- Forking the j0bIT/dokploy provider to add a real `dokploy_environment` data source — tracked separately.
- Restructuring how compose stacks are bound to environments long-term (e.g. one stack per environment vs the current single-stack model).
- Cleaning up the `dokploy_environment.stack` row left behind in Dokploy state if the destroy fails mid-apply — handled by Dokploy's own UI delete.

---

## Open Questions

- Does `project.one` return environments inline, or does it require a separate `environment.all` call keyed by project? The j0bIT provider's `findProject` Go struct suggests inline; verify with a curl during step 1 before relying on the shape. If environments aren't inline, swap to a second `data "http"` block pointed at `environment.all?projectId=...` and adjust `jsondecode` accordingly.
