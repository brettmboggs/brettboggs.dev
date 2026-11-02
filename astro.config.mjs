// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';
import { execFileSync } from 'node:child_process';
import { existsSync } from 'node:fs';

// <lastmod> for the sitemap: the last commit to a page's own files (its
// template, its copy JSON, its Markdown entry). Shared layouts don't count, so
// a site-wide style change doesn't claim every page was updated. Pages with no
// dated source get no <lastmod>, which is better than a wrong one.
function lastmod(url) {
  const path = new URL(url).pathname.replace(/^\/|\/$/g, '');
  const parts = path ? path.split('/') : [];
  const files = [
    `src/data/copy/${path ? parts.join('-') : 'home'}.json`,
    `src/pages/${path || 'index'}.astro`,
    `src/pages/${path}/index.astro`,
  ];
  if (parts.length === 2) {
    files.push(`src/content/${parts[0]}/${parts[1]}.md`, `src/content/${parts[0]}/${parts[1]}.mdx`);
  }
  const found = files.filter((f) => existsSync(f));
  if (!found.length) return undefined;
  try {
    const iso = execFileSync('git', ['log', '-1', '--format=%cI', '--', ...found], { encoding: 'utf8' }).trim();
    return iso || undefined;
  } catch {
    return undefined;
  }
}

export default defineConfig({
  site: 'https://brettboggs.dev',
  // The app was called Nightjar when the first TestFlight build shipped, and
  // that build links to these paths from Settings and the paywall. Keep them
  // pointing at the new ones so an old install never lands on a 404.
  redirects: {
    '/nightjar/': '/slumbio/',
    '/nightjar/privacy/': '/slumbio/privacy/',
    '/nightjar/terms/': '/slumbio/terms/',
  },
  vite: {
    build: {
      // lightningcss folds animation-timeline into the extended animation
      // shorthand, which stable browsers reject; esbuild leaves it alone
      cssMinify: 'esbuild',
    },
  },
  integrations: [
    sitemap({
      // /roadmap/ is a working page for Brett; /offline/ is the service
      // worker's fallback; /store/ is unfinished and sells nothing yet;
      // /edit/ is the editor; /slumbio/ is the app's own page and should be found; only its policy
      // pages and the old /nightjar/ redirects stay out.
      filter: (page) =>
        !page.includes('/roadmap/') &&
        !page.includes('/offline/') &&
        !page.includes('/store/') &&
        !page.includes('/admin/') &&
        !page.includes('/edit/') &&
        !page.includes('/slumbio/privacy/') &&
        !page.includes('/slumbio/terms/') &&
        !page.includes('/ladle/privacy/') &&
        !page.includes('/nightjar/'),
      serialize(item) {
        const date = lastmod(item.url);
        if (date) item.lastmod = date;
        return item;
      },
    }),
  ],
});
