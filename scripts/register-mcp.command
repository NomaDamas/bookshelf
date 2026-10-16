#!/bin/zsh
set -euo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
binary="$HOME/Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli"
[[ -x "$binary" ]] || { print -u2 'Install Bookshelf.app first with scripts/install-local.command.'; exit 1; }
if command -v codex >/dev/null; then
  if codex mcp get bookshelf >/dev/null 2>&1; then
    print 'Codex already has a bookshelf entry. Keeping it; compare its command with the installed binary.'
  else
    codex mcp add bookshelf -- "$binary" mcp
  fi
fi
if command -v claude >/dev/null; then
  if claude mcp get bookshelf >/dev/null 2>&1; then
    print 'Claude Code already has a bookshelf entry. Keeping it; compare its command with the installed binary.'
  else
    claude mcp add --scope user --transport stdio bookshelf -- "$binary" mcp
  fi
fi
print 'Registration finished. Restart the CLI sessions to load the server.'
