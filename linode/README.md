# Terraform - IAC

## Initialization & Bootstrapping

If initializing again or for another project:

1. Follow the instructions [here](https://developer.hashicorp.com/terraform/install#linux) to install the most recent version of terraform.
2. Sign up for a terraform cloud account, generate a token for local use, and connect to Vault Secrets
   1. Visit [HCP Terraform](https://app.terraform.io/) and create an account, an organization and a project.
   2. Once logged in navigate [here](https://app.terraform.io/app/settings/tokens), store this token in a password manager for use in the CLI
   3. Navigate to [HCP cloud](https://portal.cloud.hashicorp.com/). Create sign in with the account you used on HCP Terraform.
   4. Link HCP Terraform and Vault in HCP Cloud
      1. In HCP Cloud go to [Vault > Apps](https://portal.cloud.hashicorp.com/services/secrets/apps) and create a new app in Vault
      2. Click on the Apps > Integrations tab, find the HCP Terraform card and click add.
      3. Go back to HCP Terraform and go to the API Tokens (app > settings > authentication token), create one, and copy the value into the screen in HCP Cloud connecting the two services.
3. TODO: include steps to get linode CLI and provider setup

## Considerations & Concessions

### Terraform cloud as a State Backend

The goals I had for using terraform/IAC was to have easily configured, separated, and reproducible environments with an easily recoverable infrastructure state for this project. My initial plan was to use some self hosted method of storing environment variables and dotfiles for each environment to implement the configurable and separated environments. Alongside that I would use terraform to setup an object bucket in linode and transferring state to that bucket as the backend once created.

I was not able to get this working with the current versions of boto3, the linode-cli, and terraform. With few other solutions which did not require provisioning or paying for resources in another cloud (s3 + DynamoDB, GCP, Consul), my options were use a hosted version of GitLab and its integrated http backend or to use terraform cloud.

While I do like the idea of using GitLab for this project, I would rather it be the self hosted version. There is a lot more configuration that would be needed to get me started than just using terraform cloud. Doing so allows for a simple and direct integration with the terraform cli, no extra steps to bootstrap the storage, and simple separate environments through workspaces. If I feel like it is worth it to move backends at a later date I can but I see this as not likely unless HashiCorp seriously changes terraform or this becomes a paid service.

While I could go as far as codifying the setup of terraform cloud using the TFE Provider, I do not think this is necessary and would then potentially re-introduce the bootstrapping issue.

### Hashicorp Vault for Secrets Management

Given that I have already made the decision to include HashiCorp services in the stack for this project, I decided to use Vault as the secrets manager. It integrated with the state management and cli easily using the workspaces within terraform cloud to expose the values in the terraform provider. I can explore other backups, anything from something which stores dotfiles to secrets amanger itself to self hosting vault, this was sjust the easiest to get started on.

There will be a separation of some environment variables and other secrets which I will not be storing in Vault, those will be the manually generated tokens or global account configuration, things generally needed to bootstrap this project. For now I think I will include these values in `.tfvars` files locally. These fields are:

1. HCP_TOKEN
2. LINODE_TOKEN
3. ENVIRON
4. HOSTNAME_TLD
5. EMAIL_ADDRESS
