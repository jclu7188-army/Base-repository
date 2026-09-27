#!/usr/bin/env bash
# read a gmail message or thread using curl + jq: fetch format=full, print the key headers, walk
# the mime tree for the text/plain (or text/html) part and decode its base64url body, and
# optionally save attachments. generic to any account — everything instance-specific comes from
# env vars or flags.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  gmail_read.sh MESSAGE_ID [options]
  gmail_read.sh --thread THREAD_ID [options]

options:
  --thread ID          read every message in a thread (oldest first) instead of one message
  --html               prefer the text/html part over text/plain
  --attachments DIR    save attachments into DIR (created if missing)
  --raw-json           print the api json instead of a rendered message
  -h, --help           show this help

environment:
  GOOGLE_ACCESS_TOKEN    bearer token with a gmail read scope (required)
  GMAIL_BASE_URL         api root override (default https://gmail.googleapis.com)

output:
  for each message: a header block (Message-ID, Thread, Date, From, To, Cc, Subject, Labels,
  Attachments) then the decoded body. progress and saved-file names go to stderr.

exit codes:
  0 success    1 request failed, api error, or bad arguments
USAGE
}

message_id=""
thread_id=""
prefer_html=false
att_dir=""
raw_json=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --thread) thread_id="${2:?--thread needs a value}"; shift 2 ;;
    --html) prefer_html=true; shift ;;
    --attachments) att_dir="${2:?--attachments needs a value}"; shift 2 ;;
    --raw-json) raw_json=true; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "unknown option: $1" >&2; usage >&2; exit 1 ;;
    *) if [[ -n "$message_id" ]]; then echo "only one message id allowed" >&2; exit 1; fi
       message_id="$1"; shift ;;
  esac
done

if [[ -z "$message_id" && -z "$thread_id" ]]; then usage >&2; exit 1; fi
if [[ -n "$message_id" && -n "$thread_id" ]]; then echo "give a message id or --thread, not both" >&2; exit 1; fi

for tool in curl jq base64; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
: "${GOOGLE_ACCESS_TOKEN:?GOOGLE_ACCESS_TOKEN must be set}"
base="${GMAIL_BASE_URL:-https://gmail.googleapis.com}/gmail/v1/users/me"

api() {
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

# base64url → bytes. gmail omits padding; re-add it before decoding.
b64url_decode() {
  local s
  s=$(tr -d '\n' | tr '_-' '/+')
  case $(( ${#s} % 4 )) in
    2) s="${s}==" ;;
    3) s="${s}=" ;;
  esac
  printf '%s' "$s" | base64 -d 2>/dev/null || printf '%s' "$s" | base64 -di
}

render_message() {
  local msg="$1"
  local id; id=$(jq -r '.id' <<<"$msg")

  if $raw_json; then
    jq . <<<"$msg"
    return
  fi

  jq -r '
    def hdr($n): ([.payload.headers[]? | select(.name|ascii_downcase==$n) | .value][0] // "");
    "Message-ID: \(.id)",
    "Thread:     \(.threadId)",
    "Date:       \(hdr("date"))",
    "From:       \(hdr("from"))",
    "To:         \(hdr("to"))",
    (if hdr("cc") != "" then "Cc:         \(hdr("cc"))" else empty end),
    "Subject:    \(hdr("subject"))",
    "Labels:     \((.labelIds // []) | join(", "))",
    "Attachments: \([.. | objects | select(.filename? and .filename != "" and .body.attachmentId?) | .filename] | join(", "))",
    ""' <<<"$msg"

  local want="text/plain" other="text/html"
  if $prefer_html; then want="text/html"; other="text/plain"; fi

  local data
  data=$(jq -r --arg w "$want" --arg o "$other" '
    def parts: [.. | objects | select(.mimeType? and .body.data?)];
    (parts | map(select(.mimeType == $w)) | .[0].body.data)
    // (parts | map(select(.mimeType == $o)) | .[0].body.data)
    // .payload.body.data
    // ""' <<<"$msg")

  if [[ -n "$data" ]]; then
    printf '%s' "$data" | b64url_decode
    echo
  else
    echo "(no text body)"
  fi
  echo
  echo "----------------------------------------------------------------"

  if [[ -n "$att_dir" ]]; then
    mkdir -p "$att_dir"
    jq -r '.. | objects | select(.filename? and .filename != "" and .body.attachmentId?)
           | "\(.body.attachmentId)\t\(.filename)"' <<<"$msg" |
    while IFS=$'\t' read -r att_id filename; do
      [[ -z "$att_id" ]] && continue
      safe=$(basename -- "$filename"); safe=${safe//[^A-Za-z0-9._-]/_}
      out="${att_dir}/${id}_${safe}"
      att=$(api "/messages/${id}/attachments/${att_id}") || exit 1
      jq -r '.data' <<<"$att" | b64url_decode > "$out"
      echo "saved attachment: ${out}" >&2
    done
  fi
}

if [[ -n "$thread_id" ]]; then
  thread=$(api "/threads/${thread_id}" --data-urlencode "format=full") || exit 1
  n=$(jq '.messages | length' <<<"$thread")
  echo "thread ${thread_id}: ${n} message(s)" >&2
  for (( i = 0; i < n; i++ )); do
    render_message "$(jq -c ".messages[$i]" <<<"$thread")"
  done
else
  msg=$(api "/messages/${message_id}" --data-urlencode "format=full") || exit 1
  render_message "$msg"
fi
