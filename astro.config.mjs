// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

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
      // /slumbio/ holds the app's support and policy pages until it ships.
      // All are noindexed and unlisted.
      filter: (page) =>
        !page.includes('/roadmap/') &&
        !page.includes('/offline/') &&
        !page.includes('/store/') &&
        !page.includes('/admin/') &&
        !page.includes('/slumbio/') &&
        !page.includes('/nightjar/'),
    }),
  ],
});
