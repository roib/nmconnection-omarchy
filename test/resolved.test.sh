#!/usr/bin/env bash
# Check resolved.awk against a captured `resolvectl status`.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
got=$(awk -f "$here/../resolved.awk" < "$here/fixtures/resolvectl-split-dns.txt")
want=$(printf '%s\t%s\t%s\t%s\n' \
  wlan0 192.168.1.1 no home.example \
  wg0 10.64.0.1 yes "" \
  tailscale0 100.100.100.100 no "tail1234.ts.net;ts.net")
if [[ "$got" == "$want" ]]; then
  echo "ok - resolved.awk"
else
  echo "not ok - resolved.awk"
  diff <(echo "$want") <(echo "$got") || true
  exit 1
fi
