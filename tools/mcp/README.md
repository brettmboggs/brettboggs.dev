# MCP server

Lets anyone point an MCP client (Claude, or any agent that speaks the
protocol) at a URL and interrogate Brett's work. The worker holds no content:
every tool fetches the site's own llms.txt and resume.json at request time,
so answers can never drift from what the site publishes.

GitHub Pages is static and cannot answer POST requests, so this one piece
runs on Cloudflare Workers (free tier, no card required). It is the only
part of the site not hosted on GitHub.

## Deploy (Brett's steps, roughly 10 minutes)

1. Create a free account at https://dash.cloudflare.com/sign-up
   (the free Workers plan covers 100,000 requests per day; this will see a
   tiny fraction of that).
2. In a terminal:

   ```
   cd tools/mcp
   npx wrangler login
   npx wrangler deploy
   ```

   `wrangler` is Cloudflare's CLI; `npx` runs it without installing anything
   globally. `login` opens the browser to authorize; `deploy` uploads
   worker.js and prints the live URL, which will look like
   `https://brettboggs-mcp.<your-subdomain>.workers.dev`.

3. Sanity check it:

   ```
   curl -X POST https://brettboggs-mcp.<your-subdomain>.workers.dev/ \
     -H "Content-Type: application/json" \
     -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}'
   ```

   You should get back the two tools.

4. Tell the site about it: add the URL under "Machine-readable" in
   public/llms.txt, and flip roadmap item 01 to Live.

## Getting it onto brettboggs.dev/mcp later (optional)

Workers can only answer on the apex domain if the domain's DNS lives at
Cloudflare. That means moving DNS from Namecheap to Cloudflare (free, the
domain registration itself stays at Namecheap) and re-creating the four
GitHub Pages records there. Until that feels worth it, the workers.dev URL
works identically; agents do not care what the hostname looks like.

## Azure alternative

The same logic would run as an Azure Functions HTTP trigger on the existing
Datum account. It was not chosen here because the consumption plan cold
starts are slow, the setup is heavier, and this keeps personal-site
infrastructure out of the company subscription. If that tradeoff changes,
worker.js ports over with minor edits.
