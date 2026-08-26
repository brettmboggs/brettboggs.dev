// Shared glyph-outline helpers for the icon and social-card builders.
//
// opentype's own toPathData() emits compact SVG path data that leans on
// implicit separators ("8.65-18Q..."). That is legal SVG, but librsvg (what
// sharp rasterises with) mis-parses it and silently drops contours, so glyphs
// come out missing serifs, tittles and whole strokes. Emitting every number
// space-delimited costs a few bytes and renders correctly.
export function pathData(path, precision = 3) {
  const n = (v) => Number(v.toFixed(precision));
  const out = [];
  for (const c of path.commands) {
    if (c.type === 'M') out.push(`M ${n(c.x)} ${n(c.y)}`);
    else if (c.type === 'L') out.push(`L ${n(c.x)} ${n(c.y)}`);
    else if (c.type === 'Q') out.push(`Q ${n(c.x1)} ${n(c.y1)} ${n(c.x)} ${n(c.y)}`);
    else if (c.type === 'C')
      out.push(`C ${n(c.x1)} ${n(c.y1)} ${n(c.x2)} ${n(c.y2)} ${n(c.x)} ${n(c.y)}`);
    else if (c.type === 'Z') out.push('Z');
  }
  return out.join(' ');
}

// Sets a run of characters on one baseline. opentype's getPath() on a whole
// string is unreliable here too, so glyphs are advanced by hand; `track` is
// letterspacing in em, matching CSS letter-spacing.
export function setRun(font, text, x, y, size, track = 0) {
  const glyphs = [];
  let cursor = x;
  for (const ch of text) {
    glyphs.push({ path: font.getPath(ch, cursor, y, size) });
    cursor += (font.charToGlyph(ch).advanceWidth / font.unitsPerEm) * size + track * size;
  }
  return { glyphs, width: cursor - x - track * size };
}
