#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x dist/Bookside.app/Contents/MacOS/Bookside ]]; then
  ./scripts/build-app.sh
fi
open "$PWD/dist/Bookside.app"
