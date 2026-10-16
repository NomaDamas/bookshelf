#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${BOOKSHELF_BUILD_CONFIGURATION:-release}"
mkdir -p .runtime dist
python3 scripts/generate-reader-tokens.py --check
if [[ "${BOOKSHELF_INCLUDE_AGENT:-0}" == 1 ]]; then
  pnpm --dir Sources/BookshelfAgent install --frozen-lockfile --ignore-scripts
  pnpm --dir Sources/BookshelfAgent run build
fi
swift build -c "$configuration" --product Bookshelf
swift build -c "$configuration" --product bookshelf-cli
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
bundle="$PWD/dist/Bookshelf.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/ThirdParty"
cp "$binary_dir/Bookshelf" "$bundle/Contents/MacOS/Bookshelf"
cp "$binary_dir/bookshelf-cli" "$bundle/Contents/MacOS/bookshelf-cli"
cp -R "$binary_dir/Bookshelf_BookshelfCore.bundle" "$bundle/Contents/Resources/"
if [[ "${BOOKSHELF_INCLUDE_AGENT:-0}" == 1 ]]; then
  mkdir -p "$bundle/Contents/Resources/Agent"
  cp dist/agent/bridge.mjs dist/agent/profile.json "$bundle/Contents/Resources/Agent/"
  python3 scripts/copy-agent-licenses.py "$bundle/Contents/Resources/ThirdParty"
fi
cp Resources/Info.plist "$bundle/Contents/Info.plist"
swift scripts/generate-icon.swift .runtime/AppIcon.iconset
iconutil -c icns .runtime/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
python3 scripts/copy-licenses.py "$bundle/Contents/Resources/ThirdParty"
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
print "Built: $bundle"
