#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ ! -x dist/Bookshelf.app/Contents/MacOS/Bookshelf ]]; then
  ./scripts/build-app.sh
fi
open "$PWD/dist/Bookshelf.app"
