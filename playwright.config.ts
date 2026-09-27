import { defineConfig, devices } from '@playwright/test';

// Chromium resolution: Playwright uses the browser matching its own version from
// PLAYWRIGHT_BROWSERS_PATH. When that is missing (a different Playwright version was pinned, or
// downloads are disabled), set CHROME_PATH to any Chrome/Chromium binary — see
// scripts/browser/resolve-chrome.sh.
const executablePath = process.env.CHROME_PATH || undefined;

export default defineConfig({
  testDir: './e2e',
  outputDir: './test-results',
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: [['list'], ['html', { open: 'never', outputFolder: 'playwright-report' }]],
  use: {
    ...devices['Desktop Chrome'],
    headless: true,
    // set BROWSER_IGNORE_HTTPS_ERRORS=1 when a tls-intercepting proxy's CA is not trusted yet
    ignoreHTTPSErrors: !!process.env.BROWSER_IGNORE_HTTPS_ERRORS,
    baseURL: process.env.BASE_URL,
    trace: 'retain-on-failure',
    screenshot: 'only-on-failure',
    launchOptions: {
      executablePath,
      // containers usually run as root without user namespaces
      args: process.getuid && process.getuid() === 0 ? ['--no-sandbox'] : [],
    },
  },
  projects: [{ name: 'chromium', use: { browserName: 'chromium' } }],
});
