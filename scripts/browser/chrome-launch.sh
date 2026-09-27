#!/usr/bin/env bash
# start a chrome/chromium instance from this repository with the devtools protocol exposed on
# localhost, using a profile directory inside the repo (.chrome-profile/, git-ignored). prints the
# http endpoint and the websocket url once it answers /json/version. idempotent: if a chrome is
# already listening on the port it reports that instead of starting another.
set -euo pipefail

usage() {
  cat <<'USAGE'
usage: chrome-launch.sh [--port N] [--headed] [--profile DIR] [--url URL] [-- extra chrome flags]

options:
  --port N        devtools port (default $CHROME_DEBUG_PORT or 9222)
  --headed        run with a window (needs a display; default is headless)
  --profile DIR   user-data-dir (default .chrome-profile/ in the repo root)
  --url URL       first page to open (default about:blank)
  --              everything after this is passed to chrome verbatim

prints: DevTools listening on http://127.0.0.1:PORT  and the browser websocket url.
stop it with scripts/browser/chrome-stop.sh.
USAGE
}

root=$(cd "$(dirname "$0")/../.." && pwd)
port="${CHROME_DEBUG_PORT:-9222}"
headed=false
profile="$root/.chrome-profile"
url="about:blank"
extra=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --port) port="${2:?}"; shift 2 ;;
    --headed) headed=true; shift ;;
    --profile) profile="${2:?}"; shift 2 ;;
    --url) url="${2:?}"; shift 2 ;;
    --) shift; extra=("$@"); break ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
  esac
done

if curl -sf "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1; then
  echo "chrome already listening on http://127.0.0.1:${port}" >&2
  curl -s "http://127.0.0.1:${port}/json/version" | sed -n 's/.*"webSocketDebuggerUrl": *"\([^"]*\)".*/\1/p'
  exit 0
fi

chrome=$(bash "$root/scripts/browser/resolve-chrome.sh")
mkdir -p "$profile" "$root/.browser-out"
log="$root/.browser-out/chrome-${port}.log"
pidfile="$root/.browser-out/chrome-${port}.pid"

flags=(
  "--remote-debugging-port=${port}"
  "--remote-debugging-address=127.0.0.1"
  "--user-data-dir=${profile}"
  --no-first-run --no-default-browser-check --disable-background-networking
  --disable-features=Translate,OptimizationHints --password-store=basic
)
$headed || flags+=(--headless=new --disable-gpu --window-size=1280,800)
# containers usually run as root without user namespaces: chrome refuses to start unless told so
if [[ "$(id -u)" == "0" ]]; then flags+=(--no-sandbox); fi
[[ -n "${CHROME_EXTRA_FLAGS:-}" ]] && read -r -a envflags <<<"$CHROME_EXTRA_FLAGS" && flags+=("${envflags[@]}")

nohup "$chrome" "${flags[@]}" "${extra[@]}" "$url" >"$log" 2>&1 &
echo $! >"$pidfile"

for _ in $(seq 1 50); do
  if curl -sf "http://127.0.0.1:${port}/json/version" >/dev/null 2>&1; then
    echo "DevTools listening on http://127.0.0.1:${port} (pid $(cat "$pidfile"), log ${log})" >&2
    curl -s "http://127.0.0.1:${port}/json/version" | sed -n 's/.*"webSocketDebuggerUrl": *"\([^"]*\)".*/\1/p'
    exit 0
  fi
  sleep 0.2
done
echo "chrome did not start; last log lines:" >&2
tail -20 "$log" >&2
exit 1
