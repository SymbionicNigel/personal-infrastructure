# 14 — Document the Minecraft management story

**What to build:** Capture the operator-facing story in long-lived docs (describe the pattern, not the plan). Add a "Pelican panel (daedalus)" subsection and a "Public player ingress (mc-router)" subsection to `linode/README.md` — run mode, state/backup/recovery, the Tailscale path to Wings, the no-new-DNS fact, and how wake-on-connect behaves for a player (the fail-then-retry join, not a bug). Fix the inaccurate "Caddy disabled" line in the architecture design doc to the `BEHIND_PROXY=true` reality.

The add-a-server runbook is authored in ticket 17 and lives in `linode/README.md` already — **reference it, do not duplicate it**.

Two things are worth stating plainly for a future reader, because both look like oversights and are decisions: mc-router's `DEFAULT` is unset on purpose (it is what drops unmatched traffic at the Host), and `CONNECTION_RATE_LIMIT` is set high on purpose (the limiter delays rather than drops, so a low value starves players).

**Blocked by:** 08, 10, 13, 16, 17 — document the mechanisms once they are real.

**Status:** ready-for-agent

Source: ../spec.md (topology; ingress hardening decisions; wake UX)

- [ ] `linode/README.md` gains Pelican + mc-router operator subsections
- [ ] Wake-on-connect's player-visible behaviour documented (first join fails, retry succeeds)
- [ ] The unset `DEFAULT` and the high rate limit are each recorded as deliberate, with why
- [ ] The runbook is referenced, not duplicated
- [ ] The architecture doc's Caddy line corrected to `BEHIND_PROXY=true`
- [ ] Markdown lints clean per the repo's `.markdownlint.yml`
