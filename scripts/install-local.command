#!/bin/zsh
set -euo pipefail
cd "$(dirname "$0")/.."
bundle="$PWD/dist/Bookshelf.app"
target="$HOME/Applications/Bookshelf.app"
if [[ ! -x "$bundle/Contents/MacOS/Bookshelf" ]]; then ./scripts/build-app.sh; fi
mkdir -p "$HOME/Applications"
if [[ -e "$target" ]]; then
  identity="$(plutil -extract CFBundleIdentifier raw "$target/Contents/Info.plist")"
  [[ "$identity" == 'org.bookshelf.reader' ]] || { print -u2 'A different app already exists at the install path.'; exit 1; }
fi
ditto "$bundle" "$target"
codesign --verify --deep --strict "$target"
print "Installed: $target"
