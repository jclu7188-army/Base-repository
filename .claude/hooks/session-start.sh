#!/bin/bash
# SessionStart hook for Claude Code on the web: make the toolchains the project skills rely on
# ready — node packages (playwright, docx, pptxgenjs, mcp servers), python packages (office/pdf
# libraries, playwright), system tools (LibreOffice writer/calc/impress, poppler, pandoc, qpdf),
# and a usable chrome — and export CHROME_PATH for the session. idempotent; only runs in remote
# sessions unless invoked with --force (npm run skills:deps).
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && [ "${1:-}" != "--force" ]; then
  exit 0
fi

cd "${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# 1. node packages. PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD is set by the environment, so this never
#    re-fetches chromium.
if [ ! -d node_modules/playwright ] || [ ! -d node_modules/docx ] || [ ! -d node_modules/pptxgenjs ] \
   || [ ! -x node_modules/.bin/chrome-devtools-mcp ]; then
  npm install --no-audit --no-fund
fi

# 2. python packages for the office/pdf skills and python playwright (pinned to the same minor
#    as the node package so it finds the same chromium build).
if ! python3 -c "import docx, pptx, openpyxl, pypdf, reportlab, pdfplumber, markitdown, playwright" >/dev/null 2>&1; then
  pip install -q -r requirements-skills.txt || echo "warning: pip install -r requirements-skills.txt failed" >&2
fi

# 3. system tools. the office skills render/validate through LibreOffice (writer, calc and
#    impress modules — libreoffice-core alone cannot convert anything), pandoc, poppler
#    (pdftoppm/pdftotext) and qpdf. apt is only attempted as root.
missing=()
for pkg in libreoffice-writer libreoffice-calc libreoffice-impress poppler-utils pandoc qpdf; do
  dpkg -s "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
done
if [ ${#missing[@]} -gt 0 ]; then
  if [ "$(id -u)" = "0" ] && command -v apt-get >/dev/null; then
    echo "installing: ${missing[*]}"
    export DEBIAN_FRONTEND=noninteractive
    (apt-get update -qq && apt-get install -y -qq --no-install-recommends "${missing[@]}") \
      || echo "warning: apt-get install failed for: ${missing[*]}" >&2
  else
    echo "warning: not root or no apt-get; install manually: ${missing[*]}" >&2
  fi
fi

# 4. a chrome binary: playwright's cached one, or whatever is on the machine. exported so
#    playwright.config.ts, the mcp wrappers, and the skills' scripts all agree.
if chrome=$(bash scripts/browser/resolve-chrome.sh 2>/dev/null); then
  echo "export CHROME_PATH=\"$chrome\"" >> "${CLAUDE_ENV_FILE:-/dev/null}"
  export CHROME_PATH="$chrome"
  echo "chrome: $chrome"
else
  echo "warning: no chrome found; trying npx playwright install chromium" >&2
  PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD= npx playwright install chromium || echo "warning: chromium install failed" >&2
fi

# 5. prove chromium launches (2 seconds); failure is reported but does not block the session.
node scripts/browser/check.cjs || echo "warning: chromium launch check failed" >&2
