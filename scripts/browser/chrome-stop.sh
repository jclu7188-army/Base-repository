#!/usr/bin/env bash
# stop a chrome started by chrome-launch.sh (by pid file, falling back to the devtools port owner).
set -euo pipefail
root=$(cd "$(dirname "$0")/../.." && pwd)
port="${1:-${CHROME_DEBUG_PORT:-9222}}"
pidfile="$root/.browser-out/chrome-${port}.pid"
if [[ -f "$pidfile" ]]; then
  pid=$(cat "$pidfile")
  if kill -0 "$pid" 2>/dev/null; then kill "$pid" && echo "stopped chrome pid ${pid}" >&2; fi
  rm -f "$pidfile"
  exit 0
fi
if command -v fuser >/dev/null && fuser -k "${port}/tcp" >/dev/null 2>&1; then
  echo "stopped process on port ${port}" >&2
else
  echo "no chrome running on port ${port}" >&2
fi
