#!/usr/bin/env bash
# Fedora's libcurl has no symbol versions, so a CURL_OPENSSL_4 requirement makes its
# loader warn (#303). Usage: curl_symver_check.sh <linux sss binary>
set -uo pipefail
BIN="$1"
ERR=$(xvfb-run -a "$BIN" --version 2>&1 >/dev/null)
if grep -q "no version information available" <<< "$ERR"; then
  echo "::error::loader warning: $ERR"
  exit 1
fi
if readelf -V "$BIN" | grep -A1 'File: libcurl'; then
  echo "::error::binary requires libcurl symbol versions"
  exit 1
fi
echo "ok: no libcurl symbol versions required"
