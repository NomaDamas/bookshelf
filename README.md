# Bookshelf / 서재

A native macOS PDF reader with per-book notebooks, local Apple Vision OCR, and read-only access from Codex and Claude Code through MCP.

서재는 PDF를 읽고, 문장을 발췌하고, 책마다 내 생각을 남기는 Mac 앱입니다.
원본 파일은 제자리에 두고, 메모와 읽던 위치를 로컬 SQLite에 저장합니다.

## What works

- Native SwiftUI/AppKit reader with PDFKit rendering, selection, zoom, page navigation, and text view.
- Aside-inspired native material sidebars, neutral controls, and a paper-like notebook surface, with system/light/dark appearance settings.
- Keyboard page turning in both original PDF and text view, with single-page and continuous PDF layouts.
- OCR-friendly Korean/English search that ignores whitespace and line breaks, with an exact-spacing option.
- Per-book notebooks with autosave, save-failure feedback, and revision conflict protection.
- Quoted passages with page coordinates, persistent highlights, comments, and Markdown export.
- Bookmarks and reading position restored after quitting and relaunching.
- Three reading shelves, dated read-through history, note-count badges and persistent sorting.
- Local OCR through OCRmyPDF + AppleOCR using the public Vision `accurate` mode.
- OCR output is a new `_ocr.pdf` file. Existing files are never overwritten.
- The original and its OCR output retain one book ID, notebook, bookmarks, and progress.
- A native CLI and five read-only MCP tools: `list_books`, `read_page`, `search_book`, `get_notes`, and `get_reading_context`.

This experimental branch adds in-app learning chat through Pi and the user's official Claude Code
or Codex executable. The **대화** tab supports source-page context, streaming, per-book conversation
storage and switching executors. The model runs through the selected provider; the app owns the
learning instructions and conversation history. See [the Pi experiment](Resources/Design/PI-AGENT.md)
for account boundaries, setup, scope and verification. The external MCP workflow remains available.

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
| Command-Shift-L | Show the currently reading shelf |
| Command-Option-Left / Right | Previous / next page from anywhere in the reader |

Enter a page number and press Return to jump and keep reading with the keyboard.
The first and last pages are clamped. PDF layout selection is saved between launches.
The keyboard button beside the page controls opens an in-app reference.

The reading area keeps the current book title visible above the controls. Opening a book
preserves the sidebar's visibility. The library marks the current row with its live page;
“책장에서 보기” clears a library filter and scrolls to that book.

## Reading shelves, history and sorting

The sidebar separates **읽기 전** (not started), **읽는 중** (reading) and **읽은 책**
(finished). Command-Shift-L opens the reading shelf. Cards show covers, the saved page,
progress and read-through counts; “펼친 책으로” returns to the open document.

- Opening a new book starts its first reading. Choose **읽기 완료** in its menu to
  record a completed read-through and its date. Jumping to the last page never completes a book.
- Reopening a finished book is a review. **다시 읽기 시작** starts the next read-through
  at page one and preserves all previous completions and notes.
- **회독 기록 보기** lists completion dates. **최근 완료 기록 취소** undoes only the
  latest completion and returns to reading. Repeated completion clicks cannot add duplicates.
- Shelving a first read returns it to not started; cancelling a reread returns it to
  finished with the earlier counts intact. Saved pages and notes remain available.
- Red badges count one nonempty book notebook plus each saved excerpt. Editing or autosaving
  an item does not increase its count. Zero is hidden; 100 or more is displayed as **99+**,
  with the exact number exposed to accessibility. A card's badge opens that book's notes.
- Sort by recently read, recently finished, recently added, title, note count or read-through
  count, with ascending/descending order. The last selection applies across all shelves and
  the sidebar, and survives relaunch. Title ties use a stable secondary order.

Reading state and completion events live in additive SQLite tables. Legacy reading-shelf
membership and saved positions are carried forward; no historical completions or start dates
are invented. Opening a shelf or changing reading state first saves pending notes; a save
conflict preserves the draft in the reader.

