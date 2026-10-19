// One social card per page, drawn at build time in the site's own type and
// counter look.
// satori lays the card out from a plain element tree and returns SVG with the
// glyphs already outlined; sharp rasterises it. No browser, no service, no
// runtime: the PNGs are just files in the build.
import type { APIRoute, GetStaticPaths } from 'astro';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import satori from 'satori';
import sharp from 'sharp';
import { getCollection } from 'astro:content';
import { cards, type OgCard } from '../../data/og';
import help from '../../data/copy/help.json';

// the hand-listed cards, plus one for every how-I-help page and post
export const getStaticPaths: GetStaticPaths = async () => {
  const guides = await getCollection('help', ({ data }) => !data.draft);
  const posts = await getCollection('writing', ({ data }) => !data.draft);
  const all: OgCard[] = [
    ...cards,
    ...guides.map((e) => ({ id: `help-${e.id}`, path: `/help/${e.id}/`, kicker: help.kinds[e.data.kind], title: e.data.heading, note: e.data.summary })),
    ...posts.map((p) => ({ id: `writing-${p.id}`, path: `/writing/${p.id}/`, kicker: 'Writing', title: p.data.title, note: p.data.description })),
  ];
  return all.map((card) => ({ params: { id: card.id }, props: { card } }));
};

// static cuts of the fonts the site already ships; satori reads woff, not woff2
const font = (p: string) => readFile(path.resolve(process.cwd(), 'node_modules', p));
const fonts = Promise.all([
  font('@fontsource/anybody/files/anybody-latin-900-normal.woff'),
  font('@fontsource/hanken-grotesk/files/hanken-grotesk-latin-400-normal.woff'),
  font('@fontsource/martian-mono/files/martian-mono-latin-400-normal.woff'),
]);

// the counter: cool counter-top grey, paper, ink, one signal orange
const BG = '#E4E7EB';
const SHEET = '#FCFCFA';
const INK = '#15171C';
const SOFT = '#6B717C';
const HAIR = '#C3C8D0';
const SIG = '#FF4F00';
const HIGHLIGHT = '#FFC2A6';

type Style = Record<string, string | number>;
type Node = { type: string; props: { style?: Style; children?: unknown } };
const el = (type: string, style: Style, children?: unknown): Node => ({ type, props: { style, children } });

// the homepage card carries a corner of the statement the hero reads
const statement = (): Node => {
  const row = (item: string, amount: string, gone: boolean): Node =>
    el('div', { display: 'flex', justifyContent: 'space-between', padding: '7px 8px', marginBottom: 4, borderRadius: 4, backgroundColor: gone ? HIGHLIGHT : 'transparent', color: gone ? SOFT : INK, textDecoration: gone ? 'line-through' : 'none' }, [
      el('span', { display: 'flex' }, item),
      el('span', { display: 'flex' }, amount),
    ]);
  return el('div', { display: 'flex', flexDirection: 'column', width: 400, padding: '26px 26px 22px', backgroundColor: SHEET, borderRadius: 6, fontFamily: 'Martian Mono', fontSize: 15, transform: 'rotate(2deg)', boxShadow: '0 30px 60px rgba(40,48,64,0.28)' }, [
    el('div', { display: 'flex', justifyContent: 'space-between', paddingBottom: 12, marginBottom: 10, borderBottom: `2px solid ${INK}` }, [
      el('span', { display: 'flex', fontFamily: 'Anybody', fontSize: 18, textTransform: 'uppercase' }, 'Business card'),
      el('span', { display: 'flex', color: SOFT, fontSize: 13 }, 'October'),
    ]),
    row('Scheduling app', '189.00', true),
    row('Accounting', '85.00', true),
    row('Fuel', '86.40', false),
    row('Reviews and texting', '399.00', true),
    row('Website builder', '39.00', true),
    el('div', { display: 'flex', justifyContent: 'space-between', padding: '9px 10px', marginTop: 6, borderRadius: 4, backgroundColor: INK, color: SHEET }, [
      el('span', { display: 'flex' }, 'Your own system'),
      el('span', { display: 'flex', color: SIG }, '400.00'),
    ]),
  ]);
};

export const GET: APIRoute = async ({ props }) => {
  const card = props.card as OgCard;
  const [anybody, hanken, mono] = await fonts;
  const home = card.id === 'home';
  const long = card.title.length > (home ? 16 : 24);

  const tree = el(
    'div',
    {
      display: 'flex',
      width: '100%',
      height: '100%',
      backgroundColor: BG,
      padding: '58px 72px 54px',
      fontFamily: 'Hanken Grotesk',
      color: INK,
    },
    [
      el('div', { display: 'flex', flexDirection: 'column', flexGrow: 1, flexShrink: 1, minWidth: 0 }, [
        el('div', { display: 'flex', fontFamily: 'Anybody', fontSize: 28, textTransform: 'uppercase' }, [
          el('span', { display: 'flex' }, 'Brett Boggs'),
          el('span', { display: 'flex', color: SIG }, '.'),
        ]),
        el('div', { display: 'flex', marginTop: 10, fontFamily: 'Martian Mono', fontSize: 16, color: SOFT, textTransform: 'uppercase', letterSpacing: 1 }, card.kicker),
        el(
          'div',
          { display: 'flex', flexGrow: 1, alignItems: 'center' },
          el('div', { display: 'flex', fontFamily: 'Anybody', fontSize: card.title.length > 44 ? 60 : long ? 72 : home ? 92 : 104, lineHeight: 0.95, letterSpacing: -3, maxWidth: home ? 620 : 1040 }, card.title),
        ),
        el('div', { display: 'flex', fontSize: 25, lineHeight: 1.4, color: '#4A4F59', maxWidth: home ? 600 : 940 }, card.note),
        el('div', { display: 'flex', alignItems: 'center', marginTop: 26, paddingTop: 18, borderTop: `1.5px solid ${HAIR}`, fontFamily: 'Martian Mono', fontSize: 16, color: SOFT }, [
          el('div', { display: 'flex', width: 12, height: 12, backgroundColor: SIG, marginRight: 12 }),
          'brettboggs.dev',
        ]),
      ]),
      ...(home ? [el('div', { display: 'flex', alignItems: 'center', marginLeft: 40 }, statement())] : []),
    ],
  );

  const svg = await satori(tree as never, {
    width: 1200,
    height: 630,
    fonts: [
      { name: 'Anybody', data: anybody, weight: 900, style: 'normal' },
      { name: 'Hanken Grotesk', data: hanken, weight: 400, style: 'normal' },
      { name: 'Martian Mono', data: mono, weight: 400, style: 'normal' },
    ],
  });
  const png = await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
  return new Response(png, { headers: { 'Content-Type': 'image/png' } });
};
