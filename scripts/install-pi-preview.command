#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
BOOKSIDE_INCLUDE_AGENT=1 ./scripts/build-app.sh
preview="$PWD/dist/Bookside Pi.app"
ditto "$PWD/dist/Bookside.app" "$preview"
python3 - "$preview/Contents/Info.plist" <<'PY'
import plistlib, sys
from pathlib import Path
p = Path(sys.argv[1]); info = plistlib.loads(p.read_bytes())
info['CFBundleIdentifier'] += '.pi'
info['CFBundleName'] += ' Pi'
info['CFBundleDisplayName'] = info.get('CFBundleDisplayName', info['CFBundleName']) + ' Pi'
info.pop('CFBundleURLTypes', None)
p.write_bytes(plistlib.dumps(info))
PY
codesign --force --deep --sign - "$preview"
target="$HOME/Applications/Bookside Pi.app"
if [[ -e "$target" ]]; then
  identity="$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"
  expected="$(plutil -extract CFBundleIdentifier raw "$preview/Contents/Info.plist")"
  [[ "$identity" == "$expected" || "$identity" == 'org.bookshelf.reader.pi' ]] || exit 1
fi
ditto "$preview" "$target"
codesign --verify --deep --strict "$target"
print "Installed preview: $target"
