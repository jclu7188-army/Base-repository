#!/usr/bin/env node
// launch chromium through playwright from this repository, print its version, and save a
// screenshot to .browser-out/check.png. honours CHROME_PATH when playwright's own browser for
// the installed version is missing. exits 1 with the underlying error otherwise.
const path = require('path');
const fs = require('fs');
const { chromium } = require('playwright');

(async () => {
  const outDir = path.join(__dirname, '..', '..', '.browser-out');
  fs.mkdirSync(outDir, { recursive: true });
  const opts = { headless: true };
  if (process.env.CHROME_PATH) opts.executablePath = process.env.CHROME_PATH;
  const browser = await chromium.launch(opts);
  const page = await browser.newPage();
  await page.setContent('<h1 style="font-family:sans-serif">Chromium launched from this repository</h1>');
  const ua = await page.evaluate(() => navigator.userAgent);
  const shot = path.join(outDir, 'check.png');
  await page.screenshot({ path: shot });
  await browser.close();
  console.log(`chromium ${browser.version()} ok`);
  console.log(`user agent: ${ua}`);
  console.log(`screenshot: ${shot}`);
})().catch((err) => {
  console.error('browser check failed:', err.message);
  console.error('hint: set CHROME_PATH to a chrome binary (scripts/browser/resolve-chrome.sh) or run: npx playwright install chromium');
  process.exit(1);
});
