// One social card per page, drawn at build time in the site's own type and
// drawing-set look.
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
  font('@fontsource/archivo/files/archivo-latin-800-normal.woff'),
  font('@fontsource/ibm-plex-mono/files/ibm-plex-mono-latin-400-normal.woff'),
]);

// the drawing set: white sheet, grid, ink, one signal orange, blueprint blue
const BG = '#F5F5F1';
const GRID = '#E4E4DE';
const INK = '#111111';
const SOFT = '#5F5F59';
const SIG = '#FF4F00';
const BLUE = '#1F4FD8';

type Style = Record<string, string | number>;
type Node = { type: string; props: { style?: Style; children?: unknown } };
const el = (type: string, style: Style, children?: unknown): Node => ({ type, props: { style, children } });

export const GET: APIRoute = async ({ props }) => {
  const card = props.card as OgCard;
  const [archivo, mono] = await fonts;
  const long = card.title.length > 24;

  const cell = (label: string, value: string, last = false): Node =>
    el('div', { display: 'flex', flexDirection: 'column', padding: '10px 16px', borderRight: last ? 'none' : `2px solid ${INK}`, flexGrow: 1 }, [
      el('div', { display: 'flex', fontSize: 13, letterSpacing: 3, color: SOFT }, label),
      el('div', { display: 'flex', marginTop: 4, fontSize: 18, color: INK }, value),
    ]);

  const tree = el(
    'div',
    {
      display: 'flex',
      flexDirection: 'column',
      width: '100%',
      height: '100%',
      backgroundColor: BG,
      backgroundImage: `linear-gradient(${GRID} 1px, transparent 1px), linear-gradient(90deg, ${GRID} 1px, transparent 1px)`,
      backgroundSize: '30px 30px',
      padding: '56px 72px 52px',
      fontFamily: 'Plex Mono',
      color: INK,
    },
    [
      el('div', { display: 'flex', justifyContent: 'space-between', alignItems: 'center' }, [
        el('div', { display: 'flex', alignItems: 'center', fontSize: 20, letterSpacing: 4, textTransform: 'uppercase', color: SOFT }, [
          el('div', { display: 'flex', width: 14, height: 14, backgroundColor: SIG, marginRight: 14 }),
          card.kicker,
        ]),
        el('div', { display: 'flex', fontFamily: 'Archivo', fontSize: 30, letterSpacing: 0, textTransform: 'uppercase' }, [
          el('span', { display: 'flex' }, 'Brett Boggs'),
          el('span', { display: 'flex', color: SIG }, '.'),
        ]),
      ]),
      el(
        'div',
        { display: 'flex', flexGrow: 1, alignItems: 'center' },
        el(
          'div',
          {
            display: 'flex',
            fontFamily: 'Archivo',
            fontSize: long ? 78 : 112,
            lineHeight: 0.95,
            letterSpacing: -2,
            textTransform: 'uppercase',
            maxWidth: 1040,
          },
          card.title,
        ),
      ),
      el('div', { display: 'flex', fontSize: 22, lineHeight: 1.45, color: SOFT, maxWidth: 960, marginBottom: 22 }, card.note),
      el('div', { display: 'flex', border: `2px solid ${INK}`, backgroundColor: '#FFFFFF' }, [
        cell('DRAWN BY', 'B. BOGGS'),
        cell('SHEET', card.id.toUpperCase().slice(0, 14)),
        cell('PRACTICE', 'OPERATIONS & SYSTEMS'),
        el('div', { display: 'flex', flexDirection: 'column', padding: '10px 16px', flexGrow: 1 }, [
          el('div', { display: 'flex', fontSize: 13, letterSpacing: 3, color: SOFT }, 'WEB'),
          el('div', { display: 'flex', marginTop: 4, fontSize: 18, color: BLUE }, 'brettboggs.dev'),
        ]),
      ]),
    ],
  );

  const svg = await satori(tree as never, {
    width: 1200,
    height: 630,
    fonts: [
      { name: 'Archivo', data: archivo, weight: 800, style: 'normal' },
      { name: 'Plex Mono', data: mono, weight: 400, style: 'normal' },
    ],
  });
  const png = await sharp(Buffer.from(svg)).png({ compressionLevel: 9 }).toBuffer();
  return new Response(png, { headers: { 'Content-Type': 'image/png' } });
};
