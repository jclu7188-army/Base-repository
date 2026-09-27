#!/usr/bin/env bash
# Copyright 2026 Anthropic PBC
# SPDX-License-Identifier: Apache-2.0
# read one google drive file's content with curl + jq: fetch metadata, branch on mimeType — export
# google workspace files (docs/sheets/slides/drawings) to a concrete format, download everything
# else as raw bytes via alt=media — and stream the result to stdout or a file. generic to any
# google drive — everything instance-specific comes from env vars or flags.

set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  drive_read.sh [options] FILE_ID

  FILE_ID is the opaque id from a drive.google.com / docs.google.com url.

options:
  --format MIME    export target mime type for google workspace files (overrides the default).
                   defaults: document → text/plain, spreadsheet → text/csv (first sheet only),
                   presentation → text/plain, drawing → image/png.
  --out FILE       write content to FILE instead of stdout
  -h, --help       show this help

environment:
  GOOGLE_ACCESS_TOKEN  bearer token; injected by the runtime, so the placeholder default is fine
  GDRIVE_BASE_URL      api root override (default https://www.googleapis.com)

output:
  file content on stdout (or the --out file). content may be binary. file name, mime type, size,
  and the action taken (export target or raw download) go to stderr.

exit codes:
  0 success    1 request failed, api error, no export for the type, or bad arguments
EOF
}

err() { printf '%s\n' "$*" >&2; }

command -v curl >/dev/null || { err "curl is required"; exit 1; }
command -v jq >/dev/null || { err "jq is required"; exit 1; }

BASE_URL="${GDRIVE_BASE_URL:-https://www.googleapis.com}"
TOKEN="${GOOGLE_ACCESS_TOKEN:-placeholder}"
FORMAT=""
OUT=""
FILE_ID=""

while [ $# -gt 0 ]; do
  case "$1" in
    --format)
      if [ -z "${2:-}" ]; then err "--format needs a mime type"; exit 1; fi
      FORMAT="$2"; shift 2 ;;
    --out)
      if [ -z "${2:-}" ]; then err "--out needs a file path"; exit 1; fi
      OUT="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    -*) err "unknown option: $1 (see --help)"; exit 1 ;;
    *)
      if [ -n "$FILE_ID" ]; then err "unexpected extra argument: $1"; exit 1; fi
      FILE_ID="$1"; shift ;;
  esac
done

if [ -z "$FILE_ID" ]; then err "no file id given (see --help)"; exit 1; fi

gdrive_api() {
  curl -sS --max-time 120 \
    -H "Authorization: Bearer ${TOKEN}" \
    "$@"
}

gdrive_urlenc() { jq -rn --arg s "$1" '$s | @uri'; }

# exit with the api's own message if the response is an error envelope (or not json at all)
gdrive_check_error() {
  if ! jq -e . >/dev/null 2>&1 <<<"$1"; then
    err "non-json response from the api:"
    printf '%s\n' "$1" | head -c 2000 >&2
    exit 1
  fi
  if [ "$(jq -r 'type == "object" and has("error")' <<<"$1")" = "true" ]; then
    jq -r '"drive error \(.error.code // ""): \(.error.message // "unknown error")"
      + ((.error.errors[0].reason // "") as $r | if $r != "" then " (\($r))" else "" end)' \
      <<<"$1" >&2
    exit 1
  fi
}

ENC_ID="$(gdrive_urlenc "$FILE_ID")"
META_URL="${BASE_URL}/drive/v3/files/${ENC_ID}"

# step 1: metadata — name, mimeType, size
META="$(gdrive_api -G "${META_URL}" \
  --data-urlencode "supportsAllDrives=true" \
  --data-urlencode "fields=id,name,mimeType,size")"
gdrive_check_error "$META"

NAME="$(jq -r '.name // ""' <<<"$META")"
MIME="$(jq -r '.mimeType // ""' <<<"$META")"
SIZE="$(jq -r '.size // ""' <<<"$META")"

err "name:     ${NAME}"
err "mimeType: ${MIME}"
if [ -n "$SIZE" ]; then err "size:     ${SIZE} bytes"; fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# step 2: branch on mimeType — workspace types export, everything else downloads raw bytes
GAPPS="application/vnd.google-apps."
case "$MIME" in
  "${GAPPS}"*)
    SUB="${MIME#"$GAPPS"}"
    TARGET="$FORMAT"
    if [ -z "$TARGET" ]; then
      case "$SUB" in
        document)     TARGET="text/plain" ;;
        spreadsheet)  TARGET="text/csv" ;;
        presentation) TARGET="text/plain" ;;
        drawing)      TARGET="image/png" ;;
        *)
          err "no export available for ${MIME} (folders, forms, shortcuts, sites cannot be"
          err "exported; for other workspace types pass --format with an explicit mime type)"
          exit 1 ;;
      esac
    fi
    err "action:   export → ${TARGET}"
    HTTP="$(gdrive_api -G "${META_URL}/export" \
      --data-urlencode "mimeType=${TARGET}" \
      -o "$TMP" -w '%{http_code}')"
    ;;
  *)
    if [ -z "$OUT" ] && [ -n "$SIZE" ] && [ "$SIZE" -gt 10485760 ]; then
      MIB=$(( SIZE / 1048576 ))
      err "file is ${MIB} MiB; pass --out FILE to download it"
      exit 1
    fi
    err "action:   download (alt=media)"
    HTTP="$(gdrive_api "${META_URL}?alt=media&supportsAllDrives=true" \
      -o "$TMP" -w '%{http_code}')"
    ;;
esac

if [ "$HTTP" != "200" ]; then
  # body is a json error envelope — surface message + reason (e.g. exportSizeLimitExceeded for
  # exports over the 10 MB cap, fileNotDownloadable for alt=media on a workspace file)
  BODY="$(head -c 2000 "$TMP")"
  if jq -e . >/dev/null 2>&1 <<<"$BODY"; then
    jq -r '"drive error \(.error.code // ""): \(.error.message // "unknown error")"
      + ((.error.errors[0].reason // "") as $r | if $r != "" then " (\($r))" else "" end)' \
      <<<"$BODY" >&2
  else
    err "http ${HTTP} — non-json response from the api:"
    printf '%s\n' "$BODY" >&2
  fi
  exit 1
fi

if [ -n "$OUT" ]; then
  mv -f "$TMP" "$OUT"
  err "wrote ${OUT}"
else
  cat "$TMP"
fi
