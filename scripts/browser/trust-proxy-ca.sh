#!/usr/bin/env bash
# make chromium trust the environment's tls-intercepting proxy: import every certificate from the
# proxy ca bundle that is missing from the system bundle into the user's nss store
# (~/.pki/nssdb), which chrome/chromium on linux reads for extra trust anchors. curl, node and
# python already trust the bundle through SSL_CERT_FILE / NODE_EXTRA_CA_CERTS; chromium does not.
# idempotent; exits 0 with a note when there is no proxy bundle.
set -euo pipefail

bundle="${PROXY_CA_BUNDLE:-${NODE_EXTRA_CA_CERTS:-${SSL_CERT_FILE:-/root/.ccr/ca-bundle.crt}}}"
db="${NSS_DB:-$HOME/.pki/nssdb}"

[[ -r "$bundle" ]] || { echo "no proxy ca bundle at ${bundle}; nothing to do"; exit 0; }
if ! command -v certutil >/dev/null; then
  if [[ "$(id -u)" == "0" ]] && command -v apt-get >/dev/null; then
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends libnss3-tools >/dev/null
  else
    echo "certutil (libnss3-tools) is required" >&2; exit 1
  fi
fi
command -v openssl >/dev/null || { echo "openssl is required" >&2; exit 1; }

mkdir -p "$db"
[[ -f "$db/cert9.db" ]] || certutil -d "sql:$db" -N --empty-password

tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
awk -v d="$tmp" 'BEGIN{n=0} /BEGIN CERTIFICATE/{n++} {print > (d "/c" n ".pem")}' "$bundle"
# reference set of public roots: the distro's mozilla certificates (individual files). the merged
# system bundle is no good as a reference because the proxy setup appends its own ca to it.
ref_fps="$tmp/ref.txt"; : > "$ref_fps"
if [[ -d /usr/share/ca-certificates/mozilla ]]; then
  for f in /usr/share/ca-certificates/mozilla/*.crt; do openssl x509 -in "$f" -noout -fingerprint -sha256 2>/dev/null; done | sort > "$ref_fps"
fi
existing=$(certutil -d "sql:$db" -L 2>/dev/null | tail -n +4 | sed 's/[[:space:]]*$//; s/ \+[A-Za-z,]*$//' || true)

added=0; skipped=0
for f in "$tmp"/c*.pem; do
  fp=$(openssl x509 -in "$f" -noout -fingerprint -sha256 2>/dev/null) || continue
  grep -qxF "$fp" "$ref_fps" && continue                       # public root, chromium has it
  # with no reference set, only self-signed certificates (roots) are worth importing
  if [[ ! -s "$ref_fps" ]]; then
    [[ "$(openssl x509 -in "$f" -noout -subject)" == "$(openssl x509 -in "$f" -noout -issuer | sed 's/^issuer=/subject=/')" ]] || continue
  fi
  name=$(openssl x509 -in "$f" -noout -subject | sed 's/^subject=//; s/.*CN *= *//; s/,.*//')
  if grep -qxF "$name" <<<"$existing"; then skipped=$((skipped+1)); continue; fi
  certutil -d "sql:$db" -A -t "C,," -n "$name" -i "$f" && { echo "trusted: $name"; added=$((added+1)); }
done
echo "nss store ${db}: ${added} added, ${skipped} already present"
