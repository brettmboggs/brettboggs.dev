// Structured data the inner pages add to the homepage's identity graph. They
// point at the Person and the practice by @id instead of repeating them, so
// crawlers see one entity, described once, with many pages about its work.

import { inline } from './copy';

export const SITE = 'https://brettboggs.dev';
export const PERSON = { '@id': `${SITE}/#brett` };
export const PRACTICE = { '@id': `${SITE}/#practice` };

export const areaServed = [
  { '@type': 'AdministrativeArea', name: 'St. Charles County, Missouri' },
  { '@type': 'AdministrativeArea', name: 'St. Louis County, Missouri' },
  { '@type': 'City', name: 'St. Louis, Missouri' },
];

// answers are Markdown; structured data wants plain text, so drop the tags and
// undo the entities marked escapes
const plain = (s: string): string =>
  inline(s)
    .replace(/<[^>]+>/g, '')
    .replace(/&#39;/g, "'")
    .replace(/&quot;/g, '"')
    .replace(/&lt;/g, '<')
    .replace(/&gt;/g, '>')
    .replace(/&amp;/g, '&');

export const breadcrumb = (url: string, trail: { name: string; url: string }[]) => ({
  '@type': 'BreadcrumbList',
  '@id': `${url}#crumbs`,
  itemListElement: trail.map((t, i) => ({ '@type': 'ListItem', position: i + 1, name: t.name, item: t.url })),
});

export const faqPage = (url: string, faq: { q: string; a: string }[]) => ({
  '@type': 'FAQPage',
  '@id': `${url}#faq`,
  mainEntity: faq.map((f) => ({
    '@type': 'Question',
    name: f.q,
    acceptedAnswer: { '@type': 'Answer', text: plain(f.a) },
  })),
});

export const service = (url: string, name: string, description: string, price?: { amount: string; note: string }) => ({
  '@type': 'Service',
  '@id': `${url}#service`,
  name,
  description,
  url,
  provider: PRACTICE,
  areaServed,
  ...(price && {
    offers: {
      '@type': 'Offer',
      description: `${price.amount}. ${price.note}`,
      priceCurrency: 'USD',
      ...(/^\$[\d,]+$/.test(price.amount) && { price: price.amount.replace(/[$,]/g, '') }),
    },
  }),
});