[Light preview](Resources/Design/evidence/reading-history-light.png) /
[Dark preview](Resources/Design/evidence/reading-history-dark.png) /
[Compact window](Resources/Design/evidence/reading-history-narrow.png) /
[Completion history](Resources/Design/evidence/reading-history-dates.png).
Previews use authored sample books. See [native checks](Resources/Design/evidence/reading-history-checks.json)
and [upgrade checks](Resources/Design/evidence/reading-history-migration.json).

## Loading performance

The sidebar creates only visible rows and serializes cover generation. The reader retains
up to two unchanged PDF documents within a source-size budget, reuses full-text inspection
results for the exact file version, and cancels obsolete inspection work between pages.
Replacing a PDF or switching its OCR version invalidates the cached data.

In a local two-book comparison, the median time from sidebar selection to PDF-view connection
fell from 2,560 ms to 96 ms. This measures downloaded files with warm filesystem caches,
while a separate OCR batch was running; it is not an iCloud-download or GPU-presentation benchmark.
See [measurement details and regression checks](Resources/Design/PERFORMANCE.md).

## Native design

The reader adapts the [Aside / Glass workspace](https://github.com/seungwonme/ui-references/tree/main/references/aside-glass)
reference to SwiftUI and AppKit. Native materials surround opaque PDF and writing surfaces;
the system font, semantic colors, split views, segmented controls and keyboard behavior remain native.
Choose system, light or dark appearance in settings. Reduced transparency, increased contrast
and reduced motion have dedicated fallback behavior.

The source mapping and intentional differences are in [Resources/Design/DESIGN.md](Resources/Design/DESIGN.md),
with native screenshots and verification in [Resources/Design/verification.md](Resources/Design/verification.md).
Edit [Resources/Design/tokens.json](Resources/Design/tokens.json), then run
`python3 scripts/generate-reader-tokens.py` to regenerate the Swift constants. The app build checks for drift.

## Searching OCR text

The search panel enables “띄어쓰기 무시” by default. `설득의 심리학` can find `설 득 의 심 리 학`,
and `Deep Learning` can find `DE EP LEARN ING`, including line breaks, tabs and Unicode spaces.
Soft hyphens and zero-width spaces are ignored in this search projection too.
PDF files, extracted source text, quotations and page numbers stay unchanged.

Turn the checkbox off when word boundaries matter: removing spaces also makes `the rapist`
match `therapist`. This feature does not correct misspelled characters, rewrite grammar,
or remove visible punctuation/hyphens. It does not install a language model or upload book text.

CLI search uses the same default. Pass `--exact-spacing` to preserve spacing.
The MCP `search_book` tool accepts `ignore_whitespace: false` for the same behavior and returns
the chosen mode alongside original page excerpts.

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

The worker explicitly uses AppleOCR `accurate`, the `sandwich` renderer, ordinary PDF output,
optimization disabled, and overwrite protection. “텍스트 인식” uses `--skip-text` for missing text;
“기존 OCR 개선” uses `--redo-ocr` to replace an existing invisible text layer in a separate copy.
Before replacement, a bundled helper clears render-mode-3 text from supported page and Form streams.
This avoids duplicate text with OCRmyPDF versions that leave old OCR inside nested forms.
The helper uses the Python interpreter from the OCRmyPDF launcher; a custom launcher can specify
`BOOKSHELF_OCR_PYTHON` pointing to the same environment with pikepdf installed.
The app opens a review screen before connecting either result to the book. Compare extracted text
or PDF pages, test a literal phrase, and choose the new copy or keep the current PDF.

Quality checks cover page count/geometry, text presence, excess character spacing, text loss,
and PDFKit/Poppler agreement on every page. Poppler is optional; unavailable checks are reported.
Rendered appearance is compared on up to three text-bearing pages, not the entire book.
The report records pixel differences. It permits Quartz rounding on at most 0.001% of pixels
(minimum four pixels), with a maximum per-channel difference of 8/255. Larger changes require review.
Flags require explicit review in the app; they are not a claim that every recognized word is correct.
Acceptance verifies source and candidate hashes again, then preserves the book ID, notes, bookmarks,
and progress. Cancellation interrupts OCR and removes its private partial output.
Unaccepted candidates are excluded from folder rescans and can be reopened from “생성한 OCR 사본 검토”.
Previously accepted OCR versions remain associated with the same book during later rescans.
“원본 PDF 사용” (or `ocr-original <book-id>`) returns to the source without deleting OCR copies or notes.
That choice also survives folder rescans.

CLI users can run `ocr <book-id> --redo --review-only` to create a candidate and JSON report without
attaching it. After review, `ocr-accept <result-json>` attaches the unchanged candidate. Default CLI OCR
refuses automatic attachment when quality checks need review. MCP remains read-only.

PDF text detection counts pages with any extractable text. It is not an OCR quality score.
A scanned page with a small existing text header may require a separate repair workflow;
this app does not automatically force-rasterize it.

## Existing OCR layer maintenance

The optional scripts below audit and repair one specific failure mode in some AppleOCR PDFs:
standalone invisible spaces inserted between Korean characters. They do not rewrite grammar,
run a language model, or replace recognized letters. They require Poppler and a Python environment
with `pikepdf` and Pillow, in addition to the Swift/PDFKit probe.

- `pdf-text-probe.swift`: extract PDFKit text/geometry for selected pages or `all` pages.
- `audit-text-layer.py`: compare sampled PDFKit/Poppler text. A clean sample is not proof that every page is accurate.
- `repair-ocr-spacing.py`: propose removal of separately positioned invisible GlyphLessFont spaces only where a complete, unambiguous source-text match supports it. Without `--output`, it is a dry run.
- `validate-text-layer.py`: compare all PDFKit/Poppler non-whitespace text, page geometry, image stream bytes, and chosen rendered pages.
- `stage-spacing-repairs.py` / `finalize-spacing-repairs.py`: prepare candidates and restore any pages where either extractor's reading order changes. Unsupported or ambiguous text remains untouched.
- `apply-spacing-repairs.py`: verify source/candidate hashes, back up originals, then replace files atomically. A dry run is the default; `--apply` is explicit.
- `restore-text-layer-backup.py`: restore originals only if the current PDF still matches the recorded repair; keep a copy of the repaired file too.

Every tool has `--help`, except the standalone restore tool, which accepts its backup directory.
Keep the virtual environment's Python executable path when passing `--python`; resolving its symlink
to a base interpreter bypasses the environment's installed dependencies.
Placeholder downloads require an explicit file list and `--download-placeholders`; normal auditing
does not download them. A FileProvider timeout leaves the PDF unmodified and its audit incomplete.
Do not apply a candidate with a failed validation report. These tools do not edit the global OCR skill
or an installed third-party package. The app continues to use explicit Apple Vision `accurate` mode.

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
Search is keyword search with optional whitespace normalization, not semantic search.
Tool results distinguish user notes from source quotations.
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
python3 scripts/check-ocr-review.py dist/Bookshelf.app/Contents/MacOS/bookshelf-cli
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
Search regression tests cover Korean/English OCR spacing, Unicode spaces, emoji and decomposed
text offsets, unchanged quotations, empty queries and exact-spacing false-positive control.
The stdio MCP check covers both search modes and rejects an invalid option type.

Build and verification logs are local under `.runtime/` and excluded from Git.

`scripts/check-ocr-preparation.py`, run in the OCRmyPDF Python environment, verifies nested hidden
text removal while preserving visible/mixed text, vectors and image pixels. `audit-text-layer.py`
supports full-page inspection and append-only retries. `maintain-pdf-library.py` follows an audit,
backs up spacing repairs, and creates OCR copies with the same book identity; it is dry-run unless
`--apply` is explicit. Candidates with quality flags remain available for review in the app.
`report-pdf-maintenance.py` produces a live/final per-file report without modifying the library.
`restore-library-maintenance.py` previews a job rollback; `--apply --stop-running` stops that job,
restores its original selections and spacing backups, and keeps OCR copies and notes.

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
