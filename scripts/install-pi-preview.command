#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
BOOKSHELF_INCLUDE_AGENT=1 ./scripts/build-app.sh
preview="$PWD/dist/Bookshelf Pi.app"
ditto "$PWD/dist/Bookshelf.app" "$preview"
python3 - "$preview/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]); info = plistlib.loads(p.read_bytes())
info['CFBundleIdentifier'] = 'org.bookshelf.reader.pi'
info['CFBundleName'] = 'Bookshelf Pi'
info['CFBundleDisplayName'] = '서재 Pi'
info.pop('CFBundleURLTypes', None)
p.write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$preview"
target="$HOME/Applications/Bookshelf Pi.app"
if [[ -e "$target" ]]; then
  [[ "$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")" == 'org.bookshelf.reader.pi' ]] || exit 1
fi
ditto "$preview" "$target"
codesign --verify --deep --strict "$target"
print "Installed preview: $target"
