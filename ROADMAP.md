# Roadmap

Ten features approved 2026-08-26. Rendered at /roadmap/ (noindexed, unlisted)
so nothing gets forgotten. Update BOTH this file and src/pages/roadmap.astro
when status changes.

Statuses: LIVE (shipped), PARTIAL (some of it shipped), PLANNED (not started,
blocked on the listed next step).

| #  | Feature                          | Status  | Next step |
|----|----------------------------------|---------|-----------|
| 1  | Machine-readable layer           | PARTIAL | llms.txt, resume.json, homepage JSON-LD are live. MCP server is WRITTEN at tools/mcp (Cloudflare Worker, stateless Streamable HTTP; tools proxy llms.txt/resume.json live so nothing can drift). Brett's 10-minute deploy steps are in tools/mcp/README.md; after deploy, add the URL to llms.txt and flip this to LIVE. |
| 2  | Playable product slices          | PLANNED | PARKED by Brett 2026-08-26: "a playable version of Datum honestly might not be very valuable without pushing real work through." Revisit when a slice has real work in it. Game half still viable: Sprout Siege GameCore is pure UI-free deterministic Swift (repo on the Mac); SwiftWasm compiles it, thin JS shell renders it. |
| 3  | Case studies as decision logs    | PARTIAL | All three templates drafted (draft: true, invisible until filled): tenant-isolation.md, session-prompting.md, erp-writeback.md in src/content/work/. Each needs Brett's real numbers and war stories in the TODOs. |
| 4  | View transitions + scroll-driven | LIVE    | Cross-document view transitions and scroll-driven entry reveals, native CSS, zero JS, reduced-motion guarded. |
| 5  | WebGPU hero moment               | LIVE    | "The Field" (Brett approved placement 2026-08-26): hero of /lab/ and its own page at /lab/field/. Compute-shader prairie: per-blade spring dynamics, traveling wind, light waves, pointer parting wake, drifting seed particles. src/scripts/field.ts + FieldScene.astro. Feature-detected; reduced motion or no WebGPU gets a deterministic SVG still. Homepage film untouched. |
| 6  | Typography as art direction      | LIVE    | Approved by Brett 2026-08-26 with the condition that the homepage headline stays in sync with the film. Page-head h1s interpolate Fraunces axes (opsz 144→28, SOFT 60→100) on a view() exit timeline, native CSS. Homepage never uses .page-head, so the film headline is untouched. |
| 7  | Live proof-of-work feed          | PARTIAL | Live strip on /roadmap/ (client-side GitHub API, fetched at view time so it cannot go stale). Public placement waits on Brett's decision about which sources count; public events only show this repo today. |
| 8  | Embedded 3D/CAD viewer           | PLANNED | Infrastructure DONE and shelved: tools/parts/convert.py (Blender headless, STL/3MF to GLB, mm to m, decimate, stacks assemblies) + src/scripts/partsViewer.ts (three-based orbit viewer; model-viewer rejected, peer-conflicts with three 0.185). HARD RULE learned 2026-08-26: a first version shipped with models Brett had NOT approved (one inappropriate, two not his). Never again — models go live only when Brett names the files and explicitly approves the page. When he does: add to parts.json, run converter, recreate src/pages/lab/parts.astro (in git history at 2b76bc7). |
| 9  | Offline-first PWA                | LIVE    | Installable (display: standalone) + public/sw.js v2: core pages and posters precached at install, network-first navigations (never a stale deploy), cache-first hashed assets, offline fallback page. Film frame sequences stay online-only by design. |
| 10 | Generative visitor keepsake      | LIVE    | /lab/keepsake/ · seeded deterministic SVG, shareable by URL, downloadable. |
