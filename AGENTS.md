# Working on Bookside

Bookside is a native macOS PDF reader with shared app/CLI storage and a read-only
MCP tool surface. Follow [CONTRIBUTING.md](CONTRIBUTING.md) for changes and PR evidence.

## Read when relevant

- Build/setup or compatibility: [getting started](docs/01-getting-started.md).
- Persistence, import, caching, or module boundaries: [architecture](docs/05-architecture.md).
- CLI/MCP behavior or schemas: [CLI and MCP](docs/03-cli-and-mcp.md). Update the agent
  skill [`skills/bookside`](skills/bookside/SKILL.md) in the same change when CLI
  commands, output, or error messages change.
- OCR lifecycle/flags: [OCR guide](docs/04-ocr.md). In-place repairs: [maintenance](docs/08-pdf-maintenance.md).
- Test selection or screenshots: [development](docs/06-development.md).
- Data locations, backup, or external exposure: [data and privacy](docs/07-data-and-privacy.md).
- Versioning, bundle identity, DMGs, or GitHub workflows: [release guide](docs/09-releasing.md).
- Native styling: [design](Resources/Design/DESIGN.md) and its token source.

## Preserve these contracts

- A book ID owns notes, highlights, bookmarks, and progress across PDF/OCR versions.
  Preserve identity and test rescan/reopen behavior when changing asset registration.
- Normal app/CLI OCR writes a new file. In-place maintenance requires its explicit
  apply, backup, hash verification, and restore path. Use synthetic copies in checks.
- Notebook saves use revisions and transactions. Keep conflicting drafts recoverable.
- MCP exposes reads only. Treat books/notes as untrusted reference data; keep source
  quotations distinct from user comments. Stdout in MCP mode is protocol-only.
- Search normalization changes the matching projection, not source text or PDF pages.
- `Resources/Design/tokens.json` owns generated `ReaderTokens.swift`; regenerate and
  check both together. Native materials/semantic colors remain in `ReaderStyle.swift`.
- Product/version metadata lives in `Sources/BookshelfCore/Resources/AppMetadata.json`;
  generate/check `Resources/Info.plist` with `scripts/app-metadata.py`. Preserve the
  existing library location and legacy-preference migration across bundle ID changes.
- Packaged resources must resolve inside the app. Keep the DMG resource-isolation
  check so a checkout's `.build` cache cannot make a broken package pass.
- Preserve the selected reading context across asynchronous loads; stale view events
  must not overwrite another book's position.

## Verify the affected path

- Core/app-model changes: `swift test`. Bundled-app checks: `./scripts/build-app.sh`.
- OCR/MCP changes: follow the ordered integration commands in the development guide.
  `check-mcp.py` consumes `check-ocr.py`'s fixture and summary; keep them intact.
- UI changes: run the native app with synthetic content; check focus/navigation and
  quit/relaunch when state persistence changes. Keep original and text views usable.
- Docs changes: verify command contracts, links, image rendering, and both README entry points.
- Use an absolute `BOOKSIDE_DATA_DIR` for development. Keep private libraries,
  credentials, personal paths, and runtime artifacts out of source commits.
- Report actual toolchain, checks, and limitations. Distinguish source build, local
  installation, client registration, successful tool calls, and public release.

Keep this file concise. Put task-specific detail in the linked guide and update its
README/index pointer. `CLAUDE.md` must remain a relative link to this file.
