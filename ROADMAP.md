# Roadmap

Ten features approved 2026-08-26. Rendered at /roadmap/ (noindexed, unlisted)
so nothing gets forgotten. Update BOTH this file and src/pages/roadmap.astro
when status changes.

Statuses: LIVE (shipped), PARTIAL (some of it shipped), PLANNED (not started,
blocked on the listed next step).

| #  | Feature                          | Status  | Next step |
|----|----------------------------------|---------|-----------|
| 1  | Machine-readable layer           | PARTIAL | llms.txt, resume.json, homepage JSON-LD are live. MCP endpoint needs a host that answers POST; GitHub Pages cannot. Options: Cloudflare Worker (free, new account) or Azure Functions (existing Datum account). Brett decides. |
| 2  | Playable product slices          | PLANNED | Needs a seeded Datum demo tenant (sandboxed iframe) and a WASM build of the garden-defense game. Budget 1 hr/quarter to keep demo data from rotting. |
| 3  | Case studies as decision logs    | PARTIAL | Template drafted at src/content/work/tenant-isolation.md (draft: true, invisible until filled). Needs Brett's real numbers and stories; copy it for RLS-vs-app-layer and session prompting. |
| 4  | View transitions + scroll-driven | LIVE    | Cross-document view transitions and scroll-driven entry reveals, native CSS, zero JS, reduced-motion guarded. |
| 5  | WebGPU hero moment               | LIVE    | "The Field" (Brett approved placement 2026-08-26): hero of /lab/ and its own page at /lab/field/. Compute-shader prairie: per-blade spring dynamics, traveling wind, light waves, pointer parting wake, drifting seed particles. src/scripts/field.ts + FieldScene.astro. Feature-detected; reduced motion or no WebGPU gets a deterministic SVG still. Homepage film untouched. |
| 6  | Typography as art direction      | LIVE    | Approved by Brett 2026-08-26 with the condition that the homepage headline stays in sync with the film. Page-head h1s interpolate Fraunces axes (opsz 144→28, SOFT 60→100) on a view() exit timeline, native CSS. Homepage never uses .page-head, so the film headline is untouched. |
| 7  | Live proof-of-work feed          | PARTIAL | Live strip on /roadmap/ (client-side GitHub API, fetched at view time so it cannot go stale). Public placement waits on Brett's decision about which sources count; public events only show this repo today. |
| 8  | Embedded 3D/CAD viewer           | PLANNED | Needs GLB exports from Brett's CAD work, then a model-viewer page. |
| 9  | Offline-first PWA                | PARTIAL | Installable (display: standalone) + public/sw.js: network-first navigations (never a stale deploy), cache-first hashed assets, offline fallback page, film frames excluded. Full precache of core pages is the remaining step. |
| 10 | Generative visitor keepsake      | LIVE    | /lab/keepsake/ · seeded deterministic SVG, shareable by URL, downloadable. |
