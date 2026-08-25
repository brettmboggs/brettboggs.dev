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

Direction: **"Golden Hour"** (approved by Brett 2026-08-25) —
70s California concert-poster warmth run through Apple/Swiss restraint. Brett's
brief: "a hippie who went to college." Airy, light, professional-but-passion-project.

- **Palette:** oat paper #F4EDDF ground, espresso ink #33291C (never pure
  white/black), sunflower #D9971E, sienna #B85C38 (links), olive #6F7D4E,
  faded denim #7A93A7 (rare). Sun-faded earth tones only.
- **Type (Google Fonts):** Fraunces for display (opsz 144, SOFT ~60, WONK on),
  Instrument Sans for body, Spline Sans Mono for metadata/labels.
- **Motifs:** type-led — NO sun/rainbow/arch iconography (Brett vetoed it).
  Subtle film grain (~5% SVG noise), 2px espresso rules, bordered cards.
  One hero element per page, usually a big Fraunces headline.
- **Implementation:** tokens live in `src/styles/global.css`; fonts are
  self-hosted via Fontsource packages imported in `src/layouts/Base.astro`.
- **Motion:** few, slow, warm — long ease-outs (cubic-bezier(0.22,1,0.36,1)),
  ambient "breathing," ink-fill link underlines. Always respect
  prefers-reduced-motion.
- **Never:** tie-dye busyness, pattern-on-pattern, terminal/dev-portfolio
  aesthetics, skill bars, default-blue links, motion that delays reading.

## Deployment status

Repo: https://github.com/brettmboggs/brettboggs.dev (Brett is sole
contributor; public forks/PRs possible but no collaborators). Pages enabled
with workflow builds, custom domain brettboggs.dev set. Namecheap DNS is
Brett's manual step; HTTPS enforcement flips on after the cert issues.

## Working style

- Go one step at a time; let Brett review before moving on.
- Keep costs at $0 beyond the domain. Small one-off charges OK; no subscriptions.
- Brett knows GitHub from Datum; explain new tools/services rather than assuming.

## Commands

- `npm run dev` — local dev server
- `npm run build` — static build to `dist/` (also runs content type-gen)
- `npm run preview` — serve the built site locally
