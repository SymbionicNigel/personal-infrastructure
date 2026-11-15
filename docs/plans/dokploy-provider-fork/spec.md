# Dokploy Provider Fork: `dokploy_api_key` Resource

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans
> to implement this plan task-by-task.

**Goal:** Fork `j0bIT/terraform-provider-dokploy` to add a
`dokploy_api_key` resource that creates an admin account and API key
during `terraform apply`, enabling single-stage infrastructure
provisioning.

**Architecture:** The provider currently requires `host` and `api_key`
at the provider level (plan-time). This fork makes `api_key` optional
and adds a `dokploy_api_key` resource that handles admin signup, signin,
and API key creation via Dokploy's better-auth endpoints. The resource
mutates the shared `*client.DokployClient` pointer during `Create()`,
so all subsequent resources in the dependency chain use the live
credentials. The `host` attribute also moves to the resource level
(optional at provider level) so it can reference resource outputs like
`linode_instance.ip_address`.

**Tech Stack:** Go 1.25, Terraform Plugin Framework v1.19.0,
`j0bIT/terraform-provider-dokploy` v0.3.0

---

## Context: Why This Enables Single-Stage Deploy

Currently, Stage 1 provisions the Linode + runs cloud-init (which
installs Dokploy and creates an API key), then Stage 2 uses that key
to configure Dokploy. Two stages exist because the provider needs the
API key at plan-time.

With this fork:

```hcl
provider "dokploy" {
  # Both optional — api_key resource handles auth
}

resource "dokploy_api_key" "main" {
  host     = "http://${linode_instance.dokploy_main.ip_address}:3000/api"
  email    = var.DOKPLOY_ADMIN_EMAIL
  password = var.DOKPLOY_ADMIN_PASSWORD
  name     = "terraform"
}

resource "dokploy_project" "main" {
  name       = "services"
  depends_on = [dokploy_api_key.main]
}
```

Terraform apply order:

1. `linode_instance` created → IP known
2. `remote-exec` provisioner blocks until cloud-init finishes
3. `dokploy_api_key.Create()` → signup + signin + create key → mutates
   shared client with `BaseURL` and `APIKey`
4. All other `dokploy_*` resources run with live credentials

Single `terraform apply`, single state file, single root module.

**What stays from the existing plans:**

- Cloud-init script (installs Docker, Dokploy, SSH hardening, firewall)
- `remote-exec` provisioner (waits for `cloud-init status --wait`)
- SSH key pair for the provisioner connection

**What this replaces:**

- Cloud-init admin account + API key creation section (moves to TF
  resource)
- `local-exec` provisioner that retrieves API key via SSH
- `.dokploy-api-key` file and deploy script key retrieval logic
- The two-stage Terraform split

---

## Shared Client Mutation Pattern

All 13 resources receive the same `*client.DokployClient` pointer
via `req.ProviderData` in their `Configure()` method. The client is a
simple struct with exported fields:

```go
type DokployClient struct {
    BaseURL    string
    APIKey     string
    HTTPClient *http.Client
}
```

`dokploy_api_key.Create()` sets `r.client.BaseURL` and
`r.client.APIKey`. Terraform applies resources in dependency order, so
any resource with `depends_on = [dokploy_api_key.main]` runs after
the client is fully configured. No concurrency issues — Terraform
serializes dependent resources.

---

## Task 1: Fork and Set Up Repository

### Step 1: Fork the repository

Fork `j0bIT/terraform-provider-dokploy` to your GitHub account. Clone
it locally.

```bash
gh repo fork j0bIT/terraform-provider-dokploy --clone \
  --remote=true
cd terraform-provider-dokploy
```

### Step 2: Verify existing tests pass

```bash
go test ./internal/...
```

Expected: All tests pass. If any fail, note them — they're pre-existing
and not our concern.

### Step 3: Commit

```bash
git checkout -b feat/api-key-resource
git commit --allow-empty -m "chore: start api-key resource branch"
```

---

## Task 2: Make Provider Config Optional

**Files:**

- Modify: `internal/provider/provider.go`

