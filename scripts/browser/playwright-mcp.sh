#!/usr/bin/env bash
# stdio wrapper used by .mcp.json: run microsoft's playwright mcp server against the chrome
# resolved for this repository, headless, isolated, saving outputs under .browser-out/. extra
# arguments are passed through (e.g. --cdp-endpoint http://127.0.0.1:9222 to attach to
# chrome-launch.sh, or --caps vision,pdf).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
bin="$root/node_modules/.bin/playwright-mcp"
[[ -x "$bin" ]] || { echo "@playwright/mcp not installed: run npm install in $root" >&2; exit 1; }
mkdir -p "$root/.browser-out"
args=(--output-dir "$root/.browser-out")
if [[ "$*" != *--cdp-endpoint* ]]; then
  chrome=$(bash "$root/scripts/browser/resolve-chrome.sh")
  args+=(--executable-path "$chrome" --headless --isolated)
  [[ "$(id -u)" == "0" ]] && args+=(--no-sandbox)
fi
exec "$bin" "${args[@]}" "$@"
