#!/usr/bin/env bash
# Copies the case's fixture into the eval workspace. Run with --scaffold.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
for d in "$here/fixture" ./fixture ../fixture; do
  if [ -d "$d" ]; then cp -R "$d/." .; break; fi
done
[ -f intent/2026-02-02-guest-access/intent.md ] || { echo "fixture not found" >&2; exit 1; }