### Step 1: Make `host` and `api_key` optional in the provider schema

In `provider.go`, change the schema from `Required: true` to
`Optional: true` for both attributes:

```go
func (p *DokployProvider) Schema(_ context.Context,
    _ provider.SchemaRequest, resp *provider.SchemaResponse) {
    resp.Schema = schema.Schema{
        Attributes: map[string]schema.Attribute{
            "host": schema.StringAttribute{
                Optional:    true,
                Description: "The URL of your Dokploy instance " +
                    "(e.g., https://dokploy.example.com/api). " +
                    "Can be omitted if using dokploy_api_key resource.",
            },
            "api_key": schema.StringAttribute{
                Optional:    true,
                Sensitive:   true,
                Description: "Your Dokploy API Key. Can be omitted " +
                    "if using dokploy_api_key resource.",
            },
        },
    }
}
```

### Step 2: Update `Configure()` to create client even without credentials

The client should always be created (so the shared pointer exists for
mutation), but with empty values if not provided:

```go
func (p *DokployProvider) Configure(ctx context.Context,
    req provider.ConfigureRequest,
    resp *provider.ConfigureResponse) {
    var config DokployProviderModel
    diags := req.Config.Get(ctx, &config)
    resp.Diagnostics.Append(diags...)
    if resp.Diagnostics.HasError() {
        return
    }

    host := ""
    apiKey := ""

    if !config.Host.IsNull() && !config.Host.IsUnknown() {
        host = config.Host.ValueString()
    }
    if !config.ApiKey.IsNull() && !config.ApiKey.IsUnknown() {
        apiKey = config.ApiKey.ValueString()
    }

    // Always create the client — dokploy_api_key resource will
    // configure it if host/api_key are empty.
    c := client.NewDokployClient(host, apiKey)

    resp.ResourceData = c
    resp.DataSourceData = c
}
```

### Step 3: Run existing tests

```bash
go test ./internal/provider/ -run TestProvider -v
```

Expected: Provider tests still pass (schema validation no longer
requires the attributes).

### Step 4: Commit

```bash
git add internal/provider/provider.go
git commit -m "feat: make host and api_key optional in provider config

Allows dokploy_api_key resource to handle auth instead of requiring
credentials at provider configuration time."
```

---

## Task 3: Add Auth Methods to Client

**Files:**

- Modify: `internal/client/client.go`

### Step 1: Add auth-related structs and methods

Add these after the existing `GetUser()` method (around line 316):

