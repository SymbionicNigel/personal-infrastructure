# Dokploy template service catalog

A saved menu of candidate self-hosted services (sourced from Dokploy's template list), grouped by type. Each entry links the Dokploy template and the upstream project, and flags whether it wants a relational database. This is a reference of options — not a commitment to deploy any of them.

> Note on our setup: we don't use Dokploy's one-click template mechanism. Services are defined as raw compose in `compose/docker-compose.yml`, routed via Traefik labels, image-pinned via `TF_VAR_*_IMAGE_TAG`, env via chezmoi. Anything adopted here gets re-shaped into that pattern.

## database / datastore

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| autobase | Orchestrator for self-hosted Postgres HA clusters (RDS-style). | is Postgres | [template](https://docs.dokploy.com/docs/templates/autobase) · [autobase.tech](https://autobase.tech/) |
| convex | Reactive backend platform with its own NoSQL store + TS functions. | own NoSQL | [template](https://docs.dokploy.com/docs/templates/convex) · [convex.dev](https://www.convex.dev/) |
| drizzle-gateway | Admin/proxy UI over Postgres/MySQL/SQLite — not a DB itself. | n/a (client) | [template](https://docs.dokploy.com/docs/templates/drizzle-gateway) · [drizzle docs](https://orm.drizzle.team/drizzle-gateway/overview) |

## infra / ops

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| ntfy | Topic-based push-notification server. | optional (sqlite/pg) | [template](https://docs.dokploy.com/docs/templates/ntfy) · [ntfy.sh](https://ntfy.sh/) |

## security / auth

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| authentik | Identity provider (OAuth2/OIDC/SAML), SSO. | Postgres | [template](https://docs.dokploy.com/docs/templates/authentik) · [goauthentik.io](https://goauthentik.io/) |
| vault | HashiCorp secrets management & encryption. | optional backend | [template](https://docs.dokploy.com/docs/templates/vault) · [vaultproject.io](https://www.vaultproject.io/) |
| vaultwarden | Lightweight Bitwarden-compatible password manager (Rust). | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/vaultwarden) · [github](https://github.com/dani-garcia/vaultwarden) |
| crowdsec | Collaborative IPS: log analysis + IP blocking. | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/crowdsec) · [crowdsec.net](https://www.crowdsec.net/) |

## observability / monitoring

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| grafana | Metrics/logs dashboards & visualization. | optional (sqlite/pg) | [template](https://docs.dokploy.com/docs/templates/grafana) · [grafana.com](https://grafana.com/) |
| signoz | APM/observability (traces, metrics, logs) on ClickHouse + Postgres. | ClickHouse + pg | [template](https://docs.dokploy.com/docs/templates/signoz) · [signoz.io](https://signoz.io/) |
| bugsink | Self-hosted, Sentry-SDK-compatible error tracking. | yes | [template](https://docs.dokploy.com/docs/templates/bugsink) · [bugsink.com](https://www.bugsink.com/) |
| changedetection | Website change monitoring + alerting. | sqlite | [template](https://docs.dokploy.com/docs/templates/changedetection) · [changedetection.io](https://changedetection.io/) |
| dokploy-prom-monitoring-extension | Prometheus metrics exporter for Dokploy. | no | [template](https://docs.dokploy.com/docs/templates/dokploy-prom-monitoring-extension) · [github](https://github.com/Dokploy/dokploy) |

## backup

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| backrest | Web UI for restic backups (scheduling/management). | sqlite | [template](https://docs.dokploy.com/docs/templates/backrest) · [github](https://github.com/garethgeorge/backrest) |
| borgitory | Web UI for BorgBackup repo management. | sqlite | [template](https://docs.dokploy.com/docs/templates/borgitory) · [github](https://github.com/mlapaglia/Borgitory) |

## productivity / notes

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| mealie | Recipe manager + meal planning + shopping lists. | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/mealie) · [mealie.io](https://mealie.io/) |
| blinko | Self-hosted note/memo app (card-style, AI features). | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/blinko) · [github](https://github.com/blinko-space/blinko) |
| grimoire | Self-hosted bookmark manager. | Postgres | [template](https://docs.dokploy.com/docs/templates/grimoire) · [github](https://github.com/goniszewski/grimoire) |
| cookie-cloud | Sync browser cookies to a self-hosted server. | local store | [template](https://docs.dokploy.com/docs/templates/cookie-cloud) · [github](https://github.com/easychen/CookieCloud) |

## media / books

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| calibre | Ebook library management + format conversion. | embedded | [template](https://docs.dokploy.com/docs/templates/calibre) · [calibre-ebook.com](https://calibre-ebook.com/) |
| calibre-web | Web reader/UI over a Calibre library. | sqlite | [template](https://docs.dokploy.com/docs/templates/calibre-web) · [github](https://github.com/janeczku/calibre-web) |
| booklore | Self-hosted digital library for ebooks/PDFs/comics. | MariaDB/MySQL | [template](https://docs.dokploy.com/docs/templates/booklore) · [github](https://github.com/booklore-app/booklore) |
| barrage | Minimalist Deluge torrent WebUI with mobile support. | no | [template](https://docs.dokploy.com/docs/templates/barrage) · [github](https://github.com/maulik9898/barrage) |

## feeds / RSS

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| rss-bridge | Generates RSS feeds for sites that lack them. | no | [template](https://docs.dokploy.com/docs/templates/rss-bridge) · [rss-bridge.org](https://rss-bridge.org/) |
| rsshub | Extensible RSS aggregator/generator. | optional | [template](https://docs.dokploy.com/docs/templates/rsshub) · [docs.rsshub.app](https://docs.rsshub.app/) |

## home / IoT

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| homeassistant | Home-automation hub integrating smart devices. | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/homeassistant) · [home-assistant.io](https://www.home-assistant.io/) |
| scrypted | Camera/NVR & smart-home video platform. | embedded | [template](https://docs.dokploy.com/docs/templates/scrypted) · [scrypted.app](https://www.scrypted.app/) |
| chirpstack | LoRaWAN network/application server. | Postgres + Redis | [template](https://docs.dokploy.com/docs/templates/chirpstack) · [chirpstack.io](https://www.chirpstack.io/) |

## dev-tools

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| omni-tools | Self-hosted collection of developer/web utilities. | no | [template](https://docs.dokploy.com/docs/templates/omni-tools) · [github](https://github.com/iib0011/omni-tools) |
| drawio | Diagram editor (flowcharts/UML/architecture). | no | [template](https://docs.dokploy.com/docs/templates/drawio) · [drawio.com](https://www.drawio.com/) |
| excalidraw | Collaborative hand-drawn-style whiteboard. | no | [template](https://docs.dokploy.com/docs/templates/excalidraw) · [excalidraw.com](https://excalidraw.com/) |
| minepanel | Docker-based web panel for managing Minecraft servers. | MySQL/MariaDB | [template](https://docs.dokploy.com/docs/templates/minepanel) · [github](https://github.com/Ketbome/minepanel) |

## finance / misc

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| maybe | Personal finance / spending tracker. | Postgres | [template](https://docs.dokploy.com/docs/templates/maybe) · [maybefinance.com](https://maybefinance.com/) |
| babybuddy | Baby/child tracking & milestone logging. | sqlite/pg | [template](https://docs.dokploy.com/docs/templates/babybuddy) · [github](https://github.com/babybuddy/babybuddy) |

## document management / PDFs

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| paperless-ngx | Scan/OCR/index/search documents. | Postgres + Redis | [docs.paperless-ngx.com](https://docs.paperless-ngx.com/) |
| stirling-pdf | Browser-based PDF toolbox (merge/split/OCR/etc). | no | [stirlingpdf.com](https://www.stirlingpdf.com/) |
| docuseal | Self-hosted document signing (DocuSign-style). | sqlite/pg | [docuseal.com](https://www.docuseal.com/) |

## privacy / networking (DNS / VPN / proxy)

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| adguard-home | Network-wide DNS ad/tracker blocking. | no | [adguard-home](https://adguard.com/en/adguard-home/overview.html) |
| headscale | Self-hosted Tailscale control server. | sqlite/pg | [github](https://github.com/juanfont/headscale) |
| pangolin | Tunneled reverse-proxy / WireGuard mesh access. | sqlite/pg | [github](https://github.com/fosrl/pangolin) |

## dashboards / homepages

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| homepage | Config-driven service dashboard w/ widgets. | no | [gethomepage.dev](https://gethomepage.dev/) |
| glance | Single-page feed/widget dashboard (YAML). | no | [github](https://github.com/glanceapp/glance) |
| dashy | Customizable startpage w/ status checks. | no | [dashy.to](https://dashy.to/) |

## project management / kanban

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| plane | Linear/Jira-style issues + cycles + modules. | Postgres + Redis | [plane.so](https://plane.so/) |
| vikunja | To-do + kanban + gantt, clean and light. | sqlite/pg/MySQL | [vikunja.io](https://vikunja.io/) |
| focalboard | Trello/Notion-style boards (Mattermost). | sqlite/pg | [github](https://github.com/mattermost/focalboard) |

## email / mail stack

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| stalwart | All-in-one JMAP/IMAP/SMTP mail server (Rust). | sqlite/embedded | [stalw.art](https://stalw.art/) |
| mailcow | Dockerized full mail suite (Postfix/Dovecot/SOGo). | MariaDB | [mailcow.email](https://mailcow.email/) |
| maddy | Single-binary composable mail server. | sqlite/pg | [maddy.email](https://maddy.email/) |

> Caveat: outbound mail from a Linode IP usually means deliverability
> pain (reputation, PTR, blocklists). Evaluate before investing.

## automation / workflows

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| n8n | Visual workflow/integration automation. | sqlite/pg | [n8n.io](https://n8n.io/) |
| windmill | Scripts/flows/UIs as code (TS/Python/Go). | Postgres | [windmill.dev](https://www.windmill.dev/) |
| huginn | Agents that watch and act on the web. | MySQL/pg | [github](https://github.com/huginn/huginn) |

## git forge / CI-CD

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| forgejo | Lightweight GitHub-style git forge (gitea fork). | sqlite/pg | [forgejo.org](https://forgejo.org/) |
| woodpecker-ci | Container-native CI, pairs with forgejo/gitea. | sqlite/pg | [woodpecker-ci.org](https://woodpecker-ci.org/) |
| harbor | Private OCI registry w/ vuln scanning + signing. | Postgres | [goharbor.io](https://goharbor.io/) |

## file sync / cloud storage

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| nextcloud | Full Drive/Office/Calendar/Contacts suite. | pg/MariaDB | [nextcloud.com](https://nextcloud.com/) |
| seafile | Fast, reliable file sync with library encryption. | sqlite/MySQL | [seafile.com](https://www.seafile.com/) |
| syncthing | Peer-to-peer continuous file sync (no server hub). | no | [syncthing.net](https://syncthing.net/) |
| copyparty | Portable file server: resumable uploads, WebDAV/FTP, media index. | optional sqlite | [github](https://github.com/9001/copyparty) |

## photos / memories

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| immich | Google-Photos-style backup w/ ML face/object search. | Postgres + Redis | [immich.app](https://immich.app/) |
| photoprism | AI-tagged photo library; browse by place/time/face. | sqlite/MariaDB | [photoprism.app](https://www.photoprism.app/) |
| librephotos | Self-hosted photo management with geotagging. | Postgres | [github](https://github.com/LibrePhotos/librephotos) |

## media streaming / management

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| jellyfin | Free media server (movies/TV/music), no licensing strings. | sqlite | [jellyfin.org](https://jellyfin.org/) |
| arr-stack | Media acquisition + indexers (sonarr/radarr/prowlarr). | sqlite | [wiki.servarr.com](https://wiki.servarr.com/) |
| navidrome | Subsonic-compatible music streaming server. | sqlite | [navidrome.org](https://www.navidrome.org/) |

## status / uptime monitoring

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| uptime-kuma | Self-hosted uptime monitor w/ status pages + alerts. | sqlite/MariaDB | [github](https://github.com/louislam/uptime-kuma) |
| gatus | Config-as-code health dashboard + SLA tracking. | sqlite/pg | [github](https://github.com/TwiN/gatus) |
| statping-ng | Status page w/ history graphs + notifications. | sqlite/pg/MySQL | [github](https://github.com/statping-ng/statping-ng) |

## health / fitness

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| wger | Workout manager + nutrition tracking. | sqlite/pg | [wger.de](https://wger.de/) |
| gymroutines | Self-hosted strength-training tracker. | sqlite/pg | [github](https://github.com/noahjutz/GymRoutines) |
| fittrackee | Outdoor activity / GPX workout logger. | Postgres | [github](https://github.com/SamR1/FitTrackee) |

## maps / location

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| traccar | GPS tracking server (devices/vehicles). | MySQL/pg/H2 | [traccar.org](https://www.traccar.org/) |
| owntracks | Private location-history recorder. | sqlite/MySQL/pg | [owntracks.org](https://owntracks.org/) |
| dawarich | Self-hosted Google-Timeline alternative. | Postgres + Redis | [dawarich.app](https://dawarich.app/) |

## recipes / meal planning

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| tandoor | Recipe manager w/ meal planning + shopping lists. | Postgres | [tandoor.dev](https://tandoor.dev/) |
| grocy | "ERP for your groceries" — stock, chores, recipes. | sqlite | [grocy.info](https://grocy.info/) |
| kitchenowl | Shared shopping lists + recipes, mobile-friendly. | sqlite/MariaDB | [kitchenowl.org](https://kitchenowl.org/) |

## personal finance / budgeting

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| firefly-iii | Double-entry budgeting + rules + reports. | MySQL/pg | [firefly-iii.org](https://www.firefly-iii.org/) |
| actual | Local-first envelope budgeting w/ sync. | sqlite | [actualbudget.org](https://actualbudget.org/) |
| ghostfolio | Wealth/portfolio + investment tracking. | Postgres + Redis | [ghostfol.io](https://ghostfol.io/) |

## audiobooks / podcasts

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| audiobookshelf | Audiobook + podcast server w/ progress sync. | sqlite | [audiobookshelf.org](https://www.audiobookshelf.org/) |
| podfetch | Self-hosted podcast manager + downloader. | sqlite/pg | [github](https://github.com/SamTV12345/PodFetch) |
| podgrab | Minimalist podcast archiver/auto-downloader. | sqlite | [github](https://github.com/akhilrex/podgrab) |

## comics / manga

| Service | What it does | Needs DB | Links |
| --- | --- | --- | --- |
| kavita | Fast reader for comics/manga/ebooks. | sqlite | [kavitareader.com](https://www.kavitareader.com/) |
| komga | Comic/manga media server w/ OPDS. | embedded (H2) | [komga.org](https://komga.org/) |
| mango | Manga server + web reader. | sqlite | [github](https://github.com/getmango/Mango) |
