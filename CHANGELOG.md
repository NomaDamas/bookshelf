# Changelog

Changes intended for users are recorded here. Version metadata lives in
`Sources/BookshelfCore/Resources/AppMetadata.json`. A listed version is not proof
that its Git tag or GitHub Release has been published.

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
