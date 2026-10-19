#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
# BOOKSHELF_* is the pre-rename prefix; it applies only when BOOKSIDE_* is unset.
configuration="${BOOKSIDE_BUILD_CONFIGURATION:-${BOOKSHELF_BUILD_CONFIGURATION:-release}}"
mkdir -p .runtime dist
python3 scripts/generate-reader-tokens.py --check
python3 scripts/app-metadata.py check
# The learning chat bridge ships in every build.
for tool in node pnpm bun; do
  command -v "$tool" >/dev/null || { print -u2 "Building Bookside requires $tool; see docs/01-getting-started.md."; exit 1; }
done
pnpm --dir Sources/BookshelfAgent install --frozen-lockfile --ignore-scripts
pnpm --dir Sources/BookshelfAgent run build
swift build -c "$configuration" --product Bookside
swift build -c "$configuration" --product bookside-cli
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
build_stage="$(mktemp -d "$PWD/dist/.build-stage.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$build_stage"' EXIT
bundle="$build_stage/Bookside.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/ThirdParty"
cp "$binary_dir/Bookside" "$bundle/Contents/MacOS/Bookside"
cp "$binary_dir/bookside-cli" "$bundle/Contents/MacOS/bookside-cli"
cp -R "$binary_dir/Bookside_BookshelfCore.bundle" "$bundle/Contents/Resources/"
mkdir -p "$bundle/Contents/Resources/Agent"
cp dist/agent/bridge.mjs dist/agent/profile.json "$bundle/Contents/Resources/Agent/"
cp dist/agent/renderer.html dist/agent/renderer.js "$bundle/Contents/Resources/Agent/"
python3 scripts/copy-agent-licenses.py "$bundle/Contents/Resources/ThirdParty"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
python3 - "$bundle/Contents/Info.plist" "$configuration" <<'PYINFO'
import plistlib, subprocess, sys
from pathlib import Path
plist = Path(sys.argv[1])
data = plistlib.loads(plist.read_bytes())
data["BooksideBuildConfiguration"] = sys.argv[2]
data["BooksideSourceRevision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
data["BooksideSourceDirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip())
plist.write_bytes(plistlib.dumps(data, sort_keys=False))
PYINFO
swift scripts/generate-icon.swift .runtime/AppIcon.iconset
iconutil -c icns .runtime/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
python3 scripts/copy-licenses.py "$bundle/Contents/Resources/ThirdParty"
python3 scripts/release.py sign-app "$bundle"
python3 - "$bundle" "$PWD/dist/Bookside.app" "$build_stage" <<'PYINSTALL'
import shutil, sys
from pathlib import Path
source, target, stage = map(Path, sys.argv[1:])
if target.exists():
    target.rename(stage / "previous-build.app")
try:
    source.rename(target)
except BaseException:
    if (stage / "previous-build.app").exists() and not target.exists():
        (stage / "previous-build.app").rename(target)
    raise
PYINSTALL
print "Built: $PWD/dist/Bookside.app"
