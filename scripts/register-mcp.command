#!/bin/zsh
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
cd "$(dirname "$0")/.."
binary="$(python3 - <<'PYAPP'
import json, os, plistlib
from pathlib import Path
product = json.loads(Path("Sources/BookshelfCore/Resources/AppMetadata.json").read_text())
explicit = os.environ.get("BOOKSIDE_APP_PATH")
locations = [Path(explicit)] if explicit else [Path.home()/"Applications/Bookside.app", Path("/Applications/Bookside.app")]
found = []
for app in locations:
    try:
        info = plistlib.loads((app/"Contents/Info.plist").read_bytes())
        cli = app/"Contents/MacOS/bookside-cli"
        if info.get("CFBundleIdentifier") in [product["bundleIdentifier"], *product["legacyBundleIdentifiers"]] and os.access(cli, os.X_OK):
            found.append(cli.resolve())
    except (OSError, plistlib.InvalidFileException):
        pass
found = list(dict.fromkeys(found))
if not found:
    raise SystemExit("Install Bookside.app first, or set BOOKSIDE_APP_PATH to its absolute bundle path.")
if len(found) > 1:
    raise SystemExit("Multiple Bookside installations found. Set BOOKSIDE_APP_PATH to the one to register.")
print(found[0])
PYAPP
)"
clients=0
if command -v codex >/dev/null; then
  clients=$((clients + 1))
  if codex mcp get bookside >/dev/null 2>&1; then
    print 'Codex already has a bookside entry. Keeping it; compare its command with the installed binary.'
  else
    codex mcp add bookside -- "$binary" mcp
  fi
fi
if command -v claude >/dev/null; then
  clients=$((clients + 1))
  if claude mcp get bookside >/dev/null 2>&1; then
    print 'Claude Code already has a bookside entry. Keeping it; compare its command with the installed binary.'
  else
    claude mcp add --scope user --transport stdio bookside -- "$binary" mcp
  fi
fi
[[ $clients -gt 0 ]] || { print -u2 'No supported MCP client found on PATH.'; exit 1; }
print 'Registration finished. Restart the CLI sessions and verify a bookside tool call.'
