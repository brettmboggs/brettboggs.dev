# brettboggs.dev

Personal site for Brett Boggs: portfolio, credibility page for Datum (AI-native
construction management, datumci.com), and a playground for experiments.

## Stack decisions (settled — don't relitigate)

- **Astro 5, fully static.** No SSR, no adapter. `site` is set to https://brettboggs.dev.
- **Hosting: GitHub Pages** with custom domain (public/CNAME), deployed by
  `.github/workflows/deploy.yml` on push to `main`. Domain registered at Namecheap;
  DNS points to GitHub Pages. No Vercel/Netlify — Brett wants everything in one
  GitHub account and $0 hosting.
- **No CSS framework.** Plain CSS with custom properties. The site must NOT look
  like a generic dev portfolio — no Tailwind defaults, no component libraries.
- **No UI framework globally.** If a page needs interactivity, add a framework
  island (or vanilla JS) scoped to that page only. GSAP is the approved choice
  when an animation outgrows CSS.
- **Content collections (Astro 5 API):** `src/content.config.ts` with `glob()`
  loaders — not the v4 `src/content/config.ts` API. Entries use `entry.id` as the
  slug and `render(entry)` imported from `astro:content`.

## Routes

- `/` — polished front door: who Brett is, what he's building, contact
- `/work` — case studies, Markdown in `src/content/work/`
- `/lab` — experiments; allowed to be rough. Each experiment is a page under `src/pages/lab/`
- `/writing` — posts, Markdown in `src/content/writing/`

Content frontmatter supports `draft: true` — drafts are filtered out of listings
and never get pages built.

## Design

Aesthetic direction is decided with Brett before writing design code — he
explicitly does not want a generic dev portfolio. Current pages are unstyled
placeholders awaiting that conversation.

## Working style

- Go one step at a time; let Brett review before moving on.
- Keep costs at $0 beyond the domain. Small one-off charges OK; no subscriptions.
- Brett knows GitHub from Datum; explain new tools/services rather than assuming.

## Commands

- `npm run dev` — local dev server
- `npm run build` — static build to `dist/` (also runs content type-gen)
- `npm run preview` — serve the built site locally
