#!/bin/bash
# SessionStart hook for Claude Code on the web: make the browser toolchain in this repository
# ready (node packages, python playwright, a usable chrome) and export CHROME_PATH for the
# session. idempotent; only runs in remote sessions.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# 1. node packages (playwright, @playwright/test, chrome-devtools-mcp, @playwright/mcp).
#    PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is set by the environment, so this never re-fetches chromium.
if [ ! -d node_modules/playwright ] || [ ! -x node_modules/.bin/chrome-devtools-mcp ]; then
  npm install --no-audit --no-fund
fi

# 2. python playwright, pinned to the same minor as the node package so it finds the same
#    chromium build under PLAYWRIGHT_BROWSERS_PATH.
if ! python3 -c "import playwright" >/dev/null 2>&1; then
  pip install -q "playwright==1.56.0" || echo "warning: pip install playwright failed" >&2
fi

# 3. a chrome binary: playwright's cached one, or whatever is on the machine. exported so
#    playwright.config.ts, the mcp wrappers, and the skills' scripts all agree.
if chrome=$(bash scripts/browser/resolve-chrome.sh 2>/dev/null); then
  echo "export CHROME_PATH=\"$chrome\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"
  export CHROME_PATH="$chrome"
  echo "chrome: $chrome"
else
  echo "warning: no chrome found; trying npx playwright install chromium" >&2
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD= npx playwright install chromium || echo "warning: chromium install failed" >&2
fi

# 4. prove it launches (2 seconds); failure is reported but does not block the session.
node scripts/browser/check.cjs || echo "warning: chromium launch check failed" >&2
