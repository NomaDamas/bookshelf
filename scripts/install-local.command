#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/dist/Bookside.app"
target="$HOME/Applications/Bookside.app"
# Reuse dist/ only when it was built from this commit with no local changes; otherwise it holds older source.
if ! python3 - "$bundle" <<'PYCURRENT'
import os, plistlib, subprocess, sys
from pathlib import Path
bundle = Path(sys.argv[1])
try:
    info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip())
except (OSError, plistlib.InvalidFileException, subprocess.CalledProcessError):
    raise SystemExit(1)
built = info.get("BooksideSourceRevision") == head and info.get("BooksideSourceDirty") is False
raise SystemExit(0 if built and not dirty and os.access(bundle / "Contents/MacOS/Bookside", os.X_OK) else 1)
PYCURRENT
then
  ./scripts/build-app.sh
fi
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
# Older apps live at other paths, so installing Bookside never replaces them.
python3 - "$HOME/Applications" <<'PYLEGACY'
import json, plistlib, sys
from pathlib import Path
product = json.loads(Path("Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
legacy = product["legacyBundleIdentifiers"]
# The learning chat used to ship as a separate preview app with a ".pi" bundle ID.
previews = [identity + ".pi" for identity in (product["bundleIdentifier"], *legacy)]
candidates = {"Bookshelf.app": legacy, "Bookside Pi.app": previews, "Bookshelf Pi.app": previews}
for name, identities in candidates.items():
    app = Path(sys.argv[1]) / name
    try:
        identity = plistlib.loads((app / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier")
    except (OSError, plistlib.InvalidFileException):
        continue
    if identity in identities:
        print(f"An older app is still at {app}; Bookside now includes the learning chat.\n"
              "Quit it, confirm Bookside shows your library, then move the old app to the Trash.")
        if name == "Bookshelf.app":
            print("If you use MCP, also run scripts/register-mcp.command.")
PYLEGACY
