// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

export default defineConfig({
  site: 'https://brettboggs.dev',
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
      // worker's fallback; /store/ is unfinished and sells nothing yet. All
      // are noindexed and unlisted.
      filter: (page) =>
        !page.includes('/roadmap/') &&
        !page.includes('/offline/') &&
        !page.includes('/store/') &&
        !page.includes('/admin/'),
    }),
  ],
});
