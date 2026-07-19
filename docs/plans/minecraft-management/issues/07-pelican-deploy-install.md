# 07 — Deploy Pelican + first-boot install

**What to build:** Apply the Dokploy Layer to roll out the panel, then complete Pelican's one-time web installer (SQLite + filesystem cache) and create the admin user. Confirm `APP_KEY` reached the container and does **not** appear in the rendered compose content. The panel is then live and healthy at `daedalus.<tld>`.

**Blocked by:** 06.

**Status:** ready-for-human — the web installer and admin-credential capture are manual, one-time steps.

Source: ../spec.md (SP2 — one-time web installer is the chosen manual touch)

- [ ] Apply succeeds; a running `pelican` container has `APP_KEY` set and `BEHIND_PROXY=true`
- [ ] `APP_KEY` appears only as a `$${APP_KEY}` reference in the stack's compose content
- [ ] Web installer completed (SQLite + filesystem); admin credentials stored in Bitwarden
- [ ] `https://daedalus.<tld>/up` returns 200 and Traefik shows the service healthy