```go
// --- Auth / API Key ---

type SignUpResponse struct {
    ID    string `json:"id"`
    Email string `json:"email"`
    Name  string `json:"name"`
}

type APIKeyResponse struct {
    Key string `json:"key"`
}

type OrganizationResponse struct {
    ID   string `json:"id"`
    Name string `json:"name"`
}

// SignUp creates a new admin user via better-auth.
// Only succeeds if no owner exists yet (first-time setup).
func (c *DokployClient) SignUp(
    email, password, name string,
) (*SignUpResponse, error) {
    payload := map[string]string{
        "email":    email,
        "password": password,
        "name":     name,
    }
    resp, err := c.doRequest(
        "POST", "auth/sign-up/email", payload,
    )
    if err != nil {
        return nil, fmt.Errorf("signup failed: %w", err)
    }
    var result SignUpResponse
    if err := json.Unmarshal(resp, &result); err != nil {
        return nil, fmt.Errorf(
            "failed to parse signup response: %w", err,
        )
    }
    return &result, nil
}

// SignIn authenticates and returns the session cookie jar.
// The caller should use the returned http.Client for subsequent
// authenticated requests (cookie-based auth).
func (c *DokployClient) SignIn(
    email, password string,
) (*http.Client, error) {
    jar, err := cookiejar.New(nil)
    if err != nil {
        return nil, fmt.Errorf(
            "failed to create cookie jar: %w", err,
        )
    }

    authedClient := &http.Client{
        Timeout: 30 * time.Second,
        Jar:     jar,
    }

    payload, err := json.Marshal(map[string]string{
        "email":    email,
        "password": password,
    })
    if err != nil {
        return nil, err
    }

    url := fmt.Sprintf("%s/auth/sign-in/email", c.BaseURL)
    resp, err := authedClient.Post(
        url, "application/json", bytes.NewBuffer(payload),
    )
    if err != nil {
        return nil, fmt.Errorf("signin failed: %w", err)
    }
    defer resp.Body.Close()

    if resp.StatusCode >= 400 {
        body, _ := io.ReadAll(resp.Body)
        return nil, fmt.Errorf(
            "signin failed: %s - %s",
            resp.Status, string(body),
        )
    }

    return authedClient, nil
}

// ListOrganizations returns organizations for the authenticated user.
func (c *DokployClient) ListOrganizations(
    authedClient *http.Client,
) ([]OrganizationResponse, error) {
    url := fmt.Sprintf(
        "%s/auth/organization/list", c.BaseURL,
    )
    resp, err := authedClient.Get(url)
    if err != nil {
        return nil, fmt.Errorf(
            "list organizations failed: %w", err,
        )
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return nil, err
    }

    if resp.StatusCode >= 400 {
        return nil, fmt.Errorf(
            "list organizations failed: %s - %s",
            resp.Status, string(body),
        )
    }

    var orgs []OrganizationResponse
    if err := json.Unmarshal(body, &orgs); err != nil {
        return nil, fmt.Errorf(
            "failed to parse organizations: %w", err,
        )
    }
    return orgs, nil
}

// CreateAPIKey creates a new API key via better-auth's apiKey plugin.
func (c *DokployClient) CreateAPIKey(
    authedClient *http.Client,
    name, organizationID string,
) (string, error) {
    payload, err := json.Marshal(map[string]interface{}{
        "name": name,
        "metadata": map[string]string{
            "organizationId": organizationID,
        },
    })
    if err != nil {
        return "", err
    }

    url := fmt.Sprintf(
        "%s/auth/api-key/create", c.BaseURL,
    )
    resp, err := authedClient.Post(
        url, "application/json", bytes.NewBuffer(payload),
    )
    if err != nil {
        return "", fmt.Errorf(
            "create API key failed: %w", err,
        )
    }
    defer resp.Body.Close()

    body, err := io.ReadAll(resp.Body)
    if err != nil {
        return "", err
    }

    if resp.StatusCode >= 400 {
        return "", fmt.Errorf(
            "create API key failed: %s - %s",
            resp.Status, string(body),
        )
    }

    var result APIKeyResponse
    if err := json.Unmarshal(body, &result); err != nil {
        return "", fmt.Errorf(
            "failed to parse API key response: %w", err,
        )
    }

    if result.Key == "" {
        return "", fmt.Errorf(
            "API key response missing 'key' field",
        )
    }

    return result.Key, nil
}
```

### Step 2: Add the `cookiejar` import

Add `"net/http/cookiejar"` to the import block at the top of
`client.go`.

### Step 3: Verify compilation

```bash
go build ./...
```

Expected: Clean build, no errors.

### Step 4: Commit

```bash
git add internal/client/client.go
git commit -m "feat: add auth methods to client

SignUp, SignIn, ListOrganizations, and CreateAPIKey methods for
better-auth integration. Used by dokploy_api_key resource."
```

---

## Task 4: Create `dokploy_api_key` Resource

**Files:**

- Create: `internal/provider/resource_api_key.go`

### Step 1: Write the resource implementation

