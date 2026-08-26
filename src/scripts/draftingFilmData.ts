// The Drafting Film - geometry and timeline, shared by the page template
// (which renders the SVG at build time) and the client loop (which conducts
// it). Ported from Datum's v5 landing intro, commit e095f7a in datum-core:
// a highway-underpass elevation the visitor drafts by scrolling.

/* ── Scroll timeline (fractions of track progress) ────────────────────── */

export const TRACK_VH = 760; // five beats + an unhurried turn

export const SCATTER_END = 0.16;
export const SILOS_END = 0.315;
export const LEAVE_END = 0.45;
export const CONFLICT_END = 0.56;
export const INERT_END = 0.66; // the low point holds longest
export const ASM_AT = 0.7; // assembly (registration snap) owns .70 to .88
export const ASM_SPAN = 0.18;
export const VEIL_AT = 0.955;

export const SEEN_KEY = 'bb.lab.drafting.seen';
export const FLD_SHEET = 2; // the sheet that walks out in beat 03

/* ── Copy - the five pain points, then the turn ───────────────────────── */

export interface BeatSpec {
  kicker: string;
  head: string[];
  sup?: string;
  window: [number, number]; // text visibility span within the track
}

export const BEATS: BeatSpec[] = [
  {
    kicker: 'Fragmented truth',
    head: ['Scattered data.', 'Nobody sees the same picture.'],
    window: [0.035, 0.15],
  },
  {
    kicker: 'Paying for the silos',
    head: ['Six systems. Six logins.', 'Six bills.'],
    sup: 'Each one holds a piece. None of them holds the project.',
    window: [0.175, 0.3],
  },
  {
    kicker: 'Knowledge walks out the door',
    head: ['Your best people leave.', 'The process leaves with them.'],
    window: [0.32, 0.44],
  },
  {
    kicker: 'Re-typing the same number',
    head: ['Same data,', 're-entered at every handoff.'],
    sup: 'Until nobody knows which number is true.',
    window: [0.46, 0.55],
  },
  {
    kicker: 'Storage, not intelligence',
    head: ['Your tools hold data.', 'None of them think.'],
    window: [0.575, 0.655],
  },
];

export const TURN_BEAT: BeatSpec = {
  kicker: 'Every measurement needs a reference',
  head: ['Set the datum.'],
  sup: 'One reference every number, drawing, and dollar measures from.',
  window: [0.71, 0.86],
};

export const MARK_TAG = 'One living record.';

export const SHEETS = [
  { tag: 'SYSTEM 01 - ESTIMATING', ax: 268, ay: 305 },
  { tag: 'SYSTEM 02 - PROJECT MGMT', ax: 806, ay: 292 },
  { tag: 'SYSTEM 03 - FIELD OPS', ax: 1332, ay: 305 },
  { tag: 'SYSTEM 04 - EQUIPMENT', ax: 268, ay: 655 },
  { tag: 'SYSTEM 05 - SAFETY', ax: 806, ay: 678 },
  { tag: 'SYSTEM 06 - FINANCE', ax: 1332, ay: 655 },
];

// Beat 04 - the same span, four values. Each stamps near a different sheet.
export const CONFLICTS = [
  { x: 268, y: 432, v: `48'-0"` },
  { x: 806, y: 420, v: `47'-6"` },
  { x: 1332, y: 784, v: `48'-2"` },
  { x: 560, y: 512, v: `46'-9"` },
];
export const TRUE_DIM = `48'-0"`;
export const TRUE_DIM_XY: [number, number] = [800, 542];

// Chapter rail - the film's controllability made literal.
export const CHAPTERS = [
  { label: 'Scattered', at: 0.06 },
  { label: 'Six systems', at: 0.22 },
  { label: 'Turnover', at: 0.365 },
  { label: 'Re-entry', at: 0.49 },
  { label: 'Dead storage', at: 0.6 },
  { label: 'The datum', at: 0.82 },
];

/* ── The drawing - a highway-underpass elevation in a 1600x900 sheet ──── */
// Sheet assignment is the silo story: each discipline owns only its slice.
//   0 EST dimensions · 1 PM span/centerline/callouts · 2 FLD earthwork (the
//   richest - it walks out) · 3 EQP substructure · 4 SAF parapet & rail ·
//   5 FIN elevation callouts.
// `order` is the construction-order stagger at the turn: footings first,
// stems, deck, parapet, rail, then the paper (dims, callouts, station).

