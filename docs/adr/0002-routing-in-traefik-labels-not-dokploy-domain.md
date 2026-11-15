# Routing lives in Traefik labels in the compose file, not `dokploy_domain` resources

Each Service's routing — host rules, TLS, middlewares — is declared as Traefik labels on the Service in `compose/docker-compose.yml`, and that file is the single source of truth for routing. Dokploy's native `dokploy_domain` resources are deliberately not used.

The reason is colocation: keeping routing next to the Service definition is one less place to remember, and it avoids adding a third routing/config surface on top of the canonical compose file and its override — a split we already manage. `dokploy_domain` resources would pull routing back out into Terraform, away from the Service it describes, and make the base/override divergence worse.