```go
package provider

import (
    "context"
    "fmt"

    "github.com/hashicorp/terraform-plugin-framework/path"
    "github.com/hashicorp/terraform-plugin-framework/resource"
    "github.com/hashicorp/terraform-plugin-framework/resource/schema"
    "github.com/hashicorp/terraform-plugin-framework/resource/schema/planmodifier"
    "github.com/hashicorp/terraform-plugin-framework/resource/schema/stringplanmodifier"
    "github.com/hashicorp/terraform-plugin-framework/types"
    "github.com/j0bit/terraform-provider-dokploy/internal/client"
)

var _ resource.Resource = &APIKeyResource{}
var _ resource.ResourceWithImportState = &APIKeyResource{}

func NewAPIKeyResource() resource.Resource {
    return &APIKeyResource{}
}

type APIKeyResource struct {
    client *client.DokployClient
}

type APIKeyResourceModel struct {
    ID       types.String `tfsdk:"id"`
    Host     types.String `tfsdk:"host"`
    Email    types.String `tfsdk:"email"`
    Password types.String `tfsdk:"password"`
    Name     types.String `tfsdk:"name"`
    Key      types.String `tfsdk:"key"`
}

func (r *APIKeyResource) Metadata(
    _ context.Context,
    req resource.MetadataRequest,
    resp *resource.MetadataResponse,
) {
    resp.TypeName = req.ProviderTypeName + "_api_key"
}

func (r *APIKeyResource) Schema(
    _ context.Context,
    _ resource.SchemaRequest,
    resp *resource.SchemaResponse,
) {
    resp.Schema = schema.Schema{
        Description: "Creates a Dokploy admin account and API key. " +
            "This resource handles first-time signup, signin, and " +
            "API key generation via Dokploy's better-auth endpoints. " +
            "It also configures the provider's shared client so " +
            "subsequent resources can authenticate.",
        Attributes: map[string]schema.Attribute{
            "id": schema.StringAttribute{
                Computed: true,
                PlanModifiers: []planmodifier.String{
                    stringplanmodifier.UseStateForUnknown(),
                },
            },
            "host": schema.StringAttribute{
                Required: true,
                Description: "The Dokploy API base URL " +
                    "(e.g., http://<ip>:3000/api). Can reference " +
                    "other resource outputs.",
                PlanModifiers: []planmodifier.String{
                    stringplanmodifier.RequiresReplace(),
                },
            },
            "email": schema.StringAttribute{
                Required:    true,
                Description: "Admin email for Dokploy signup.",
            },
            "password": schema.StringAttribute{
                Required:    true,
                Sensitive:   true,
                Description: "Admin password for Dokploy signup.",
            },
            "name": schema.StringAttribute{
                Optional: true,
                Computed: true,
                Description: "Name for the API key. " +
                    "Defaults to 'terraform'.",
            },
            "key": schema.StringAttribute{
                Computed:    true,
                Sensitive:   true,
                Description: "The generated API key. " +
                    "Stored in Terraform state.",
                PlanModifiers: []planmodifier.String{
                    stringplanmodifier.UseStateForUnknown(),
                },
            },
        },
    }
}

func (r *APIKeyResource) Configure(
    _ context.Context,
    req resource.ConfigureRequest,
    resp *resource.ConfigureResponse,
) {
    if req.ProviderData == nil {
        return
    }
    c, ok := req.ProviderData.(*client.DokployClient)
    if !ok {
        resp.Diagnostics.AddError(
            "Unexpected Data Source Type",
            fmt.Sprintf(
                "Expected *client.DokployClient, got: %T",
                req.ProviderData,
            ),
        )
        return
    }
    r.client = c
}

func (r *APIKeyResource) Create(
    ctx context.Context,
    req resource.CreateRequest,
    resp *resource.CreateResponse,
) {
    var plan APIKeyResourceModel
    diags := req.Plan.Get(ctx, &plan)
    resp.Diagnostics.Append(diags...)
    if resp.Diagnostics.HasError() {
        return
    }

    // Default name
    if plan.Name.IsNull() || plan.Name.IsUnknown() {
        plan.Name = types.StringValue("terraform")
    }

    // Configure the shared client's BaseURL
    r.client.BaseURL = plan.Host.ValueString()

    // 1. Sign up (creates admin + org via better-auth after hook).
    //    If admin already exists (re-apply), fall through to signin.
    _, err := r.client.SignUp(
        plan.Email.ValueString(),
        plan.Password.ValueString(),
        "admin",
    )
    adminExists := err != nil &&
        strings.Contains(err.Error(), "Admin is already created")
    if err != nil && !adminExists {
        resp.Diagnostics.AddError(
            "Dokploy signup failed", err.Error(),
        )
        return
    }

    // 2. Sign in (get session cookie)
    authedClient, err := r.client.SignIn(
        plan.Email.ValueString(),
        plan.Password.ValueString(),
    )
    if err != nil {
        resp.Diagnostics.AddError(
            "Dokploy signin failed", err.Error(),
        )
        return
    }

    // 3. Get organization ID (auto-created by signup after hook)
    orgs, err := r.client.ListOrganizations(authedClient)
    if err != nil {
        resp.Diagnostics.AddError(
            "Failed to list organizations", err.Error(),
        )
        return
    }
    if len(orgs) == 0 {
        resp.Diagnostics.AddError(
            "No organizations found",
            "Signup should have auto-created an organization. "+
                "Check Dokploy logs.",
        )
        return
    }
    orgID := orgs[0].ID

    // 4. Create API key
    key, err := r.client.CreateAPIKey(
        authedClient,
        plan.Name.ValueString(),
        orgID,
    )
    if err != nil {
        resp.Diagnostics.AddError(
            "Failed to create API key", err.Error(),
        )
        return
    }

    // 5. Mutate the shared client — all subsequent resources
    //    that depend on this resource will use these credentials.
    r.client.APIKey = key

    // 6. Set state
    plan.ID = types.StringValue(orgID)
    plan.Key = types.StringValue(key)

    diags = resp.State.Set(ctx, plan)
    resp.Diagnostics.Append(diags...)
}

func (r *APIKeyResource) Read(
    ctx context.Context,
    req resource.ReadRequest,
    resp *resource.ReadResponse,
) {
    var state APIKeyResourceModel
    diags := req.State.Get(ctx, &state)
    resp.Diagnostics.Append(diags...)
    if resp.Diagnostics.HasError() {
        return
    }

    // Ensure the shared client is configured from state
    if r.client.BaseURL == "" && !state.Host.IsNull() {
        r.client.BaseURL = state.Host.ValueString()
    }
    if r.client.APIKey == "" && !state.Key.IsNull() {
        r.client.APIKey = state.Key.ValueString()
    }

    // Verify the API key still works by calling user.get
    _, err := r.client.GetUser()
    if err != nil {
        // Key is invalid or Dokploy is unreachable — remove
        resp.State.RemoveResource(ctx)
        return
    }

    // State is unchanged
    diags = resp.State.Set(ctx, state)
    resp.Diagnostics.Append(diags...)
}

func (r *APIKeyResource) Update(
    ctx context.Context,
    req resource.UpdateRequest,
    resp *resource.UpdateResponse,
) {
    // host change triggers RequiresReplace, so only email/password/
    // name can change in-place. Re-signin and rotate the key.
    var plan APIKeyResourceModel
    diags := req.Plan.Get(ctx, &plan)
    resp.Diagnostics.Append(diags...)
    if resp.Diagnostics.HasError() {
        return
    }

    var state APIKeyResourceModel
    diags = req.State.Get(ctx, &state)
    resp.Diagnostics.Append(diags...)
    if resp.Diagnostics.HasError() {
        return
    }

    // Ensure client is configured
    r.client.BaseURL = plan.Host.ValueString()
    if r.client.APIKey == "" {
        r.client.APIKey = state.Key.ValueString()
    }

    // Keep existing key and state — name/email/password changes
    // don't rotate the key.
    plan.ID = state.ID
    plan.Key = state.Key

    diags = resp.State.Set(ctx, plan)
    resp.Diagnostics.Append(diags...)
}

func (r *APIKeyResource) Delete(
    ctx context.Context,
    req resource.DeleteRequest,
    resp *resource.DeleteResponse,
) {
    // API key deletion is not supported by better-auth's API.
    // On destroy, the key simply becomes orphaned. The admin account
    // persists until Dokploy is rebuilt.
    //
    // This is intentional — destroying the api_key resource shouldn't
    // lock you out of Dokploy.
}

func (r *APIKeyResource) ImportState(
    ctx context.Context,
    req resource.ImportStateRequest,
    resp *resource.ImportStateResponse,
) {
    resource.ImportStatePassthroughID(
        ctx, path.Root("id"), req, resp,
    )
}
```

