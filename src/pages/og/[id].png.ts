// One social card per page, drawn at build time in the site's own type.
// satori lays the card out from a plain element tree and returns SVG with the
// glyphs already outlined; sharp rasterises it. No browser, no service, no
// runtime: the PNGs are just files in the build.
import type { APIRoute, GetStaticPaths } from 'astro';
import { readFile } from 'node:fs/promises';
import path from 'node:path';
import satori from 'satori';
import sharp from 'sharp';
import { cards, type OgCard } from '../../data/og';

export const getStaticPaths: GetStaticPaths = () =>
  cards.map((card) => ({ params: { id: card.id }, props: { card } }));

// static cuts of the fonts the site already ships; satori reads woff, not woff2
const font = (p: string) => readFile(path.resolve(process.cwd(), 'node_modules', p));
const fonts = Promise.all([
  font('@fontsource/fraunces/files/fraunces-latin-600-normal.woff'),
  font('@fontsource/spline-sans-mono/files/spline-sans-mono-latin-400-normal.woff'),
]);

const PAPER = '#F4EDDF';
const INK = '#33291C';
const SOFT = '#6B5D48';
const RUST = '#8F3F22';
const SUN = '#D9971E';

type Style = Record<string, string | number>;
type Node = { type: string; props: { style?: Style; children?: unknown } };
const el = (type: string, style: Style, children?: unknown): Node => ({ type, props: { style, children } });

export const GET: APIRoute = async ({ props }) => {
  const card = props.card as OgCard;
  const [fraunces, mono] = await fonts;
  const long = card.title.length > 24;

  const tree = el(
    'div',
    {
      display: 'flex',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      background: PAPER,
      padding: '64px 84px 60px',
      fontFamily: 'Spline Sans Mono',
      color: INK,
    },
    [
      el(
        'div',
        {
          display: 'flex',
          justifyContent: 'space-between',
          alignItems: 'flex-end',
          fontSize: 22,
          letterSpacing: 4,
          textTransform: 'uppercase',
          color: RUST,
        },
        [
          el('div', { display: 'flex' }, card.kicker),
          el(
            'div',
            { display: 'flex', fontFamily: 'Fraunces', fontSize: 44, letterSpacing: -2, color: INK, textTransform: 'none' },
            [el('span', { display: 'flex' }, 'BB'), el('span', { display: 'flex', color: SUN }, '.')],
          ),
        ],
      ),
      el(
        'div',
        { display: 'flex', flexGrow: 1, alignItems: 'center' },
        el(
          'div',
          {
            display: 'flex',
            fontFamily: 'Fraunces',
            fontSize: long ? 76 : 116,
            lineHeight: 1.02,
            letterSpacing: long ? -2 : -4,
            maxWidth: 1000,
          },
          card.title,
        ),
      ),
      el('div', { display: 'flex', flexDirection: 'column', borderTop: `3px solid ${INK}`, paddingTop: 22 }, [
        el('div', { display: 'flex', fontSize: 24, lineHeight: 1.45, color: SOFT, maxWidth: 900 }, card.note),
        el('div', { display: 'flex', marginTop: 18, fontSize: 19, letterSpacing: 3, color: SOFT }, 'brettboggs.dev'),
      ]),
    ],
  );

  const svg = await satori(tree as never, {
    width: 1200,
    height: 630,
    fonts: [
      { name: 'Fraunces', data: fraunces, weight: 600, style: 'normal' },
      { name: 'Spline Sans Mono', data: mono, weight: 400, style: 'normal' },
    ],
  });
  const png = await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
  return new Response(png, { headers: { 'Content-Type': 'image/png' } });
};
