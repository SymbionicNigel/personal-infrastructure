# Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - enki.localhost - gitlab
   - khazad-dum.localhost - vault
   - hendrix.localhost - traefik
   - astarte.localhost - solid
2. To run Traefik and use https run the following command to create tls certificates for https to work properly

   ```openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout traefik/local_certs/traefik-selfsigned.key -out traefik/local_certs/traefik-selfsigned.crt -subj "/CN=*.<desired_local_domain_name>"```

## Modules

1. [Traefik](./traefik/README.md) - Load balancer and proxy
2. [Linode](./linode/README.md) - Terraform based IAC
3. [Quart](./quart/TODO) - Async first Python API
4. [Solid](./solid/SOLIDSTART_README.md) - Solidstart Web frontend, to be replaced by remix potentially
5. [Scripts](./scripts/README.md) - Scripts for building and developing in personal-infrastructure

Required CLI packages and initializing commands:

<!-- TODO: give install commands, possibly adding a script -->
<!-- TODO: include links to documentation -->

- Docker/Docker-compose
- [terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli)
- [PNPM](https://pnpm.io/)
<!-- TODO: Move to Yarn -->
- yarn v2+
- node
- nvm
- postgres
<!-- - supabase as app orchestration? -->
- [Linode-Cli](https://github.com/linode/linode-cli)
  - `linode-cli configure --token`
