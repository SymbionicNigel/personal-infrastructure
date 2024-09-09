# Traefik - Load Balanacer, Proxy, Router

## Reasoning and Methodology

Traefik's intersection of being a networking multitool, having a simple extensible configuration, and containers as a first class citizen made it a shoo in as proxy server over the standard choices (nginx and apache). After understanding the fundamental layers needed to interact with traefik, it seems like a fine choice to move forward with as the core of the network management of this project.

In this project I am looking to self host as many services for my personal infrastructre as I can. On top of being a technical challenge which will stick with this project no matter what direction it goes, I see it as a way to keep the technical and infrastructural drift between local development and cloud deployment to an absolute minimum. I want a reproducible evnvironment for debugging and development.

The initial design for Traefik is to take any container we wish to handle external routing for and with minimal configuration have that container routed to `<container_name>.<hostname>.<tld>` using https. This is currently done by editing the `defaultCertificate` and `defaultGeneratedCert` configurations in the default tls store in the dynamic config. With future iterations I hope to add logging, monitoring, and additional hardening measures to this configuration.

## Adding a service

1. If no new https, entrypoint, or other configuration needs to be handled the following lines added to [docker-compose.yml](../docker-compose.yml) will have a new container routed with https to the correct sub-domains through labels.

``` yml
traefik.enable: True
traefik.http.routers.<service_name>.entrypoints: websecure
traefik.http.routers.<service_name>.tls: true
traefik.http.services.<service_name>.loadbalancer.server.port: <port>
```

2. If another entrypoint is needed, the entrypoints section in the [traefik static config](./config/traefik.yml)

``` yml
entryPoints:
  ...
  <entrypoint_name>:
    address: :<port>
```
