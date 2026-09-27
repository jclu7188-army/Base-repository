#!/usr/bin/env bash
# Copyright 2026 Anthropic PBC
# SPDX-License-Identifier: Apache-2.0
# search google drive with the files.list query language using curl + jq: build the q expression
# from a free-form clause plus --name/--mime helpers (always excluding trash), request the
# nextPageToken field explicitly so pagination works, follow it across allDrives, and emit tsv or
# jsonl. generic to any google drive — everything instance-specific comes from env vars or flags.

set -euo pipefail

usage() {
  cat <<'EOF'
usage:
  drive_search.sh [options] ["q-expression"]       # raw files.list q clause as one quoted argument
  drive_search.sh --name budget --mime application/pdf

  the positional q-expression is combined with --name / --mime using "and"; trashed = false is
  always appended. omit everything to list recently-modified files across all drives.

options:
  --name VALUE     add "name contains 'VALUE'" to the query (single quotes / backslashes escaped)
  --mime TYPE      add "mimeType = 'TYPE'" to the query
  --order-by KEY   sort key passed as orderBy (default "modifiedTime desc")
  --limit N        stop after N files total (default 100; 0 = fetch everything)
  --json           emit one json object per file (jsonl) instead of tsv
  -h, --help       show this help

environment:
  GOOGLE_ACCESS_TOKEN    bearer token; injected by the runtime, so the placeholder default is fine
  GDRIVE_BASE_URL      api root override (default https://www.googleapis.com)

output:
  files on stdout — tsv with header (id, name, mimeType, modifiedTime, size) by default, jsonl
  with --json. size is empty for google-native docs/sheets/slides (they have no stored bytes).
  the assembled q string, file counts, and any truncation warning go to stderr.

exit codes:
  0 success    1 request failed, api error, or bad arguments
EOF
}

err() { printf '%s\n' "$*" >&2; }

command -v curl >/dev/null || { err "curl is required"; exit 1; }
command -v jq >/dev/null || { err "jq is required"; exit 1; }

BASE_URL="${GDRIVE_BASE_URL:-https://www.googleapis.com}"
TOKEN="${GOOGLE_ACCESS_TOKEN:-placeholder}"
LIMIT=100
ORDER_BY="modifiedTime desc"
FORMAT=tsv
RAW_Q=""
NAME_FILTER=""
MIME_FILTER=""

# require_int FLAG VALUE — flags that take a count must get a non-negative integer
require_int() {
  case "$2" in
    ''|*[!0-9]*) err "$1 needs a non-negative integer, got '${2:-nothing}'"; exit 1 ;;
  esac
}

while [ $# -gt 0 ]; do
  case "$1" in
    --name)
      if [ -z "${2:-}" ]; then err "--name needs a value"; exit 1; fi
      NAME_FILTER="$2"; shift 2 ;;
    --mime)
      if [ -z "${2:-}" ]; then err "--mime needs a value"; exit 1; fi
      MIME_FILTER="$2"; shift 2 ;;
    --order-by)
      if [ -z "${2:-}" ]; then err "--order-by needs a value"; exit 1; fi
      ORDER_BY="$2"; shift 2 ;;
    --limit) require_int --limit "${2:-}"; LIMIT="$2"; shift 2 ;;
    --json) FORMAT=json; shift ;;
    -h|--help) usage; exit 0 ;;
    -*) err "unknown option: $1 (see --help)"; exit 1 ;;
    *)
      if [ -n "$RAW_Q" ]; then err "unexpected extra argument: $1"; exit 1; fi
      RAW_Q="$1"; shift ;;
  esac
done

# escape a value for a single-quoted q literal: \ -> \\ then ' -> \'
gdrive_qescape() {
  jq -rn --arg s "$1" --arg q "'" '$s | gsub("\\\\"; "\\\\") | gsub($q; "\\" + $q)'
}

