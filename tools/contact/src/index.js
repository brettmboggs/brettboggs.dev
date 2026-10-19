// Contact endpoint for brettboggs.dev, as a Cloudflare Worker.
//
// The homepage form posts name, email and message here. Each one becomes a
// plain-text email to Brett with the sender as Reply-To, so answering is just
// hitting reply. With script, the page posts by fetch and asks for JSON; a
// browser without script posts the form itself and is sent back to /#sent.

import { EmailMessage } from 'cloudflare:email';

const LIMITS = { name: 200, email: 320, message: 5000 };
const EMAIL = /^[^@\s]+@[^@\s]+\.[^@\s]+$/;

export default {
  async fetch(req, env) {
    const origin = req.headers.get('Origin') ?? '';
    const allowed = env.ALLOWED_ORIGINS.split(',').map((o) => o.trim());
    const cors = allowed.includes(origin)
      ? { 'Access-Control-Allow-Origin': origin, 'Access-Control-Allow-Methods': 'POST, OPTIONS', 'Access-Control-Allow-Headers': 'Accept', Vary: 'Origin' }
      : {};

    if (req.method === 'OPTIONS') return new Response(null, { status: 204, headers: cors });
    if (req.method !== 'POST') return new Response('Method not allowed', { status: 405, headers: cors });
    if (!cors['Access-Control-Allow-Origin']) return new Response('Forbidden', { status: 403 });

    const json = (req.headers.get('Accept') ?? '').includes('application/json');
    const reply = (status, error) =>
      json
        ? Response.json(error ? { error } : { ok: true }, { status, headers: cors })
        : status === 200
          ? Response.redirect(`${origin}/#sent`, 303)
          : new Response(error, { status, headers: cors });

    // The Origin header can be faked, so also cap how often one address can send.
    const ip = req.headers.get('CF-Connecting-IP') ?? '';
    if (env.LIMITER && !(await env.LIMITER.limit({ key: ip })).success) return reply(429, 'Too many messages. Try again in a minute.');

    if (Number(req.headers.get('Content-Length') ?? 0) > 64 * 1024) return reply(413, 'That message is too long.');

    let form;
    try {
      form = await req.formData();
    } catch {
      return reply(400, 'Bad request');
    }
    const field = (k) => String(form.get(k) ?? '').trim().slice(0, LIMITS[k] ?? 200);

    // Bots fill every field; people never see this one.
    if (field('company')) return reply(200);

    const name = field('name').replace(/[\r\n]+/g, ' ');
    const email = field('email');
    const message = field('message');
    if (!name || !message) return reply(422, 'Add your name and a message.');
    if (!EMAIL.test(email)) return reply(422, 'That email address does not look right.');

    const raw = mime({
      from: `brettboggs.dev <${env.FROM_EMAIL}>`,
      to: env.TO_EMAIL,
      replyTo: `${name} <${email}>`,
      subject: `Contact: ${name}`,
      text: [message, '', `${name} · ${email}`, '', `Sent from the form on ${env.SITE}`].join('\n'),
      domain: env.FROM_EMAIL.split('@')[1],
    });

    try {
      await env.MAIL.send(new EmailMessage(env.FROM_EMAIL, env.TO_EMAIL, raw));
    } catch (err) {
      console.error('send failed', err);
      return reply(502, 'That did not go through.');
    }
    return reply(200);
  },
};

// A plain-text UTF-8 message. Header words that are not ASCII are encoded so a
// name with an accent survives; the body is base64 so line length never matters.
function mime({ from, to, replyTo, subject, text, domain }) {
  const b64 = (s) => btoa(String.fromCharCode(...new TextEncoder().encode(s)));
  const word = (s) => (/^[\x20-\x7e]*$/.test(s) ? s : `=?UTF-8?B?${b64(s)}?=`);
  const addr = (s) => s.replace(/^(.*?)\s*(<[^>]+>)$/, (_, n, a) => `${word(n)} ${a}`);
  const body = b64(text).replace(/.{76}/g, '$&\r\n');
  return [
    `From: ${from}`,
    `To: ${to}`,
    `Reply-To: ${addr(replyTo)}`,
    `Subject: ${word(subject)}`,
    `Date: ${new Date().toUTCString()}`,
    `Message-ID: <${crypto.randomUUID()}@${domain}>`,
    'MIME-Version: 1.0',
    'Content-Type: text/plain; charset=UTF-8',
    'Content-Transfer-Encoding: base64',
    '',
    body,
  ].join('\r\n');
}
