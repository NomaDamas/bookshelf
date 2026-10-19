# Changelog

Changes intended for users are recorded here. Version metadata lives in
`Sources/BookshelfCore/Resources/AppMetadata.json`. A listed version is not proof
that its Git tag or GitHub Release has been published.

## [Unreleased]

### Changed

- The learning chat is part of Bookside. Every build, including the DMGs and the Homebrew
  cask, bundles it, and the separate `Bookside Pi.app` is gone. Using the chat needs
  Node.js 22.19 or later and the official Claude Code or Codex executable; without them the
  rest of the app works and the panel says what is missing.
- Conversations and the Codex sign-in from `Bookside Pi.app` are stored in the library folder,
  so they appear in Bookside. `scripts/install-local.command` reports a remaining preview app.
- Building from source needs Node.js 22.19 or later, pnpm and Bun.

### Removed

- `scripts/install-pi-preview.command` and the `BOOKSIDE_INCLUDE_AGENT` build variable.

## [0.2.0] - 2026-10-20

### Added

- A left reader panel with page thumbnails, notes, excerpts and book search beside
  the page, and configurable app shortcuts in **Settings > 단축키**.
- In-app learning chat preview, available only from a separate source build
  (`scripts/install-pi-preview.command`). It answers through the official Claude Code
  or Codex executable, searches and cites the selected book, and keeps replies per book.
  DMG and Homebrew builds do not include it.
- `skills/bookside`, an agent skill for using the library through `bookside-cli`
  without MCP. Install it with `npx skills add NomaDamas/bookside --skill bookside`.

### Changed

- Renamed the project to Bookside: `Bookside.app`, `bookside-cli`, bundle ID
  `org.nomadamas.bookside`, `bookside://` links, the `bookside` MCP server name, and
  the `NomaDamas/bookside` repository. Swift module names are unchanged for now.
- An existing `~/Library/Application Support/Bookshelf` library is used in place
  while no `Bookside` folder exists; nothing is moved or copied.
- `bookshelf://book/...` links still open books, and the reader appearance carries
  over from `org.nomadamas.bookshelf`.
- `register-mcp.command` replaces a pre-rename `bookshelf` entry that runs
  `bookshelf-cli`, and the local installer reports a remaining `Bookshelf.app`.
- The Homebrew cask is now `nomadamas/bookside/bookside`. A `bookshelf` cask install
  moves to it with `brew trust --cask nomadamas/bookshelf/bookside`,
  `brew migrate --cask bookshelf`, and `brew upgrade --cask bookside`, which installs
  `Bookside.app`; the library stays where it is. See
  [Install with Homebrew](docs/01-getting-started.md#install-with-homebrew).

### Deprecated

- `BOOKSHELF_*` variables. They apply only when the matching `BOOKSIDE_*` variable
  is unset or empty.

### Fixed

- `bookside-cli --help` lists every accepted OCR language, including `chi_sim` and `chi_tra`.
- Learning chat preview: finishing a request no longer crashes PDFKit from a worker
  thread ([#20](https://github.com/NomaDamas/bookside/issues/20)).

### Known limitations

- Ad-hoc signed developer preview, not notarized by Apple.
- Opening a book whose file was moved or deleted reports an iCloud download message
  ([#18](https://github.com/NomaDamas/bookside/issues/18)).
- `bookside-cli` installed by Homebrew can wait at a Gatekeeper prompt until macOS
  allows the app ([#24](https://github.com/NomaDamas/bookside/issues/24)).

## [0.1.0] - 2026-10-17

### Added

- Native macOS PDF/text reader, currently reading shelf, keyboard navigation,
  per-book notebooks, quotations/comments, bookmarks, and Markdown export.
- Not-started, reading, and finished shelves with dated read-through history,
  reread counts, note badges, and saved sorting by title, activity, notes, or reads.
- Local Apple Vision OCR with new-copy review and preserved reading identity.
- OCR-spacing-aware search and five read-only MCP tools through `bookshelf-cli`.
- English/Korean project guides, native screenshots, and contribution documentation.
- NomaDamas product identity, one metadata source for app/CLI versions, and verified
  DMG packaging with checksums and build metadata for Apple Silicon and Intel.
- macOS CI and tag-triggered draft prereleases. CI artifacts are ad-hoc signed;
  Developer ID signing and notarization require separately configured credentials.
- Public developer-preview downloads for Apple Silicon and Intel, with SHA-256
  checksums and source/build manifests for each DMG.

### Fixed

- Locate app metadata and OCR helpers inside the distributed app across Swift
  resource-bundle layouts, without depending on the build machine's checkout.
- Reject DMGs whose copied app still starts when its packaged resources are absent.
- Create the filesystem image before compressing it, avoiding corrupt DMG block
  offsets observed during direct folder-to-compressed-image creation on arm64 CI.

### Known limitations

- macOS 14 is the deployment target; native UI verification has used macOS 26 on
  Apple Silicon. Intel CI verifies builds and CLI execution, not native UI interaction.
- Temporary-path aliases can bypass OCR-candidate withholding; tracked in
  [#2](https://github.com/NomaDamas/bookshelf/issues/2).
- No EPUB support, embedded model, semantic search, or cross-device note sync.
