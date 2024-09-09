# Dev Setup

1. Need to add subdomains to `/etc/hosts` on Linux and `C:\Windows\System32\drivers\etc\hosts` on Windows so that subdomain testing will work
   - enki.localhost - gitlab
   - khazad-dum.localhost - vault
   - hendrix.localhost - traefik
   - astarte.localhost - solid
2. To run Traefik and use https run the following command to create tls certificates for https to work properly

   ```openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout traefik/local_certs/traefik-selfsigned.key -out traefik/local_certs/traefik-selfsigned.crt -subj "/CN=*.<desired_local_domain_name>"```

Required CLI packages:

- Docker/Docker-compose
- terraform
- [PNPM](https://pnpm.io/)
- node
- postgres
