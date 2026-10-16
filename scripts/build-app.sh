#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode.app/Contents/Developer ]]; then
  export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
configuration="${BOOKSHELF_BUILD_CONFIGURATION:-release}"
mkdir -p .runtime dist
swift build -c "$configuration" --product Bookshelf
swift build -c "$configuration" --product bookshelf-cli
binary_dir="$(swift build -c "$configuration" --show-bin-path)"
bundle="$PWD/dist/Bookshelf.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources/ThirdParty"
cp "$binary_dir/Bookshelf" "$bundle/Contents/MacOS/Bookshelf"
cp "$binary_dir/bookshelf-cli" "$bundle/Contents/MacOS/bookshelf-cli"
cp -R "$binary_dir/Bookshelf_BookshelfCore.bundle" "$bundle/Contents/Resources/"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
swift scripts/generate-icon.swift .runtime/AppIcon.iconset
iconutil -c icns .runtime/AppIcon.iconset -o "$bundle/Contents/Resources/AppIcon.icns"
python3 scripts/copy-licenses.py "$bundle/Contents/Resources/ThirdParty"
codesign --force --deep --sign - "$bundle"
codesign --verify --deep --strict "$bundle"
print "Built: $bundle"