### Step 2: Register the resource in the provider

In `provider.go`, add `NewAPIKeyResource` to the `Resources()` method:

```go
func (p *DokployProvider) Resources(
    _ context.Context,
) []func() resource.Resource {
    return []func() resource.Resource{
        NewAPIKeyResource,  // <-- add this
        NewProjectResource,
        NewEnvironmentResource,
        // ... rest unchanged
    }
}
```

### Step 3: Verify compilation

```bash
go build ./...
```

Expected: Clean build.

### Step 4: Commit

```bash
git add internal/provider/resource_api_key.go \
        internal/provider/provider.go
git commit -m "feat: add dokploy_api_key resource

Creates admin account and API key via better-auth endpoints.
Mutates shared client so dependent resources can authenticate.
Enables single-stage Terraform apply without pre-existing API key."
```

---

## Task 5: Write Tests

**Files:**

- Create: `internal/provider/resource_api_key_test.go`

### Step 1: Write a unit test for the resource schema

```go
package provider

import (
    "context"
    "testing"

    fwresource "github.com/hashicorp/terraform-plugin-framework/resource"
    "github.com/hashicorp/terraform-plugin-framework/resource/schema"
)

func TestAPIKeyResource_Schema(t *testing.T) {
    r := &APIKeyResource{}
    ctx := context.Background()

    var resp fwresource.SchemaResponse
    r.Schema(ctx, fwresource.SchemaRequest{}, &resp)

    // Verify required attributes
    hostAttr, ok := resp.Schema.Attributes["host"].(schema.StringAttribute)
    if !ok || !hostAttr.Required {
        t.Error("host should be a required StringAttribute")
    }

    // Verify key is computed + sensitive
    keyAttr, ok := resp.Schema.Attributes["key"].(schema.StringAttribute)
    if !ok || !keyAttr.Computed {
        t.Error("key should be computed")
    }
    if !keyAttr.Sensitive {
        t.Error("key should be sensitive")
    }
}
```

