#!/bin/zsh
# Assembles dist/chrome and dist/firefox from src/ + manifests/.
set -euo pipefail
cd "${0:A:h}"
for browser in chrome firefox; do
  out="dist/$browser"
  rm -rf "$out"
  mkdir -p "$out"
  rsync -a src/ "$out/"
  cp "manifests/$browser.json" "$out/manifest.json"
done
echo "Built extension/dist/{chrome,firefox}"
