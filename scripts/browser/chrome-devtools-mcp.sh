#!/usr/bin/env bash
# stdio wrapper used by .mcp.json: run the chrome devtools mcp server (google's) against the
# chrome resolved for this repository, headless and with a throwaway profile. extra arguments
# are passed through (e.g. --browserUrl http://127.0.0.1:9222 to attach to chrome-launch.sh).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
bin="$root/node_modules/.bin/chrome-devtools-mcp"
[[ -x "$bin" ]] || { echo "chrome-devtools-mcp not installed: run npm install in $root" >&2; exit 1; }
args=()
if [[ "$*" != *--browserUrl* && "$*" != *--wsEndpoint* ]]; then
  chrome=$(bash "$root/scripts/browser/resolve-chrome.sh")
  args+=(--executablePath "$chrome" --headless --isolated)
  [[ "$(id -u)" == "0" ]] && args+=(--chromeArg=--no-sandbox)
fi
exec "$bin" "${args[@]}" "$@"
