# Bookshelf / 서재

A native macOS PDF reader with per-book notebooks, local Apple Vision OCR, and read-only access from Codex and Claude Code through MCP.

서재는 PDF를 읽고, 문장을 발췌하고, 책마다 내 생각을 남기는 Mac 앱입니다.
원본 파일은 제자리에 두고, 메모와 읽던 위치를 로컬 SQLite에 저장합니다.

## What works

- Native SwiftUI/AppKit reader with PDFKit rendering, selection, zoom, page navigation, and text view.
- Keyboard page turning in both original PDF and text view, with single-page and continuous PDF layouts.
- Per-book notebooks with autosave, save-failure feedback, and revision conflict protection.
- Quoted passages with page coordinates, persistent highlights, comments, and Markdown export.
- Bookmarks and reading position restored after quitting and relaunching.
- Local OCR through OCRmyPDF + AppleOCR using the public Vision `accurate` mode.
- OCR output is a new `_ocr.pdf` file. Existing files are never overwritten.
- The original and its OCR output retain one book ID, notebook, bookmarks, and progress.
- A native CLI and five read-only MCP tools: `list_books`, `read_page`, `search_book`, `get_notes`, and `get_reading_context`.

AI answers are generated in your MCP client. This version does not run a model inside the reader.
The reader's “AI로 이어가기” button copies the current book ID and PDF page as a prompt for your client.

## Reading controls

Click the original PDF or text reading area to use these keys. Switching to text view focuses
the reading area automatically. Notes, search fields, PDF form fields, and the page-number
field keep their normal editing keys.

| Key | Action |
| --- | --- |
| Left / Right | Previous / next PDF page |
| Space / Shift-Space | Next / previous PDF page |
| Page Down / Page Up (Fn-Down / Fn-Up) | Next / previous PDF page |
| Home / End (Fn-Left / Fn-Right) | First / last PDF page |
| Up / Down | Scroll within the reading area |
| Command-Shift-R | Return keyboard focus to the current reading view |
| Command-Option-Left / Right | Previous / next page from anywhere in the reader |

Enter a page number and press Return to jump and keep reading with the keyboard.
The first and last pages are clamped. PDF layout selection is saved between launches.
The keyboard button beside the page controls opens an in-app reference.

## Build and run

The deployment target is macOS 14. Current build and UI verification were performed on macOS 26 with Xcode 27 / Swift 6.4. Earlier supported systems have not been tested end to end.

```sh
./scripts/build-app.sh
./scripts/open-app.command
```

The build script uses `/Applications/Xcode.app` when available, without changing the system Xcode selection.
Set `DEVELOPER_DIR` explicitly to use another compatible toolchain.
The MCP SDK is pinned to `0.12.1`, including its upstream Swift concurrency fix.

Install in your personal Applications folder:

```sh
./scripts/install-local.command
```

This creates `~/Applications/Bookshelf.app` with the app and `bookshelf-cli` inside it.
The local build is ad-hoc signed. It has not been notarized or published as a public release.

## OCR setup

OCR is optional; reading and notes work without it. The app checks for `ocrmypdf` on PATH,
in `~/.local/bin`, and in standard Homebrew locations. An explicit path can be supplied
with `BOOKSHELF_OCRMYPDF`.

Use the existing OCR skill's installation route:

```sh
uv tool install ocrmypdf --with "ocrmypdf-appleocr @ git+https://github.com/mkyt/OCRmyPDF-AppleOCR.git"
brew install ghostscript
```

The integration was verified with OCRmyPDF 17.10.0 and AppleOCR 0.4.0.
Python, OCRmyPDF, AppleOCR, and Ghostscript are external installations; they are not bundled in this app.

The worker explicitly uses `--ocr-engine appleocr`, `--appleocr-recognition-mode accurate`,
`--pdf-renderer sandwich`, `--output-type pdf`, `--optimize 0`, and `--skip-text`.
It does not pass a duplicate `--plugin` registration. Original page sizes, rotations,
page count, and the existence of extracted text are checked before attaching the output.
Cancellation interrupts the worker and removes its private partial output.

PDF text detection counts pages with any extractable text. It is not an OCR quality score.
A scanned page with a small existing text header may require a separate repair workflow;
this app does not automatically force-rasterize it.

## CLI and MCP

```sh
~/Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli --help
./scripts/register-mcp.command
```

Registration uses the official `codex mcp add` and `claude mcp add` commands.
Existing `bookshelf` registrations are preserved. Restart CLI sessions after registration.
MCP tools cannot change notes, import folders, start OCR, or remove files.

Example prompts:

- “내 서재에서 인스타 브레인을 찾아줘.”
- “이 책에서 집중력이라는 단어가 나오는 페이지를 찾아 근거와 함께 설명해줘.”
- “이 책에 내가 남긴 메모를 읽고 이해가 빠진 부분을 짚어줘.”

MCP uses 1-based PDF page numbers, which can differ from printed book page numbers.
Search is literal text search. Tool results distinguish user notes from source quotations.
Book links use `bookshelf://book/<book-id>?page=<number>`.

## Storage

- Database: `~/Library/Application Support/Bookshelf/library.sqlite3`
- OCR logs: `~/Library/Application Support/Bookshelf/Logs/`
- `BOOKSHELF_DATA_DIR` selects a separate data directory for tests or another library.
- The SQLite database stays local; it is not placed in iCloud Drive.
- PDFs remain in their chosen folder. iCloud placeholders are listed but not downloaded in bulk.
- Same-stem original/OCR pairs are grouped. Other aliases are not automatically deduplicated.
- Known file renames preserve the book ID using local file identity. Moving a file while its identity changes is not automatically resolved.
- Folder import excludes hidden folders, `_DEDUP_STAGING`, `00-Materials`, `scripts`, `context`, `prompts`, and `node_modules`. An explicitly chosen PDF can still be added.

## Verification

```sh
swift test
python3 scripts/check-ocr.py dist/Bookshelf.app/Contents/MacOS/bookshelf-cli
python3 scripts/check-mcp.py dist/Bookshelf.app/Contents/MacOS/bookshelf-cli
python3 scripts/check-cancel.py dist/Bookshelf.app/Contents/MacOS/bookshelf-cli
```

OCR checks generate synthetic raster PDFs; no user-owned book is transformed by the test suite.
Tests cover persistence, separate book notes, concurrent revisions, file rename identity,
OCR version attachment, rescans, original-byte preservation, overwrite refusal, and cancellation.
Native UI verification covered typing a notebook, running OCR, selecting and annotating text,
adding a bookmark, searching, and relaunching to verify persistence.
Keyboard verification also covers original PDF and text view, page limits, Space and page keys,
editing without accidental navigation, returning focus, and page-number submission.

Build and verification logs are local under `.runtime/` and excluded from Git.

## Source layout

```text
Sources/BookshelfCore/   SQLite, library import, PDF text, OCR worker
Sources/BookshelfApp/    SwiftUI/AppKit UI and PDFKit integration
Sources/BookshelfCLI/    CLI and the official Swift MCP SDK server
Tests/                  Store and identity regression checks
Resources/              Native app metadata
scripts/                Build, local install, MCP setup, and integration checks
```

The original three-way web prototype is preserved on `feat/reader-ui-prototype`, commit `57ad734`.
The native reader implements the user's chosen B layout. The prototype's source and preview remain separate.

## License

App and core code: MIT, see `LICENSE`. Dependency license notices are copied into the app bundle.
External OCR tools retain their own licenses; their redistribution needs a separate packaging review.
Book files, extracted book text, personal notes, credentials, and local verification data are not part of the source distribution.
