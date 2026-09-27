#!/usr/bin/env bash
# print the path of a chrome/chromium binary usable from this repository, checking in order:
# $CHROME_PATH, google chrome / chromium on PATH, playwright's browser cache
# ($PLAYWRIGHT_BROWSERS_PATH, default ~/.cache/ms-playwright), then playwright's own answer.
# exit 1 with a hint on stderr when nothing is found.
set -euo pipefail

try() { [[ -n "${1:-}" && -x "$1" ]] && { printf '%s\n' "$1"; exit 0; } || true; }

try "${CHROME_PATH:-}"
for name in google-chrome google-chrome-stable chromium chromium-browser chrome; do
  p=$(command -v "$name" 2>/dev/null || true); try "$p"
done
for root in "${PLAYWRIGHT_BROWSERS_PATH:-}" "$HOME/.cache/ms-playwright" /opt/pw-browsers; do
  [[ -d "$root" ]] || continue
  # newest revision first
  for d in $(ls -d "$root"/chromium-* 2>/dev/null | sort -t- -k2 -n -r); do
    try "$d/chrome-linux/chrome"; try "$d/chrome-mac/Chromium.app/Contents/MacOS/Chromium"
  done
  try "$root/chromium/chrome"
done
if command -v node >/dev/null; then
  p=$(cd "$(dirname "$0")/../.." && node -e "try{console.log(require('playwright').chromium.executablePath())}catch(e){}" 2>/dev/null || true)
  try "$p"
fi
echo "no chrome/chromium found — install one (npx playwright install chromium) or set CHROME_PATH" >&2
exit 1