export interface PathSpec {
  d: string;
  sheet: number;
  order: number;
  w?: number; // stroke width (user units)
  dash?: string; // native dash pattern (centerline, buried lines)
  redraw?: boolean; // FLD linework that re-draws stroke-by-stroke at the turn
  detail?: boolean; // hidden on small screens
}

export interface TextSpec {
  x: number;
  y: number;
  s: string;
  size: number;
  sheet: number;
  order: number;
  anchor?: 'start' | 'middle' | 'end';
  num?: boolean; // tabular numerals
  detail?: boolean;
}

// Earth hatch: short 45deg ticks stepped along a segment.
function hatchAlong(x0: number, y0: number, x1: number, y1: number, n: number): string {
  let d = '';
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    d += `M${(x0 + (x1 - x0) * t).toFixed(1)} ${(y0 + (y1 - y0) * t).toFixed(1)} l -13 13 `;
  }
  return d;
}

// Guardrail posts between the rail line and the pavement line.
function posts(
  xa: number,
  xb: number,
  railA: number,
  railB: number,
  paveA: number,
  paveB: number,
  n: number
): string {
  let d = '';
  for (let i = 0; i <= n; i++) {
    const t = i / n;
    const x = (xa + (xb - xa) * t).toFixed(1);
    d += `M${x} ${(railA + (railB - railA) * t).toFixed(1)} L${x} ${(paveA + (paveB - paveA) * t).toFixed(1)} `;
  }
  return d;
}

export const PATHS: PathSpec[] = [
  /* FLD - existing ground, cut slopes, the lower roadway, earth hatch */
  { d: 'M80 618 C200 610 320 618 452 612', sheet: 2, order: 0.2, redraw: true },
  { d: 'M452 612 L584 700', sheet: 2, order: 0.24, redraw: true },
  { d: 'M584 700 L1016 700', sheet: 2, order: 0.26, w: 1.7, redraw: true },
  { d: 'M1016 700 L1148 608', sheet: 2, order: 0.24, redraw: true },
  { d: 'M1148 608 C1270 604 1400 612 1520 610', sheet: 2, order: 0.2, redraw: true },
  { d: hatchAlong(104, 622, 440, 617, 9), sheet: 2, order: 0.3, w: 0.9, redraw: true, detail: true },
  { d: hatchAlong(478, 632, 572, 696, 3), sheet: 2, order: 0.3, w: 0.9, redraw: true, detail: true },
  { d: hatchAlong(614, 705, 990, 705, 10), sheet: 2, order: 0.32, w: 0.9, redraw: true, detail: true },
  { d: hatchAlong(1032, 694, 1130, 624, 3), sheet: 2, order: 0.3, w: 0.9, redraw: true, detail: true },
  { d: hatchAlong(1174, 612, 1498, 614, 9), sheet: 2, order: 0.3, w: 0.9, redraw: true, detail: true },

  /* EQP - abutments, buried footings, wingwalls */
  { d: 'M532 736 L532 424 L560 424 L560 452 L584 452 L584 736', sheet: 3, order: 0.1, w: 1.7 },
  { d: 'M1068 736 L1068 424 L1040 424 L1040 452 L1016 452 L1016 736', sheet: 3, order: 0.1, w: 1.7 },
  { d: 'M502 736 L614 736 L614 766 L502 766 Z', sheet: 3, order: 0.02, dash: '5 5' },
  { d: 'M986 736 L1098 736 L1098 766 L986 766 Z', sheet: 3, order: 0.02, dash: '5 5' },
  { d: 'M532 470 L448 566', sheet: 3, order: 0.16, dash: '5 5', detail: true },
  { d: 'M1068 470 L1152 566', sheet: 3, order: 0.16, dash: '5 5', detail: true },

  /* PM - girder, slab, centerline, leader callout */
  { d: 'M560 424 L1040 424 L1040 452 L560 452 Z', sheet: 1, order: 0.34, w: 1.7 },
  { d: 'M492 400 L1108 400 M492 424 L1108 424 M492 400 L492 424 M1108 400 L1108 424', sheet: 1, order: 0.38, w: 1.7 },
  { d: 'M800 330 L800 745', sheet: 1, order: 0.58, w: 0.9, dash: '20 7 4 7' },
  { d: 'M960 438 L1060 348 L1120 348', sheet: 1, order: 0.72, w: 0.9, detail: true },

  /* SAF - parapet band, approach pavement, guardrail + posts */
  { d: 'M492 400 L492 368 L1108 368 L1108 400', sheet: 4, order: 0.44, w: 1.7 },
  { d: 'M170 410 L492 402', sheet: 4, order: 0.48 },
  { d: 'M1108 402 L1430 410', sheet: 4, order: 0.48 },
  { d: 'M170 386 L492 380', sheet: 4, order: 0.52 },
  { d: 'M1108 380 L1430 386', sheet: 4, order: 0.52 },
  { d: posts(196, 466, 385.4, 380.5, 409.3, 402.6, 6), sheet: 4, order: 0.54, w: 0.9, detail: true },
  { d: posts(1134, 1404, 380.6, 385.5, 402.7, 409.4, 6), sheet: 4, order: 0.54, w: 0.9, detail: true },

  /* EST - dimension strings */
  {
    d:
      'M584 592 L584 548 M1016 592 L1016 548 M584 560 L1016 560 ' +
      'M584 560 l 14 -5 M584 560 l 14 5 M1016 560 l -14 -5 M1016 560 l -14 5',
    sheet: 0,
    order: 0.64,
    w: 0.9,
  },
  {
    d: 'M900 700 L900 452 M900 700 l -5 -14 M900 700 l 5 -14 M900 452 l -5 14 M900 452 l 5 14',
    sheet: 0,
    order: 0.66,
    w: 0.9,
  },
  {
    d: 'M1132 400 L1132 452 M1132 400 l -4 11 M1132 400 l 4 11 M1132 452 l -4 -11 M1132 452 l 4 -11',
    sheet: 0,
    order: 0.68,
    w: 0.9,
    detail: true,
  },

  /* FIN - elevation bugs (survey targets) */
  {
    d: 'M632 700 A8 8 0 1 0 648 700 A8 8 0 1 0 632 700 M640 686 L640 714 M626 700 L654 700',
    sheet: 5,
    order: 0.76,
    w: 0.9,
  },
  {
    d: 'M1172 400 A8 8 0 1 0 1188 400 A8 8 0 1 0 1172 400 M1180 386 L1180 414 M1166 400 L1194 400',
    sheet: 5,
    order: 0.76,
    w: 0.9,
  },
];

