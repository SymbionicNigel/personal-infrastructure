# Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - enki.localhost - gitlab
   - khazad-dum.localhost - vault  (DEPRECATED)
   - hendrix.localhost - traefik
   - astarte.localhost - solid (DEPRECATED) (goddess of beauty and the public-
     facing presence of the Phoenician pantheon)
   - janus.localhost - whoami (Roman two-faced god of beginnings, doorways, and transitions)
   - vulcan.localhost - dokploy console - Roman god of the forge, craftsmen, and builders
   - IN NEED OF SERVICE
     - mimir - Norse god of knowledge.  Good for observation or knowledgebase
     - iris - Greek messenger goddess, rainbow personified, the visible link between gods and mortals
     - selene - Greek moon goddess; the visible face of the night sky
     - ptah — Egyptian creator god and patron of craftsmen and architects.
     - inanna — Sumerian goddess of love and war, predecessor to Astarte/Ishtar. Keeps the Mesopotamian thread you started with Enki.
     - daedalus — the master craftsman and architect. Built the labyrinth, designed wings.
     - anubis — Egyptian guide of souls.

1. To run Traefik and use https run the following command to create tls certificates for https to work properly

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
