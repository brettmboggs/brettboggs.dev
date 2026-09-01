// Weighs the built site and writes the result into the colophon.
//
// Runs after `astro build`. For every page in dist it counts the HTML, every
// stylesheet the page links, and every script the page loads plus everything
// those scripts can reach through imports, each gzipped the way a browser
// would receive it. Pictures, film frames and models are left out on purpose:
// they are most of what a visitor sees and none of what this table is about.
//
// The colophon carries a `<!--weigh-->` marker; this script replaces it.
import { readdir, readFile, writeFile } from 'node:fs/promises';
import { gzipSync } from 'node:zlib';
import path from 'node:path';

const DIST = path.resolve('dist');
const SKIP = [/^\/admin\//, /^\/og\//, /^\/offline\//, /^\/roadmap\//, /^\/store\//, /^\/404\//];

async function pages(dir, out = []) {
  for (const e of await readdir(dir, { withFileTypes: true })) {
    const p = path.join(dir, e.name);
    if (e.isDirectory()) await pages(p, out);
    else if (e.name === 'index.html') out.push(p);
  }
  return out;
}

const sizes = new Map();
async function gz(rel) {
  if (!sizes.has(rel)) {
    try {
      sizes.set(rel, gzipSync(await readFile(path.join(DIST, rel)), { level: 9 }).length);
    } catch {
      sizes.set(rel, 0);
    }
  }
  return sizes.get(rel);
}

// follow static and dynamic imports so a page that pulls in a chunk on demand
// is charged for it; that is the honest number, not the first paint one
const graph = new Map();
async function reach(rel, seen = new Set()) {
  if (seen.has(rel)) return seen;
  seen.add(rel);
  if (!graph.has(rel)) {
    let deps = [];
    try {
      const src = (await readFile(path.join(DIST, rel))).toString();
      const found = new Set();
      for (const m of src.matchAll(/(?:from|import)\s*["']([^"']+)["']/g)) found.add(m[1]);
      for (const m of src.matchAll(/import\(\s*["']([^"']+)["']\s*\)/g)) found.add(m[1]);
      deps = [...found]
        .filter((s) => s.startsWith('.') || s.startsWith('/'))
        .map((s) => (s.startsWith('/') ? s : path.posix.join(path.posix.dirname(rel), s)));
    } catch {
      deps = [];
    }
    graph.set(rel, deps);
  }
  for (const d of graph.get(rel)) await reach(d, seen);
  return seen;
}

const kb = (n) => (n / 1024).toFixed(1);
const rows = [];

for (const file of await pages(DIST)) {
  const dir = path.relative(DIST, path.dirname(file)).split(path.sep).join('/');
  const url = dir ? `/${dir}/` : '/';
  if (SKIP.some((re) => re.test(url))) continue;

  const html = (await readFile(file)).toString();
  const css = [...html.matchAll(/<link[^>]+rel="stylesheet"[^>]+href="(\/_astro\/[^"]+)"/g)].map((m) => m[1]);
  const scripts = [...html.matchAll(/<script[^>]+src="(\/_astro\/[^"]+)"/g)].map((m) => m[1]);

  const htmlGz = gzipSync(Buffer.from(html), { level: 9 }).length;
  let cssGz = 0;
  for (const c of new Set(css)) cssGz += await gz(c);
  const js = new Set();
  for (const s of scripts) for (const r of await reach(s)) js.add(r);
  let jsGz = 0;
  for (const j of js) jsGz += await gz(j);

  rows.push({ url, html: htmlGz, css: cssGz, js: jsGz, total: htmlGz + cssGz + jsGz });
}

rows.sort((a, b) => (a.url === '/' ? -1 : b.url === '/' ? 1 : a.url.localeCompare(b.url)));

const esc = (s) => s.replace(/&/g, '&amp;').replace(/</g, '&lt;');
const table = `<table>
<thead><tr><th>Page</th><th>HTML</th><th>CSS</th><th>Script</th><th>Total</th></tr></thead>
<tbody>
${rows
  .map(
    (r) =>
      `<tr><td><a href="${esc(r.url)}">${esc(r.url)}</a></td><td>${kb(r.html)}</td><td>${kb(r.css)}</td><td>${kb(r.js)}</td><td>${kb(r.total)}</td></tr>`,
  )
  .join('\n')}
</tbody>
</table>
<p class="weigh-note">Kilobytes, gzipped, measured on ${new Date().toISOString().slice(0, 10)} across ${rows.length} pages. Styles that ship inline with a page count as HTML. Script includes every chunk the page can reach.</p>`;

const colophon = path.join(DIST, 'colophon', 'index.html');
try {
  const src = (await readFile(colophon)).toString();
  if (!src.includes('<!--weigh-->')) throw new Error('no marker');
  await writeFile(colophon, src.replace('<!--weigh-->', table));
  console.log(`weigh: ${rows.length} pages written into /colophon/`);
} catch (e) {
  console.warn(`weigh: colophon not updated (${e.message})`);
}
