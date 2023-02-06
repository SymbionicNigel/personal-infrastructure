# Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - enki.localhost - gitlab
   - khazad-dum.localhost - vault
   - hendrix.localhost - traefik
   - astarte.localhost - solid

Required CLI packages:

- Docker/Docker-compose
- terraform
- [PNPM](https://pnpm.io/)
- node
- postgres
