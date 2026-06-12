# iris — résumé page (ideas & brainstorming)

## Context

Split out of the main iris build (`2026-06-09-iris-frontend-design.md`), which
scaffolded a `/resume` route as a placeholder. That route has been **removed**
from iris for now (the `PAGES` registry no longer lists it, so `/resume`
currently 404s). The page wants real thought — this doc collects options to
brainstorm from, not a committed plan.

## Goals / constraints

- **Content is not committed to this repo** (it's public, Apache-2.0).
- **Single source of truth**, editable in one place.
- **Easy to update** — ideally without a redeploy.

## Data sourcing (the one part that feels decided)

- **No live LinkedIn source.** No open API for your own profile + scraping
  violates ToS — so LinkedIn is only a **one-time export** to seed the data.
- **`resume.json`** using the [JSON Resume](https://jsonresume.org) schema as
  the single source of truth, hosted outside this repo, fetched server-side by
  the route `loader` via an env-var URL (`RESUME_URL`) with a short cache +
  graceful fallback. Host TBD (private gist / object storage / build-time bake).

## Ideas to explore

### Content & sections
- Standard: summary, experience, skills, education.
- Extended: projects, open-source, certifications, publications, talks, awards,
  languages, interests.
- "Highlights" / featured strip at the top (a few signature things).
- Per-role detail vs. one-liner; expandable details on click.

### Layout & presentation
- Vertical **timeline** for experience (lean into the rainbow motif).
- Sidebar (contact + skills) alongside a main column, vs. single column.
- Compact "scan in 10 seconds" mode vs. a detailed reading mode (toggle).
- Continuity with the vintage system: cards, palette, and the heading-font
  switcher all apply to the résumé too.
- Subtle scroll-reveal / staggered entrance animations.

### Interactivity
- Filter / highlight experience by skill or keyword.
- Skill tags that filter the roles that used them.
- Density toggle (compact ↔ detailed).
- "Last updated" indicator sourced from the JSON.

### Export & formats
- Print stylesheet + a "Print / Save as PDF" button (clean browser print).
- A downloadable PDF (link to the source export, or generate one).
- Expose the raw `resume.json` (it's a portable standard) and/or plain text.

### Discoverability & sharing
- schema.org `Person` JSON-LD for rich search results.
- Open Graph / social card meta for nice link previews.
- Canonical link to LinkedIn / GitHub.

### Privacy
- Obfuscate or gate contact info (e.g., reveal-on-click, or a contact form
  instead of a raw email) since the page is public.
- Ability to hide specific fields from the public render.

### Freshness
- Cache strategy + optional revalidation hook so edits to the source show up
  promptly without a redeploy.

## Open questions

- Which sections matter most, and in what order?
- One canonical layout, or the compact/detailed toggle?
- Is a generated/downloadable PDF worth it, or is "print to PDF" enough?
- Where does `resume.json` live, and how fresh does it need to be?
