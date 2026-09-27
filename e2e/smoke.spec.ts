import { test, expect } from '@playwright/test';

// Proves the browser toolchain works from this repository: Chromium launches, renders a page,
// runs JavaScript, and the console is observable.
test('chromium launches and renders a page', async ({ page, browser }) => {
  const logs: string[] = [];
  page.on('console', (msg) => logs.push(msg.text()));

  await page.setContent(`
    <main><h1>Smoke</h1><button id="go">Go</button><p id="out"></p></main>
    <script>
      document.getElementById('go').addEventListener('click', () => {
        document.getElementById('out').textContent = 'clicked';
        console.log('[smoke] clicked');
      });
    </script>`);

  await expect(page.getByRole('heading', { name: 'Smoke' })).toBeVisible();
  await page.getByRole('button', { name: 'Go' }).click();
  await expect(page.locator('#out')).toHaveText('clicked');
  expect(logs).toContain('[smoke] clicked');
  expect(browser.version()).toMatch(/^\d+\./);
});
