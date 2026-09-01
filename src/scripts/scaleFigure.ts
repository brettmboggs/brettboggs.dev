// A to-scale drawing of a product next to something the eye already knows.
//
// "16 x 24 inches" means very little to most people, and a buyer who has to
// guess is a buyer who is disappointed by the parcel. So the print is drawn
// against a six foot figure, and small things against a phone, both at true
// relative scale. Nothing here is decorative: if the rectangle looks big, the
// print is big.

export type Dims = { w: number; h: number; units: string };

type Reference = { label: string; w: number; h: number; kind: 'person' | 'phone' };

const PERSON: Reference = { label: '6 ft', w: 18, h: 72, kind: 'person' };
const PHONE: Reference = { label: 'phone', w: 3, h: 6.1, kind: 'phone' };

const BOX_H = 150;
// Wide enough that the height label sitting beside the item never collides
// with the reference figure standing next to it.
const GAP = 52;

/** Draws the item and its reference side by side, sharing one scale. */
export function scaleFigure(dims: Dims, name: string): SVGSVGElement {
  const ref = Math.max(dims.w, dims.h) >= 10 ? PERSON : PHONE;
  const tallest = Math.max(dims.h, ref.h);
  const k = BOX_H / tallest; // pixels per inch, shared by both shapes

  const iw = dims.w * k;
  const ih = dims.h * k;
  const rw = ref.w * k;
  const rh = ref.h * k;

  const width = iw + GAP + rw + 30; // room for the labels at both ends
  const svg = el('svg', {
    viewBox: `0 0 ${width} ${BOX_H + 26}`,
    width: String(width),
    height: String(BOX_H + 26),
    role: 'img',
    'aria-label': `${name} drawn to scale: ${dims.w} by ${dims.h} ${dims.units}, beside a ${ref.label} reference`,
  }) as SVGSVGElement;

  const base = BOX_H; // both shapes stand on the same ground line

  // ground line, so the two shapes are visibly on the same footing
  svg.appendChild(
    el('line', { x1: '0', y1: String(base + 0.5), x2: String(width), y2: String(base + 0.5), class: 'sf-ground' }),
  );

  // the product itself
  svg.appendChild(
    el('rect', { x: '0', y: String(base - ih), width: String(iw), height: String(ih), class: 'sf-item' }),
  );

  // its dimensions, in the mono face the rest of the site uses for figures
  const label = el('text', { x: String(iw + 6), y: String(base - ih + 11), class: 'sf-dim' });
  label.textContent = `${trim(dims.h)} ${dims.units}`;
  svg.appendChild(label);

  const wide = el('text', { x: String(iw / 2), y: String(base + 15), class: 'sf-dim sf-mid' });
  wide.textContent = `${trim(dims.w)} ${dims.units}`;
  svg.appendChild(wide);

  // the reference, drawn faintly so it reads as a yardstick and not a product
  const rx = iw + GAP;
  if (ref.kind === 'person') {
    svg.appendChild(personPath(rx, base, rw, rh));
  } else {
    svg.appendChild(
      el('rect', {
        x: String(rx),
        y: String(base - rh),
        width: String(rw),
        height: String(rh),
        rx: String(rw * 0.12),
        class: 'sf-ref',
      }),
    );
  }

  const refLabel = el('text', { x: String(rx + rw / 2), y: String(base + 15), class: 'sf-dim sf-mid sf-muted' });
  refLabel.textContent = ref.label;
  svg.appendChild(refLabel);

  return svg;
}

/** A plain standing figure. Enough to read as a person, not enough to distract. */
function personPath(x: number, base: number, w: number, h: number): SVGElement {
  const cx = x + w / 2;
  const headR = h * 0.055;
  const headCy = base - h + headR;
  const shoulder = headCy + headR * 1.9;
  const hip = base - h * 0.45;

  const g = el('g', { class: 'sf-ref' });
  g.appendChild(el('circle', { cx: String(cx), cy: String(headCy), r: String(headR) }));
  g.appendChild(el('line', { x1: String(cx), y1: String(shoulder), x2: String(cx), y2: String(hip) }));
  // arms
  g.appendChild(el('line', { x1: String(cx), y1: String(shoulder + h * 0.03), x2: String(cx - w * 0.42), y2: String(hip - h * 0.02) }));
  g.appendChild(el('line', { x1: String(cx), y1: String(shoulder + h * 0.03), x2: String(cx + w * 0.42), y2: String(hip - h * 0.02) }));
  // legs
  g.appendChild(el('line', { x1: String(cx), y1: String(hip), x2: String(cx - w * 0.3), y2: String(base) }));
  g.appendChild(el('line', { x1: String(cx), y1: String(hip), x2: String(cx + w * 0.3), y2: String(base) }));
  return g;
}

const trim = (n: number) => (Number.isInteger(n) ? String(n) : String(n));

function el(tag: string, attrs: Record<string, string>): SVGElement {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [k, v] of Object.entries(attrs)) node.setAttribute(k, v);
  return node as SVGElement;
}