Q=""
q_add() { if [ -n "$Q" ]; then Q="${Q} and $1"; else Q="$1"; fi; }
if [ -n "$RAW_Q" ]; then q_add "$RAW_Q"; fi
if [ -n "$NAME_FILTER" ]; then q_add "name contains '$(gdrive_qescape "$NAME_FILTER")'"; fi
if [ -n "$MIME_FILTER" ]; then q_add "mimeType = '$(gdrive_qescape "$MIME_FILTER")'"; fi
q_add "trashed = false"
err "q: ${Q}"

gdrive_api() {
  curl -sS --max-time 60 \
    -H "Authorization: Bearer ${TOKEN}" \
    "$@"
}

# exit with the api's own message if the response is an error envelope (or not json at all)
gdrive_check_error() {
  if ! jq -e . >/dev/null 2>&1 <<<"$1"; then
    err "non-json response from the api:"
    printf '%s\n' "$1" | head -c 2000 >&2
    exit 1
  fi
  if [ "$(jq -r 'type == "object" and has("error")' <<<"$1")" = "true" ]; then
    jq -r '"google drive error \(.error.code // ""): \(.error.message // "unknown error")"' \
      <<<"$1" >&2
    exit 1
  fi
}

FIELDS="nextPageToken,files(id,name,mimeType,modifiedTime,size)"
URL="${BASE_URL}/drive/v3/files"

if [ "$FORMAT" = "tsv" ]; then printf 'id\tname\tmimeType\tmodifiedTime\tsize\n'; fi

print_page() {
  if [ "$FORMAT" = "tsv" ]; then
    jq -r --argjson take "$2" \
      '[.files[]?][:$take][]
       | [.id, .name, .mimeType, .modifiedTime, .size]
       | map(if . == null then "" elif type == "string" then . else tojson end) | @tsv' <<<"$1"
  else
    jq -c --argjson take "$2" \
      '[.files[]?][:$take][] | {id, name, mimeType, modifiedTime, size}' <<<"$1"
  fi
}

FETCHED=0
PAGE_TOKEN=""

while :; do
  # the api clamps pageSize above 100; ask for min(100, remaining) so we never over-fetch
  WANT=100
  if [ "$LIMIT" -gt 0 ]; then
    REMAINING=$(( LIMIT - FETCHED ))
    if [ "$REMAINING" -le 0 ]; then break; fi
    if [ "$REMAINING" -lt 100 ]; then WANT="$REMAINING"; fi
  fi

  ARGS=(-G
    --data-urlencode "q=${Q}"
    --data-urlencode "fields=${FIELDS}"
    --data-urlencode "corpora=allDrives"
    --data-urlencode "includeItemsFromAllDrives=true"
    --data-urlencode "supportsAllDrives=true"
    --data-urlencode "pageSize=${WANT}")
  # the api rejects orderBy when q has a fullText clause, so omit it in that case
  case "$Q" in *fullText*) ;; *) ARGS+=(--data-urlencode "orderBy=${ORDER_BY}") ;; esac
  if [ -n "$PAGE_TOKEN" ]; then ARGS+=(--data-urlencode "pageToken=${PAGE_TOKEN}"); fi

  PAGE="$(gdrive_api "${URL}" "${ARGS[@]}")"
  gdrive_check_error "$PAGE"

  COUNT="$(jq -r '[.files[]?] | length' <<<"$PAGE")"
  TAKE="$COUNT"
  if [ "$LIMIT" -gt 0 ]; then
    REMAINING=$(( LIMIT - FETCHED ))
    if [ "$COUNT" -gt "$REMAINING" ]; then TAKE="$REMAINING"; fi
  fi
  if [ "$TAKE" -gt 0 ]; then print_page "$PAGE" "$TAKE"; fi
  FETCHED=$(( FETCHED + TAKE ))

  PAGE_TOKEN="$(jq -r '.nextPageToken // empty' <<<"$PAGE")"
  if [ "$LIMIT" -gt 0 ] && [ "$FETCHED" -ge "$LIMIT" ]; then
    if [ -n "$PAGE_TOKEN" ] || [ "$COUNT" -gt "$TAKE" ]; then
      err "output truncated at ${FETCHED} files (raise --limit, or 0 for everything)"
    fi
    break
  fi
  if [ -z "$PAGE_TOKEN" ]; then break; fi
done

err "fetched ${FETCHED} file(s)"
