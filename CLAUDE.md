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
- **Motion:** hero and scroll animations are a CORE component of this site,
  not a garnish. 3D (Three.js particles/WebGL) in the homepage hero: the name
  forms from particles, breathes, and dissolves into an abstract organic form
  on scroll. Scope: hero + smaller accents on section pages; NOT a whole-site
  scroll-jack. GSAP + ScrollTrigger drives scroll. Long warm ease-outs
  (cubic-bezier(0.22,1,0.36,1)). Simplified particle budgets on mobile.
  Always respect prefers-reduced-motion (static/2D fallback) and no-WebGL
  (2D GSAP fallback).
- **Never:** tie-dye busyness, pattern-on-pattern, terminal/dev-portfolio
  aesthetics, skill bars, default-blue links, motion that delays reading,
  card grids (Brett flagged them as AI-slop; use editorial index rows).

## Hero direction (reset 2026-08-25, after two rejected attempts)

Brett REJECTED: big bold display of his own name (particle version AND solid
3D bronze version) — "super cringey" from a visitor's POV. Identity lives in a
small "BB." monogram in the navbar, nothing bigger.

The bar he set: mercury.com's hero — a pre-rendered cinematic scene (nature,
desk, laptop) scrubbed by scroll that zooms into the laptop where product
animations take over. Verified mechanism: start/end poster JPGs + a scroll-
scrubbed video (`hero-scrub-md.mp4`, byte-range seeks) + follow-on clips.
"This is the standard or better." Approved concept: **"The Ridge"** — slow
golden-hour prairie flyover discovering a lone timber-frame structure on the
ridge, camera glides through the beams, settles on the horizon; content rises
over the final frame.

Brett's production mandate (2026-08-25): PHOTOREALISTIC or as close as
possible — "not something a child could make," no "bad cartoon." Take more
time rather than showing mediocre results. Use free assets (Poly Haven CC0
HDRIs/textures/models) for quality and speed; $0 budget ($5 absolute max if
unavoidable). UE5 not needed — Blender Cycles renders the film. Blender with
MCP addon runs on Brett's machine; long renders go through background
`blender -b` on the saved .blend, not the live UI.

## Feature roadmap (approved 2026-08-26)

Ten features Brett approved live in ROADMAP.md and render at /roadmap/
(noindexed, unlisted, filtered from the sitemap). Keep ROADMAP.md and
src/pages/roadmap.astro in sync whenever a feature ships or stalls. The
machine-readable layer (public/llms.txt, public/resume.json, homepage JSON-LD)
must stay curated and factual: only claims that already appear on the site.
Update llms.txt and resume.json when /work content changes.

Gotcha: scroll-driven animations (animation-timeline/animation-range) must be
written as LONGHANDS, and astro.config pins cssMinify: 'esbuild'. lightningcss
folds them into the extended `animation:` shorthand, which stable browsers
reject, silently killing the animation. Verify computed animationName in the
browser after touching these rules.

## Voice (Brett flagged violations, take these seriously)

- Stoic, chill, minimal. Few words. The site shows, it does not tell.
- NO cheesy taglines or metaphors ("front porch," "warm hand" style lines are out).
- NO em-dashes anywhere in site copy or titles. Use periods, commas, or "·".
- Do not narrate what Brett is currently building on the homepage; projects
  live in /work on their own terms.
- The visitor should feel like they wanted to be here, not like they are
  doing research.

## Never mention AI

Zero references to AI, Claude, or AI-assisted authorship anywhere: site copy,
commit messages, README, PR descriptions, repo metadata. Do NOT add
Co-Authored-By trailers to commits in this repo.

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
