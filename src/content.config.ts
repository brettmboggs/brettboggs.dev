import { defineCollection, z } from 'astro:content';
import { glob } from 'astro/loaders';

const work = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/work' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    // ongoing bodies of work carry a span instead of a single day
    dateEnd: z.coerce.date().optional(),
    tags: z.array(z.string()).default([]),
    draft: z.boolean().default(false),
    // grouped entries are collapsed into a single row on /work and listed
    // on their own index at /work/<group>/
    group: z.enum(['photography']).optional(),
    // bespoke entries have a hand-built page at src/pages/work/<id>.astro;
    // they appear in the index but are excluded from the generic [slug] template
    bespoke: z.boolean().default(false),
  }),
});

export const collections = { work };
