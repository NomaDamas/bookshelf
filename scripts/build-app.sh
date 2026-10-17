#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${BOOKSHELF_BUILD_CONFIGURATION:-release}"
mkdir -p .runtime dist
python3 scripts/generate-reader-tokens.py --check
python3 scripts/app-metadata.py check
if [[ "${BOOKSHELF_INCLUDE_AGENT:-0}" == 1 ]]; then
  pnpm --dir Sources/BookshelfAgent install --frozen-lockfile --ignore-scripts
  pnpm --dir Sources/BookshelfAgent run build
fi
swift build -c "$configuration" --product Bookshelf
swift build -c "$configuration" --product bookshelf-cli
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
build_stage="$(mktemp -d "$PWD/dist/.build-stage.XXXXXX")"
trap 'python3 -c "import shutil,sys; shutil.rmtree(sys.argv[1])" "$build_stage"' EXIT
bundle="$build_stage/Bookshelf.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/ThirdParty"
cp "$binary_dir/Bookshelf" "$bundle/Contents/MacOS/Bookshelf"
cp "$binary_dir/bookshelf-cli" "$bundle/Contents/MacOS/bookshelf-cli"
cp -R "$binary_dir/Bookshelf_BookshelfCore.bundle" "$bundle/Contents/Resources/"
if [[ "${BOOKSHELF_INCLUDE_AGENT:-0}" == 1 ]]; then
  mkdir -p "$bundle/Contents/Resources/Agent"
  cp dist/agent/bridge.mjs dist/agent/profile.json "$bundle/Contents/Resources/Agent/"
  cp dist/agent/renderer.html dist/agent/renderer.js "$bundle/Contents/Resources/Agent/"
  python3 scripts/copy-agent-licenses.py "$bundle/Contents/Resources/ThirdParty"
fi
cp Resources/Info.plist "$bundle/Contents/Info.plist"
python3 - "$bundle/Contents/Info.plist" "$configuration" <<'PYINFO'
import plistlib, subprocess, sys
from pathlib import Path
plist = Path(sys.argv[1])
data = plistlib.loads(plist.read_bytes())
data["BookshelfBuildConfiguration"] = sys.argv[2]
data["BookshelfSourceRevision"] = subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip()
data["BookshelfSourceDirty"] = bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip())
plist.write_bytes(plistlib.dumps(data, sort_keys=False))
PYINFO
swift scripts/generate-icon.swift .runtime/AppIcon.iconset
iconutil -c icns .runtime/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
python3 scripts/copy-licenses.py "$bundle/Contents/Resources/ThirdParty"
python3 scripts/release.py sign-app "$bundle"
python3 - "$bundle" "$PWD/dist/Bookshelf.app" "$build_stage" <<'PYINSTALL'
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
print "Built: $PWD/dist/Bookshelf.app"