**Note:** Full acceptance tests require a running Dokploy instance.
Those should be added later using the sandbox pattern from
`resources_test.go`. The schema test verifies the resource compiles
and has the expected attributes.

### Step 2: Run tests

```bash
go test ./internal/provider/ -run TestAPIKeyResource -v
```

Expected: PASS

### Step 3: Commit

```bash
git add internal/provider/resource_api_key_test.go
git commit -m "test: add schema test for dokploy_api_key resource"
```

---

## Task 6: Update Documentation

**Files:**

- Create: `docs/resources/api_key.md`

### Step 1: Write resource docs

```markdown
# dokploy_api_key (Resource)

Creates a Dokploy admin account and API key. This resource handles
first-time signup, signin, and API key generation via Dokploy's
better-auth endpoints.

When used, the provider's `host` and `api_key` attributes become
optional — this resource configures the shared client at apply time.

## Example Usage

```hcl
provider "dokploy" {
  # No config needed — api_key resource handles auth
}

resource "dokploy_api_key" "main" {
  host     = "http://${linode_instance.app.ip_address}:3000/api"
  email    = var.admin_email
  password = var.admin_password
  name     = "terraform"
}

resource "dokploy_project" "main" {
  name       = "my-project"
  depends_on = [dokploy_api_key.main]
}
```

## Schema

### Required

- `host` (String) The Dokploy API base URL. Can reference other
  resource outputs (e.g., `linode_instance.ip_address`).
- `email` (String) Admin email for Dokploy signup.
- `password` (String, Sensitive) Admin password for Dokploy signup.

### Optional

- `name` (String) Name for the API key. Defaults to "terraform".

### Read-Only

- `id` (String) The organization ID.
- `key` (String, Sensitive) The generated API key. Stored in
  Terraform state.

## Notes

- This resource only works for **first-time Dokploy setup**. If an
  admin account already exists, signup will fail.
- The API key is stored in Terraform state. Use state encryption.
- Destroying this resource does NOT revoke the API key or delete
  the admin account.
- Other `dokploy_*` resources must use
  `depends_on = [dokploy_api_key.main]` to ensure the client is
  configured before they run.

```

