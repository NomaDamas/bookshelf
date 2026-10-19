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
- Reader shortcuts follow Preview and other macOS apps. The sidebar moves from
  Command-0 to Control-Command-S, the Pi panel from Command-Shift-A to Option-Command-I,
  the sidebar tabs from Command-1/2/3 to Option-Command-1/2/3, previous/next page from
  Option-Command-Left/Right to Option-Up/Down, and saving an excerpt from Command-Shift-H
  to Control-Command-H. Shortcuts you changed yourself are kept.
- Reader commands are grouped into **이동** and **책** menus. Sidebar, Pi panel, tab and
  zoom commands are in **보기**; search is in **편집 > 찾기**; saving and exporting notes
  are in **파일**. Menu titles say whether a panel will be shown or hidden.

- The reader keeps one row of controls above the page: the window toolbar. The sidebar
  button stays first, followed by **서재**. Clicking the book title opens a menu with reading
  status, **책장에서 보기**, Finder, OCR, export and **AI로 이어가기**, which replaces the
  book header, its status menu and the ⋯ menu. View mode, page layout, zoom with a live
  percentage, find and the Pi panel button sit on the right. The window title no longer
  hides behind the add button.
- The sidebar loses its duplicate title, back link, storage note and MCP link; below the page
  only the bookmark button and page navigation remain. The keyboard reference lives in the
  Help menu.
- Settings open only as the app's Settings window (`Command-,`); the separate sheet and the
  toolbar button are gone. The settings icon is the standard gear.
- The app declares Korean as its language, so macOS's own menus and items read 파일, 편집,
  보기, 윈도우, 도움말 and 실행 취소 instead of mixing English and Korean.
- Window tabs are off (the 탭 막대 and 탭 commands are gone), because every window shows the
  same library. The keyboard shortcut window is reached from the 도움말 menu only.
- The 책 menu also has **책장에서 보기**, **Finder에서 보기** and **AI로 이어가기**, so every
  command in the title menu is in the menu bar too.
- Settings use the standard Settings tabs (일반, Pi, 단축키) with the tab name as the window
  title; the extra "서재 설정" header and version line are gone (the version is in About).
- The library toolbar no longer shows the Pi panel button, which only applies to an open book,
  and the sidebar footer with a second add-folder button is gone; adding uses the toolbar `+`
  or the 파일 menu.
- Icons have one meaning each: in-book page jumps use a page-number chip instead of an
  outward arrow, and the undo arrow is no longer used for reading-status changes,
  "펼친 책으로" or "원본 PDF 사용".
- The AI panel is named **Pi** in its header, in **Settings > Pi** (formerly AI 연결) and in
  its notices. The header keeps only the title, the current page and a ⋯ menu for undo, copying or clearing
  the conversation, context usage, the learning instructions and connection settings.
- The question composer has two rows: scope, notes and explanation choices above the field;
  자료 열기, the executor/model menu and send below it. The scope label includes the reader's
  page, and all three menus mark the current choice the same way. A line under the field says
  why sending is off.
- When Node.js is missing or the selected account is not connected, the panel shows a notice
  with **연결하기** that opens the Pi settings. Signing in stays in Settings.
- The conversation reads as a transcript instead of chat bubbles: a `❯` question line, the
  agent's tool steps with their results (`● 책 읽기 (27~29쪽)` / `└ 3쪽 읽음`), the answer
  as plain text and a summary line such as `✻ 12초 동안 작업, 오후 9:41 완료, Claude / Sonnet`.
  While a reply runs, steps show a spinner and the summary line counts the seconds. Steps
  and the finish time are saved with the reply; earlier conversations still open.
- Replies show source page chips; copy, regenerate and save-to-notes sit on the summary line
  with tooltips. Questions are edited in place, removal from a message onward moves to its
  context menu with a confirmation, and three starting prompts fill the question field.
- The app is about half its former size (17.9 MB to 9.4 MB) and the DMG shrinks from 5.2 MB
  to 2.5 MB. Release executables are stripped, the bundled Pi bridge is minified, and the
  DMG uses LZMA compression. Each release also lists a `.dSYMs.zip` with debug symbols for
  crash reports; installing does not need it.

### Added

- Zoom shortcuts (Command-Plus, Command-Minus, Command-0 for actual size and Command-9 to
  fit the page), Option-Command-G to type a page number, and Command-G /
  Command-Shift-G to step through search results.
- **도움말 > Bookside 키보드 단축키** lists every key with the current settings.
- **Settings > 단축키** groups shortcuts by menu, and each one can be cleared or reset on
  its own. Keys used by macOS or fixed menus are refused, and shortcuts are recorded the
  same way under a Korean input source.
- Option-Up/Down page commands step aside while you type, so the keys still move the cursor
  in notes, search and the Pi composer.

### Fixed

- Opening a book no longer disables the Pi panel while the account status is checked.
- Connecting an account in **Settings > Pi** no longer switches the conversation to that engine.
- Pi panel errors can be dismissed.
- Reading a whole book's text no longer holds every page in memory. On a 328-page scanned
  book, the first open peaks at about 360 MB instead of 900 MB, and `bookside-cli search`,
  `inspect`, a Pi reading turn and the OCR comparison stay under about 250 MB.

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
