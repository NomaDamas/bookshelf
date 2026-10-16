#!/bin/zsh
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
binary="$(python3 - <<'PYAPP'
import json, os, plistlib
from pathlib import Path
product = json.loads(Path("Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
explicit = os.environ.get("BOOKSHELF_APP_PATH")
locations = [Path(explicit)] if explicit else [Path.home()/"Applications/Bookshelf.app", Path("/Applications/Bookshelf.app")]
found = []
for app in locations:
    try:
        info = plistlib.loads((app/"Contents/Info.plist").read_bytes())
        cli = app/"Contents/MacOS/bookshelf-cli"
        if info.get("CFBundleIdentifier") in [product["bundleIdentifier"], *product["legacyBundleIdentifiers"]] and os.access(cli, os.X_OK):
            found.append(cli.resolve())
    except (OSError, plistlib.InvalidFileException):
        pass
found = list(dict.fromkeys(found))
if not found:
    raise SystemExit("Install Bookshelf.app first, or set BOOKSHELF_APP_PATH to its absolute bundle path.")
if len(found) > 1:
    raise SystemExit("Multiple Bookshelf installations found. Set BOOKSHELF_APP_PATH to the one to register.")
print(found[0])
PYAPP
)"
clients=0
if command -v codex >/dev/null; then
  clients=$((clients + 1))
  if codex mcp get bookshelf >/dev/null 2>&1; then
    print 'Codex already has a bookshelf entry. Keeping it; compare its command with the installed binary.'
  else
    codex mcp add bookshelf -- "$binary" mcp
  fi
fi
if command -v claude >/dev/null; then
  clients=$((clients + 1))
  if claude mcp get bookshelf >/dev/null 2>&1; then
    print 'Claude Code already has a bookshelf entry. Keeping it; compare its command with the installed binary.'
  else
    claude mcp add --scope user --transport stdio bookshelf -- "$binary" mcp
  fi
fi
[[ $clients -gt 0 ]] || { print -u2 'No supported MCP client found on PATH.'; exit 1; }
print 'Registration finished. Restart the CLI sessions and verify a bookshelf tool call.'
