# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with
code in this repository.

## Quick Reference

**Start the stack**: `docker-compose up -d`
**Frontend development**: `cd solid && pnpm dev`
**Database operations**: Use Prisma CLI in `solid/` directory
**Infrastructure**: Use Terraform in `linode/` directory
**Dotfiles**: Use chezmoi commands with `--config ./.chezmoi.toml`

## Architecture

This is a containerized personal infrastructure project with Traefik reverse
proxy managing service routing to `<container_name>.<hostname>.<tld>` subdomains.

**Key components**:

- **Traefik** (`hendrix`): Load balancer/proxy - see [traefik/README.md](./traefik/README.md)
- **Terraform** for Linode infrastructure - see [linode/README.md](./linode/README.md)
- **Dotfile management** via chezmoi - see [dotfile-utils/README.md](./dotfile-utils/README.md)

**Setup requirements**: See main [README.md](./README.md) for host configuration
and dependencies.

## Task Management

Project tasks and roadmap are tracked in the **Personal IT Infrastructure >>
To-Do Items** page in Notion. This serves as the central hub for planning,
prioritizing, and tracking all project-related work including development,
maintenance, configuration, and system improvements.

## Development Notes

- Container services auto-route via Docker labels (see docker-compose.yml template)
- Infrastructure uses HCP Terraform Cloud for state management
- Secrets managed via HashiCorp Vault + encrypted dotfiles
- Multi-environment support (dev/test/prod) via Terraform workspaces
