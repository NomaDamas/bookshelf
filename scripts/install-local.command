#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/dist/Bookside.app"
target="$HOME/Applications/Bookside.app"
if [[ ! -x "$bundle/Contents/MacOS/Bookside" ]]; then ./scripts/build-app.sh; fi
mkdir -p "$HOME/Applications"
if [[ -e "$target" ]]; then
  python3 - "$target/Contents/Info.plist" <<'PYIDENTITY'
import json, plistlib, sys
from pathlib import Path
product = json.loads(Path("Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
installed = plistlib.loads(Path(sys.argv[1]).read_bytes())
if installed.get("CFBundleIdentifier") not in [product["bundleIdentifier"], *product["legacyBundleIdentifiers"]]:
    raise SystemExit("A different app already exists at the install path.")
PYIDENTITY
fi
install_stage="$(mktemp -d "$HOME/Applications/.bookside-install.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$install_stage"' EXIT
ditto "$bundle" "$install_stage/Bookside.app"
codesign --verify --deep --strict "$install_stage/Bookside.app"
python3 - "$install_stage" "$target" <<'PYREPLACE'
from pathlib import Path
import sys
stage, target = map(Path, sys.argv[1:])
previous = stage / "previous.app"
if target.exists():
    target.rename(previous)
try:
    (stage / "Bookside.app").rename(target)
except BaseException:
    if previous.exists():
        previous.rename(target)
    raise
PYREPLACE
print "Installed: $target"
# The pre-rename app lives at a different path, so installing Bookside never replaces it.
python3 - "$HOME/Applications/Bookshelf.app" <<'PYLEGACY'
import json, plistlib, sys
from pathlib import Path
product = json.loads(Path("Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
legacy = Path(sys.argv[1])
try:
    identity = plistlib.loads((legacy / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier")
except (OSError, plistlib.InvalidFileException):
    sys.exit()
if identity in product["legacyBundleIdentifiers"]:
    print(f"The pre-rename app is still at {legacy}. Quit it, confirm Bookside shows your library,\n"
          "then move the old app to the Trash and run scripts/register-mcp.command.")
PYLEGACY
