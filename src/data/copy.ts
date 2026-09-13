// Site copy lives in src/data/copy/<page>.json so it can be edited at /edit/
// without touching a template. Short fields render as plain text. Fields that
// carry links or emphasis are written in Markdown and rendered with these two.

import { marked } from 'marked';

/** Markdown block: paragraphs, headings, lists. Use with set:html. */
export const md = (s = ''): string => marked.parse(s, { async: false }) as string;

/** Markdown inside an element that already exists: links and emphasis, no <p>. */
export const inline = (s = ''): string => marked.parseInline(s, { async: false }) as string;
