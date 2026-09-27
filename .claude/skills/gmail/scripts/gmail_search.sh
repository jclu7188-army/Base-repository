#!/usr/bin/env bash
# search gmail with the users.messages.list query syntax using curl + jq: run the search, follow
# nextPageToken up to --limit hits, fetch metadata headers for each hit, and emit tsv or jsonl.
# generic to any account — everything instance-specific comes from env vars or flags.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  gmail_search.sh [options] "query"        # gmail search-box syntax, one quoted argument
  gmail_search.sh "from:alice@example.com newer_than:7d" --limit 20
  gmail_search.sh "has:attachment filename:pdf" --json

options:
  --limit N        stop after N messages total (default 25; 0 = fetch everything)
  --label ID       restrict to a label id (repeatable; system ids like INBOX, UNREAD, or Label_123)
  --spam-trash     include SPAM and TRASH
  --json           emit one json object per message (jsonl) instead of tsv
  -h, --help       show this help

environment:
  GOOGLE_ACCESS_TOKEN    bearer token with a gmail read scope (required)
  GMAIL_BASE_URL         api root override (default https://gmail.googleapis.com)

output:
  messages on stdout, newest first — tsv with header (id, threadId, date, from, subject, snippet)
  by default, jsonl with --json. counts and truncation warnings go to stderr.

exit codes:
  0 success    1 request failed, api error, or bad arguments
USAGE
}

query=""
limit=25
labels=()
spam_trash=false
json=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --limit) limit="${2:?--limit needs a value}"; shift 2 ;;
    --label) labels+=("${2:?--label needs a value}"); shift 2 ;;
    --spam-trash) spam_trash=true; shift ;;
    --json) json=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) if [[ -n "$query" ]]; then echo "only one query argument allowed" >&2; exit 1; fi
       query="$1"; shift ;;
  esac
done

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
: "${GOOGLE_ACCESS_TOKEN:?GOOGLE_ACCESS_TOKEN must be set}"
base="${GMAIL_BASE_URL:-https://gmail.googleapis.com}/gmail/v1/users/me"

api() {
  # api PATH [curl args...] — GET with auth header; prints body; exits 1 on an api error envelope
  local path="$1"; shift
  local body
  body=$(curl -sS -G "${base}${path}" -H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}" "$@") || {
    echo "request failed: ${path}" >&2; exit 1; }
  if jq -e '.error' >/dev/null 2>&1 <<<"$body"; then
    jq -r '"api error \(.error.code): \(.error.message) (\(.error.errors[0].reason // "?"))"' <<<"$body" >&2
    exit 1
  fi
  printf '%s' "$body"
}

label_args=()
for l in "${labels[@]:-}"; do
  [[ -n "$l" ]] && label_args+=(--data-urlencode "labelIds=${l}")
done

echo "q: ${query:-<none>}" >&2

page_token=""
count=0
$json || printf 'id\tthreadId\tdate\tfrom\tsubject\tsnippet\n'

while :; do
  page_size=100
  if (( limit > 0 )); then
    remaining=$(( limit - count ))
    (( remaining <= 0 )) && break
    (( remaining < page_size )) && page_size=$remaining
  fi

  args=(--data-urlencode "maxResults=${page_size}")
  [[ -n "$query" ]] && args+=(--data-urlencode "q=${query}")
  [[ -n "$page_token" ]] && args+=(--data-urlencode "pageToken=${page_token}")
  $spam_trash && args+=(--data-urlencode "includeSpamTrash=true")
  [[ ${#label_args[@]} -gt 0 ]] && args+=("${label_args[@]}")

  page=$(api "/messages" "${args[@]}")
  ids=$(jq -r '.messages[]?.id' <<<"$page")
  [[ -z "$ids" ]] && break

  while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    msg=$(api "/messages/${id}" \
      --data-urlencode "format=metadata" \
      --data-urlencode "metadataHeaders=From" \
      --data-urlencode "metadataHeaders=Subject" \
      --data-urlencode "metadataHeaders=Date")
    if $json; then
      jq -c '{id, threadId, labelIds, internalDate, snippet,
              date: (.payload.headers[]? | select(.name|ascii_downcase=="date") | .value),
              from: (.payload.headers[]? | select(.name|ascii_downcase=="from") | .value),
              subject: (.payload.headers[]? | select(.name|ascii_downcase=="subject") | .value)}' <<<"$msg"
    else
      jq -r '
        def hdr($n): ([.payload.headers[]? | select(.name|ascii_downcase==$n) | .value][0] // "");
        def clean: gsub("[\t\n\r]"; " ");
        [.id, .threadId, hdr("date"), hdr("from"), hdr("subject"), (.snippet // "")]
        | map(clean) | @tsv' <<<"$msg"
    fi
    count=$(( count + 1 ))
    (( limit > 0 && count >= limit )) && break
  done <<<"$ids"

  (( limit > 0 && count >= limit )) && break
  page_token=$(jq -r '.nextPageToken // empty' <<<"$page")
  [[ -z "$page_token" ]] && break
done

echo "messages: ${count}" >&2
if (( limit > 0 && count >= limit )) && [[ -n "$page_token" ]]; then
  echo "warning: stopped at --limit ${limit}; more results exist" >&2
fi
