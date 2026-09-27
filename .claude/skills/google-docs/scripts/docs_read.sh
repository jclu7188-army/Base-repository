#!/usr/bin/env bash
# read a google doc using curl + jq: export it through the drive api in the format you ask for
# (markdown by default) and stream the result to stdout or a file, or fetch the docs api json
# structure (with tabs) when you need indexes for batchUpdate. generic to any account —
# everything instance-specific comes from env vars or flags.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  docs_read.sh DOC_ID [--format md|txt|html|docx|pdf|rtf|odt|epub|json] [--out FILE]

  DOC_ID is the id from https://docs.google.com/document/d/<DOC_ID>/edit (a full url is accepted).

options:
  --format F     md (default) | txt | html | docx | pdf | rtf | odt | epub | json
                 json = docs api documents.get with includeTabsContent=true (structure + indexes)
  --out FILE     write to FILE instead of stdout (required for docx/pdf/odt/epub unless piping)
  -h, --help     show this help

environment:
  GOOGLE_ACCESS_TOKEN    bearer token with documents.readonly (json) or drive.readonly (exports)
  GDRIVE_BASE_URL        drive api root override (default https://www.googleapis.com)
  GDOCS_BASE_URL         docs api root override (default https://docs.googleapis.com)

exit codes:
  0 success    1 request failed, api error, or bad arguments
USAGE
}

doc_id=""
format="md"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --format) format="${2:?--format needs a value}"; shift 2 ;;
    --out) out="${2:?--out needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) if [[ -n "$doc_id" ]]; then echo "only one doc id allowed" >&2; exit 1; fi
       doc_id="$1"; shift ;;
  esac
done
[[ -z "$doc_id" ]] && { usage >&2; exit 1; }

# accept a full docs url
if [[ "$doc_id" =~ /document/d/([A-Za-z0-9_-]+) ]]; then doc_id="${BASH_REMATCH[1]}"; fi

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
: "${GOOGLE_ACCESS_TOKEN:?GOOGLE_ACCESS_TOKEN must be set}"
drive="${GDRIVE_BASE_URL:-https://www.googleapis.com}/drive/v3"
docs="${GDOCS_BASE_URL:-https://docs.googleapis.com}/v1"
auth=(-H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}")

case "$format" in
  md|markdown) mime="text/markdown" ;;
  txt|text)    mime="text/plain" ;;
  html)        mime="text/html" ;;
  docx)        mime="application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
  pdf)         mime="application/pdf" ;;
  rtf)         mime="application/rtf" ;;
  odt)         mime="application/vnd.oasis.opendocument.text" ;;
  epub)        mime="application/epub+zip" ;;
  json)        mime="" ;;
  *) echo "unknown format: ${format}" >&2; exit 1 ;;
esac

fail_if_error() {
  # $1 = path of a response body; exits 1 with the api's message if it is an error envelope
  if jq -e '.error' "$1" >/dev/null 2>&1; then
    jq -r '"api error \(.error.code): \(.error.message) (\(.error.errors[0].reason // .error.status // "?"))"' "$1" >&2
    exit 1
  fi
}

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT

if [[ "$format" == "json" ]]; then
  curl -sS -G "${docs}/documents/${doc_id}" "${auth[@]}" \
    --data-urlencode "includeTabsContent=true" -o "$tmp" || { echo "request failed" >&2; exit 1; }
  fail_if_error "$tmp"
  echo "document: $(jq -r '.title' "$tmp") (revision $(jq -r '.revisionId' "$tmp"))" >&2
else
  # metadata first: confirm it is a google doc and report the name
  curl -sS -G "${drive}/files/${doc_id}" "${auth[@]}" \
    --data-urlencode "supportsAllDrives=true" \
    --data-urlencode "fields=id,name,mimeType" -o "$tmp" || { echo "request failed" >&2; exit 1; }
  fail_if_error "$tmp"
  name=$(jq -r '.name' "$tmp"); kind=$(jq -r '.mimeType' "$tmp")
  if [[ "$kind" != "application/vnd.google-apps.document" ]]; then
    echo "not a google doc: ${name} is ${kind} — use the google-drive-api skill's drive_read.sh" >&2
    exit 1
  fi
  echo "document: ${name} → ${mime}" >&2
  http=$(curl -sS -G "${drive}/files/${doc_id}/export" "${auth[@]}" \
    --data-urlencode "mimeType=${mime}" -o "$tmp" -w '%{http_code}') || { echo "request failed" >&2; exit 1; }
  if [[ "$http" != 2* ]]; then fail_if_error "$tmp"; echo "export failed: http ${http}" >&2; exit 1; fi
fi

if [[ -n "$out" ]]; then
  cp "$tmp" "$out"
  echo "wrote ${out} ($(wc -c < "$out") bytes)" >&2
else
  cat "$tmp"
fi