export const TEXTS: TextSpec[] = [
  { x: 800, y: 542, s: `${TRUE_DIM} CLEAR SPAN`, size: 17, sheet: 0, order: 0.64, anchor: 'middle', num: true },
  { x: 916, y: 585, s: `16'-6" MIN VERT CL`, size: 15, sheet: 0, order: 0.66, anchor: 'start', num: true },
  { x: 1146, y: 432, s: `4'-6"`, size: 14, sheet: 0, order: 0.68, anchor: 'start', num: true, detail: true },
  { x: 800, y: 314, s: 'CL', size: 14, sheet: 1, order: 0.6, anchor: 'middle' },
  { x: 800, y: 776, s: 'STA 142+50', size: 15, sheet: 1, order: 0.8, anchor: 'middle', num: true },
  { x: 1128, y: 353, s: 'PRESTRESSED GIRDER (TYP.)', size: 14, sheet: 1, order: 0.72, anchor: 'start', detail: true },
  { x: 640, y: 676, s: 'EL 700.00', size: 15, sheet: 5, order: 0.78, anchor: 'middle', num: true },
  { x: 1180, y: 376, s: 'EL 726.40', size: 15, sheet: 5, order: 0.78, anchor: 'middle', num: true },
];

export const N_PATHS = PATHS.length;
export const N_ELS = N_PATHS + TEXTS.length;
export const elSheet = (i: number): number => (i < N_PATHS ? PATHS[i].sheet : TEXTS[i - N_PATHS].sheet);
export const elOrder = (i: number): number => (i < N_PATHS ? PATHS[i].order : TEXTS[i - N_PATHS].order);

/* Turn-only furniture */
export const DATUM_LINE_D = 'M80 820 L1520 820';
export const DATUM_TICKS_D = (() => {
  let d = '';
  for (let x = 160; x <= 1440; x += 80) d += `M${x} 820 l 0 10 `;
  return d;
})();
export const DROPLINES = ['M640 712 L640 820', 'M1180 410 L1180 820', 'M800 745 L800 820'];
export const PULSE_D = 'M170 386 L492 380 L492 368 L1108 368 L1108 380 L1430 386';