### Step 2: Commit

```bash
git add docs/resources/api_key.md
git commit -m "docs: add api_key resource documentation"
```

---

## Task 7: Build and Local Install

### Step 1: Build the provider binary

```bash
go build -o terraform-provider-dokploy
```

### Step 2: Install locally for testing

```bash
mkdir -p ~/.terraform.d/plugins/registry.terraform.io/j0bit/dokploy/0.4.0-fork/linux_amd64
cp terraform-provider-dokploy \
  ~/.terraform.d/plugins/registry.terraform.io/j0bit/dokploy/0.4.0-fork/linux_amd64/
```

### Step 3: Test with a minimal config

Create a temp test directory and verify `terraform init` picks up the
local provider:

```hcl
# /tmp/test-dokploy/main.tf
terraform {
  required_providers {
    dokploy = {
      source  = "j0bit/dokploy"
      version = "0.4.0-fork"
    }
  }
}

provider "dokploy" {}

resource "dokploy_api_key" "test" {
  host     = "http://localhost:3000/api"
  email    = "test@example.com"
  password = "testpass123"
}
```

```bash
cd /tmp/test-dokploy
terraform init
terraform validate
```

Expected: `Success! The configuration is valid.`

### Step 4: Commit

```bash
git add -A
git commit -m "chore: finalize fork for local testing"
```

---

## Files Summary

| Action | File |
| --- | --- |
| **Modify** | `internal/provider/provider.go` |
| **Modify** | `internal/client/client.go` |
| **Create** | `internal/provider/resource_api_key.go` |
| **Create** | `internal/provider/resource_api_key_test.go` |
| **Create** | `docs/resources/api_key.md` |

---

## Impact on Existing Plans

Once this fork is ready, the deploy plan
(`2026-03-09-dokploy-deploy-plan.md`) and Stage 2 plan
(`2026-03-09-dokploy-stage2-config-plan.md`) should be updated:

1. **Cloud-init (`user_data.sh`):** Remove the admin signup, signin,
   and API key creation section (lines 78-111 in the deploy plan).
   Keep everything else (Docker, Dokploy install, SSH, firewall).

2. **Provisioners on `linode_instance`:** Keep `remote-exec` with
   `cloud-init status --wait`. Remove `local-exec` that retrieves the
   API key file.

3. **Merge into single root module:** Move `dokploy_*` resources from
   `linode/environments/dokploy/` into
   `linode/environments/production/` (or a shared module). Add
   `dokploy_api_key` resource with
   `host = "http://${module.dokploy-instance.instance_ip}:3000/api"`.

4. **Simplify `deploy-production.sh`:** Remove API key retrieval,
   `.env` generation for Stage 2, and the second `terraform apply`.
   It becomes just `bash scripts/tf.sh apply linode/environments/production`.

5. **Provider source:** Change from `j0bit/dokploy` to your fork's
   namespace, or use local filesystem override during development.

---

## Open Questions

1. **Signup idempotency:** If `terraform apply` is re-run after the
   admin already exists, `SignUp` will fail. The `Create()` method
   should handle this — try signup, if it fails with "user exists",
   fall through to signin. This needs testing against the actual
   Dokploy API to see the exact error response.

2. **API key rotation:** If the key in state becomes invalid (e.g.,
   Dokploy was rebuilt), `Read()` removes the resource from state,
   triggering re-creation on next apply. Verify this flow works.

3. **Upstream contribution:** This could be contributed as a PR to
   `j0bIT/terraform-provider-dokploy`. The provider is young (v0.1.0
   unreleased per CHANGELOG), so the maintainer may be receptive.

4. **`depends_on` ergonomics:** Every `dokploy_*` resource needs
   `depends_on = [dokploy_api_key.main]`. An alternative is to have
   the `Read()` method of the api_key resource configure the client
   from state on every plan/apply cycle, removing the need for
   explicit `depends_on`. This requires more testing.
