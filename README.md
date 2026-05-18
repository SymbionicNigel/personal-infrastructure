# Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - enki.localhost - gitlab
   - hendrix.localhost - traefik
   - janus.localhost - whoami (Roman two-faced god of beginnings, doorways, and transitions)
   - vulcan.localhost - dokploy console - Roman god of the forge, craftsmen, and builders
   - IN NEED OF SERVICE
     - astarte — Phoenician goddess of beauty; the public-facing presence of the Phoenician pantheon
     - mimir - Norse god of knowledge.  Good for observation or knowledgebase
     - iris - Greek messenger goddess, rainbow personified, the visible link between gods and mortals
     - selene - Greek moon goddess; the visible face of the night sky
     - ptah — Egyptian creator god and patron of craftsmen and architects.
     - inanna — Sumerian goddess of love and war, predecessor to Astarte/Ishtar. Keeps the Mesopotamian thread you started with Enki.
     - daedalus — the master craftsman and architect. Built the labyrinth, designed wings.
     - anubis — Egyptian guide of souls.

1. To run Traefik and use https run the following command to create tls certificates for https to work properly

   ```openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout traefik/local_certs/traefik-selfsigned.key -out traefik/local_certs/traefik-selfsigned.crt -subj "/CN=*.<desired_local_domain_name>"```

## Production runtime

Production services run on a single Linode host managed by
[Dokploy](https://dokploy.com), provisioned end-to-end by the Terraform
config under [linode/](./linode/README.md). Dokploy's bundled Traefik
handles routing and TLS; application services are defined in the root
`docker-compose.yml` and deployed as a `dokploy_compose` stack.

## Modules

1. [Linode](./linode/README.md) - Terraform based IAC
2. [Solid](./solid/SOLIDSTART_README.md) - SolidStart web frontend
3. [Scripts](./scripts/README.md) - Scripts for building and developing in personal-infrastructure

Required CLI packages and initializing commands:

<!-- TODO: give install commands, possibly adding a script -->
<!-- TODO: include links to documentation -->

- Docker / Docker Compose
- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [chezmoi](https://www.chezmoi.io/) — dotfile / secret management
- [GnuPG](https://gnupg.org/) — encrypts secrets handled by chezmoi
- [Bitwarden CLI (`bw`)](https://bitwarden.com/help/cli/) — unlocks the
  vault used by the GPG/SSH workflow
- [Linode-Cli](https://github.com/linode/linode-cli)
    - `linode-cli configure --token`
- [pnpm](https://pnpm.io/) — frontend package manager
- node
