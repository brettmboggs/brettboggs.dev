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
    group: z.enum(['photography', 'websites']).optional(),
    // an entry that belongs on a second index as well. It keeps one page, at
    // its own group, and is listed from the other index too
    alsoIn: z.array(z.enum(['photography', 'websites'])).default([]),
    // bespoke entries have a hand-built page at src/pages/work/<id>.astro;
    // they appear in the index but are excluded from the generic [slug] template
    bespoke: z.boolean().default(false),
    // unlisted entries render at /work/<id>/ but stay off the /work index;
    // they are reached only from pages that link them (e.g. Datum's decision logs)
    unlisted: z.boolean().default(false),
  }),
});

// how-I-help pages: what I do, getting off a rented tool, straight answers.
// One template renders them all at /help/<id>/
const help = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/help' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    kind: z.enum(['service', 'switch', 'answer']),
    heading: z.string(),
    lede: z.string(),
    // the line under the heading on /help/
    summary: z.string(),
    order: z.number().default(100),
    price: z.object({ amount: z.string(), note: z.string() }).optional(),
    faq: z.array(z.object({ q: z.string(), a: z.string() })).default([]),
    related: z.array(z.string()).default([]),
    updated: z.coerce.date(),
    draft: z.boolean().default(false),
  }),
});

const writing = defineCollection({
  loader: glob({ pattern: '**/*.md', base: './src/content/writing' }),
  schema: z.object({
    title: z.string(),
    description: z.string(),
    date: z.coerce.date(),
    updated: z.coerce.date().optional(),
    draft: z.boolean().default(false),
  }),
});

export const collections = { work, help, writing };
