#!/usr/bin/env bash
# create a google doc from a local markdown / text / html / docx file using curl + jq, by
# uploading through the drive api with conversion to the google docs type — or replace the body
# of an existing doc the same way. generic to any account — everything instance-specific comes
# from env vars or flags.

set -euo pipefail

usage() {
  cat <<'USAGE'
usage:
  docs_create.sh --title TITLE --from FILE [--parent FOLDER_ID] [--type MIME]
  docs_create.sh --replace DOC_ID --from FILE [--type MIME]

options:
  --title TITLE      name of the new doc (required unless --replace)
  --from FILE        local source file; "-" reads stdin (then --type is required)
  --parent ID        drive folder to create the doc in (default: my drive root)
  --replace DOC_ID   overwrite the body of an existing doc instead of creating one
                     (keeps id and sharing; comment anchors are lost)
  --type MIME        source content type; inferred from the extension when omitted:
                     .md text/markdown · .txt text/plain · .html text/html · .rtf application/rtf
                     .docx application/vnd.openxmlformats-officedocument.wordprocessingml.document
                     .odt application/vnd.oasis.opendocument.text
  -h, --help         show this help

environment:
  GOOGLE_ACCESS_TOKEN    bearer token with drive or drive.file scope (required)
  GDRIVE_BASE_URL        drive api root override (default https://www.googleapis.com)

output:
  one json object on stdout: {id, name, mimeType, webViewLink}. progress goes to stderr.

exit codes:
  0 success    1 request failed, api error, or bad arguments
USAGE
}

title=""; src=""; parent=""; replace=""; type=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --title) title="${2:?--title needs a value}"; shift 2 ;;
    --from) src="${2:?--from needs a value}"; shift 2 ;;
    --parent) parent="${2:?--parent needs a value}"; shift 2 ;;
    --replace) replace="${2:?--replace needs a value}"; shift 2 ;;
    --type) type="${2:?--type needs a value}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

[[ -z "$src" ]] && { echo "--from is required" >&2; usage >&2; exit 1; }
[[ -z "$replace" && -z "$title" ]] && { echo "--title is required when creating" >&2; exit 1; }
if [[ "$replace" =~ /document/d/([A-Za-z0-9_-]+) ]]; then replace="${BASH_REMATCH[1]}"; fi

for tool in curl jq; do
  command -v "$tool" >/dev/null || { echo "$tool is required" >&2; exit 1; }
done
: "${GOOGLE_ACCESS_TOKEN:?GOOGLE_ACCESS_TOKEN must be set}"
base="${GDRIVE_BASE_URL:-https://www.googleapis.com}"
auth=(-H "Authorization: Bearer ${GOOGLE_ACCESS_TOKEN}")

if [[ -z "$type" ]]; then
  if [[ "$src" == "-" ]]; then echo "--type is required when reading stdin" >&2; exit 1; fi
  case "${src##*.}" in
    md|markdown) type="text/markdown" ;;
    txt)  type="text/plain" ;;
    html|htm) type="text/html" ;;
    rtf)  type="application/rtf" ;;
    docx) type="application/vnd.openxmlformats-officedocument.wordprocessingml.document" ;;
    odt)  type="application/vnd.oasis.opendocument.text" ;;
    *) echo "cannot infer content type from '${src}'; pass --type MIME" >&2; exit 1 ;;
  esac
fi

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
content="${tmpdir}/content"
if [[ "$src" == "-" ]]; then cat > "$content"; else
  [[ -r "$src" ]] || { echo "cannot read ${src}" >&2; exit 1; }
  cp "$src" "$content"
fi
resp="${tmpdir}/resp.json"
fields="id,name,mimeType,webViewLink"

if [[ -n "$replace" ]]; then
  echo "replacing body of ${replace} from ${src} (${type})" >&2
  curl -sS -X PATCH "${base}/upload/drive/v3/files/${replace}?uploadType=media&supportsAllDrives=true&fields=${fields}" \
    "${auth[@]}" -H "Content-Type: ${type}" --data-binary "@${content}" -o "$resp" \
    || { echo "request failed" >&2; exit 1; }
else
  echo "creating '${title}' from ${src} (${type})" >&2
  meta="${tmpdir}/meta.json"
  jq -nc --arg name "$title" --arg parent "$parent" \
    '{name: $name, mimeType: "application/vnd.google-apps.document"}
     + (if $parent != "" then {parents: [$parent]} else {} end)' > "$meta"
  curl -sS -X POST "${base}/upload/drive/v3/files?uploadType=multipart&supportsAllDrives=true&fields=${fields}" \
    "${auth[@]}" \
    -F "metadata=@${meta};type=application/json;charset=UTF-8" \
    -F "file=@${content};type=${type}" -o "$resp" \
    || { echo "request failed" >&2; exit 1; }
fi

if jq -e '.error' "$resp" >/dev/null 2>&1; then
  jq -r '"api error \(.error.code): \(.error.message) (\(.error.errors[0].reason // "?"))"' "$resp" >&2
  exit 1
fi
jq -c '{id, name, mimeType, webViewLink}' "$resp"
