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
# The pre-rename preview lives at a different path, so this install never replaces it.
legacy_preview="$HOME/Applications/Bookshelf Pi.app"
if [[ -d "$legacy_preview" ]]; then
  legacy_identity="$(plutil -extract CFBundleIdentifier raw "$legacy_preview/Contents/Info.plist" 2>/dev/null || true)"
  if [[ "$legacy_identity" == org.nomadamas.bookshelf.pi || "$legacy_identity" == org.bookshelf.reader.pi ]]; then
    print "The pre-rename preview is still at $legacy_preview. Quit it, then move it to the Trash."
  fi
fi
