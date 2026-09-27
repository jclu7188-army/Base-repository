# Base repository

A starting point for Claude Code projects. It carries a set of project skills under
`.claude/skills/` (Office documents, PDF, Google Workspace, browser automation) and a working
browser toolchain so Claude can open, test, and inspect web pages from a cloud session.

## Skills

See [`.claude/skills/README.md`](.claude/skills/README.md) for the list, sources, and licences.

## Browser toolchain

| Command | What it does |
|---------|--------------|
| `npm install` | Installs Playwright 1.56.1, `@playwright/test`, `chrome-devtools-mcp`, `@playwright/mcp`. No browser download: the environment ships Chromium under `PLAYWRIGHT_BROWSERS_PATH`. |
| `npm run browser:path` | Prints the Chrome/Chromium binary that will be used (`CHROME_PATH`, `PATH`, or Playwright's cache). |
| `npm run browser:check` | Launches Chromium headless, prints its version, writes `.browser-out/check.png`. |
| `npm run browser:chrome` | Starts headless Chrome with the DevTools protocol on `127.0.0.1:9222` (profile in `.chrome-profile/`). `-- --port N`, `-- --headed`, `-- --url URL`. |
| `npm run browser:stop` | Stops it. |
| `npm run browser:trust-ca` | Imports the sandbox proxy's TLS-interception CA into Chromium's NSS store so `https://` pages load. Run by the hook; `BROWSER_IGNORE_HTTPS_ERRORS=1` is the fallback. |
| `npm run test:e2e` | Runs the `@playwright/test` suite in `e2e/` (`BASE_URL=…` to target a running app). |
| `node .claude/skills/playwright/scripts/browse.cjs text URL` | One-shot page text / html / links / screenshot / pdf / eval in real Chromium. |

`.mcp.json` registers two project MCP servers, both headless against the same Chromium:
`playwright` (Microsoft, `browser_*` tools) and `chrome-devtools` (Google, DevTools tracing,
network, console, a11y snapshots). Claude Code asks to approve project servers on first use in
an interactive session; cloud sessions load them without prompting.

`.claude/hooks/session-start.sh` runs at the start of each Claude Code web session: it runs
`npm install` if needed, installs the Python packages in `requirements-skills.txt`, installs the
system tools the Office and PDF skills need (LibreOffice writer/calc/impress, poppler, pandoc,
qpdf), exports `CHROME_PATH`, and proves Chromium launches. `npm run skills:deps` runs the same
script on demand. Outputs go to `.browser-out/` (git-ignored).

### Claude in Chrome (the browser extension)

The Claude in Chrome extension runs in your own Chrome on your computer and connects to a
*local* Claude Code (`claude --chrome`, then `/chrome` to manage it). It cannot be installed
into a cloud container; there, Claude uses the headless Chromium above instead. Setup and
troubleshooting: `.claude/skills/claude-in-chrome-setup/SKILL.md`.
