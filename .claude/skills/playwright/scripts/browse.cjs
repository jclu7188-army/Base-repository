#!/usr/bin/env node
// one-shot headless browsing from the command line with playwright: fetch a url in real chromium
// (javascript executed) and emit text, html, links, a screenshot, a pdf, or the result of a js
// expression. generic: browser comes from playwright's cache or CHROME_PATH.
//
//   browse.cjs text URL [--wait networkidle|load|domcontentloaded] [--selector CSS]
//   browse.cjs html URL [--selector CSS]
//   browse.cjs links URL
//   browse.cjs screenshot URL --out shot.png [--full] [--width 1280 --height 800] [--selector CSS]
//   browse.cjs pdf URL --out page.pdf
//   browse.cjs eval URL "document.title"
//   common: --wait STATE (default networkidle) --timeout MS (default 30000) --ua STRING
//           --cookie NAME=VALUE (repeatable, set for the url's host) --header K:V (repeatable)
//           --console (print console messages to stderr)  --cdp http://127.0.0.1:9222 (attach)
const path = require('path');
// resolve playwright from the repository root (four levels up), the cwd, or a global install
const repoRoot = path.resolve(__dirname, '..', '..', '..', '..');
const { chromium } = require(require.resolve('playwright', { paths: [repoRoot, process.cwd(), __dirname] }));

function parse(argv) {
  const [cmd, url, ...rest] = argv;
  const o = { cmd, url, wait: 'networkidle', timeout: 30000, cookies: [], headers: {}, positional: [] };
  for (let i = 0; i < rest.length; i++) {
    const a = rest[i];
    const next = () => rest[++i];
    switch (a) {
      case '--wait': o.wait = next(); break;
      case '--timeout': o.timeout = Number(next()); break;
      case '--selector': o.selector = next(); break;
      case '--out': o.out = next(); break;
      case '--full': o.full = true; break;
      case '--width': o.width = Number(next()); break;
      case '--height': o.height = Number(next()); break;
      case '--ua': o.ua = next(); break;
      case '--cookie': o.cookies.push(next()); break;
      case '--header': { const h = next(); const k = h.slice(0, h.indexOf(':')); o.headers[k.trim()] = h.slice(k.length + 1).trim(); break; }
      case '--console': o.console = true; break;
      case '--cdp': o.cdp = next(); break;
      default: o.positional.push(a);
    }
  }
  return o;
}

async function main() {
  const o = parse(process.argv.slice(2));
  const cmds = ['text', 'html', 'links', 'screenshot', 'pdf', 'eval'];
  if (!cmds.includes(o.cmd) || !o.url) {
    console.error(`usage: browse.cjs <${cmds.join('|')}> URL [options]  (see header comment)`);
    process.exit(2);
  }
  if ((o.cmd === 'screenshot' || o.cmd === 'pdf') && !o.out) { console.error('--out FILE is required'); process.exit(2); }

  const launch = { headless: true, args: process.getuid && process.getuid() === 0 ? ['--no-sandbox'] : [] };
  if (process.env.CHROME_PATH) launch.executablePath = process.env.CHROME_PATH;
  const browser = o.cdp ? await chromium.connectOverCDP(o.cdp) : await chromium.launch(launch);
  try {
    const ctx = await browser.newContext({
      viewport: { width: o.width || 1280, height: o.height || 800 },
      userAgent: o.ua, extraHTTPHeaders: o.headers,
    });
    if (o.cookies.length) {
      const host = new URL(o.url);
      await ctx.addCookies(o.cookies.map((c) => {
        const eq = c.indexOf('='); return { name: c.slice(0, eq), value: c.slice(eq + 1), url: host.origin };
      }));
    }
    const page = await ctx.newPage();
    if (o.console) page.on('console', (m) => console.error(`[console.${m.type()}] ${m.text()}`));
    page.on('pageerror', (e) => console.error(`[pageerror] ${e.message}`));
    const resp = await page.goto(o.url, { waitUntil: o.wait, timeout: o.timeout });
    if (resp && resp.status() >= 400) console.error(`warning: http ${resp.status()} for ${o.url}`);

    const target = o.selector ? page.locator(o.selector).first() : null;
    switch (o.cmd) {
      case 'text': process.stdout.write((target ? await target.innerText() : await page.locator('body').innerText()) + '\n'); break;
      case 'html': process.stdout.write((target ? await target.evaluate((el) => el.outerHTML) : await page.content()) + '\n'); break;
      case 'links': {
        const links = await page.$$eval('a[href]', (as) => as.map((a) => ({ text: a.innerText.trim().slice(0, 120), href: a.href })));
        for (const l of links) process.stdout.write(`${l.href}\t${l.text}\n`);
        break;
      }
      case 'screenshot':
        if (target) await target.screenshot({ path: o.out }); else await page.screenshot({ path: o.out, fullPage: !!o.full });
        console.error(`wrote ${o.out}`); break;
      case 'pdf': await page.pdf({ path: o.out, format: 'A4', printBackground: true }); console.error(`wrote ${o.out}`); break;
      case 'eval': {
        const expr = o.positional[0]; if (!expr) { console.error('eval needs a JS expression'); process.exit(2); }
        const v = await page.evaluate(expr);
        process.stdout.write((typeof v === 'string' ? v : JSON.stringify(v, null, 2)) + '\n'); break;
      }
    }
    await ctx.close();
  } finally {
    await browser.close();
  }
}

main().catch((e) => { console.error(`browse failed: ${e.message}`); process.exit(1); });
