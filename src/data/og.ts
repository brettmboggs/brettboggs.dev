// Social cards, one per page, rendered at build time by src/pages/og/[id].png.ts
// in the site's own type. Base.astro picks the card whose path matches the page,
// so a page needs no code of its own to get one. The homepage keeps og.png: the
// film is its card. The eclipse page brings its own photograph.

export type OgCard = {
  id: string;
  path: string;
  kicker: string;
  title: string;
  note: string;
};

export const cards: OgCard[] = [
  { id: 'work', path: '/work/', kicker: '01 · Work', title: 'Work', note: 'Case studies. The problem, the build, and what came of it.' },
  { id: 'lab', path: '/lab/', kicker: '02 · Lab', title: 'Lab', note: 'Experiments and unfinished things, allowed to be rough.' },
  { id: 'about', path: '/about/', kicker: '03 · About', title: 'Operator turned builder.', note: 'A decade running physical operations, then the software those operations deserved. St. Louis.' },
  { id: 'datum', path: '/work/datum/', kicker: 'Work · Datum', title: 'One system for running a construction company.', note: 'Co-founder. Product, design and engineering, end to end.' },
  { id: 'photography', path: '/work/photography/', kicker: 'Work · Photography', title: 'Photography', note: 'Sets shot on location, mostly in whatever light was already there.' },
  { id: 'commercial', path: '/work/photography/commercial/', kicker: 'Photography · 2021 to 2023', title: 'Commercial', note: 'Detailing, a car wash chain, and the people running them.' },
  { id: 'live-music', path: '/work/photography/live-music/', kicker: 'Photography · 2021 to 2023', title: 'Live Music', note: 'Bands on festival stages, in bar rooms, and one afternoon in a studio.' },
  { id: 'product', path: '/work/photography/product/', kicker: 'Photography · 2021 to 2022', title: 'Product', note: 'Bottles, cans, and goods on a small table.' },
  { id: 'trra', path: '/lab/trra/', kicker: 'Lab · Aug 2026', title: 'The MacArthur', note: 'A rail bridge approach in St. Louis, rebuilt to scale from public data so the job could be stood in.' },
  { id: 'field', path: '/lab/field/', kicker: 'Lab · Aug 2026', title: 'The Field', note: 'Every blade is a spring on your GPU, and the cursor is weather.' },
  { id: 'keepsake', path: '/lab/keepsake/', kicker: 'Lab · Aug 2026', title: 'Keepsake', note: 'A seeded drawing of a field, different for every visitor. Yours to keep.' },
  { id: 'sprout-siege', path: '/lab/sprout-siege/', kicker: 'Lab · Aug 2026', title: 'Sprout Siege', note: 'An idle farm game for iOS, built around a simulation core that never touches the screen.' },
  { id: 'ridge', path: '/lab/ridge/', kicker: 'Lab · Aug 2026', title: 'The Ridge', note: 'A golden hour flyover, rendered in Blender and scrubbed by scroll. It runs the front page.' },
  { id: 'underground', path: '/lab/underground/', kicker: 'Lab · Aug 2026', title: 'The Underground', note: 'The same ground as the Ridge, cut open six metres to rock. Roots grow as you scroll.' },
  { id: 'bridge', path: '/lab/bridge/', kicker: 'Lab · Jul 2026', title: 'The Bridge', note: 'A cable-stayed crossing that surveys, drafts, and builds itself as you scroll.' },
  { id: 'drafting-film', path: '/lab/drafting-film/', kicker: 'Lab · Jul 2026', title: 'The Drafting Film', note: 'A highway underpass you draft by scrolling.' },
  { id: 'colophon', path: '/colophon/', kicker: 'Colophon', title: 'How this site is made.', note: 'The tools, the pipeline, and the weight of every page.' },
  { id: 'log', path: '/log/', kicker: 'Log', title: 'The build log.', note: 'Every commit to this site, one line each, read out of git at build time.' },
  { id: 'resume', path: '/resume/', kicker: 'Resume', title: 'Brett Boggs', note: 'Co-founder of Datum. Builds the product end to end as full-stack engineer.' },
];

export const ogFor = (path: string): OgCard | undefined => cards.find((c) => c.path === path);
