#!/bin/bash
# Local preview of the GitHub Pages site: scripts/site-preview.sh [port]  (images are copied like in the Pages workflow)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p site/images
cp docs/images/icon.png docs/images/hero.gif site/images/
cp -r docs/images/themes docs/images/ui site/images/
echo "http://localhost:${1:-8080}"
cd site && python3 -m http.server "${1:-8080}"
