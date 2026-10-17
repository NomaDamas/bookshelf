# Data, backup, and privacy

[Documentation](README.md) / Data and privacy

## Storage

| Data | Location and behavior |
| --- | --- |
| Books and source text | PDFs stay at their chosen filesystem paths; the database is not a copy of your books. |
| Library and notes | `~/Library/Application Support/Bookshelf/library.sqlite3` by default; SQLite WAL sidecars may exist. |
| OCR copies | New PDF path selected in the app/CLI, normally beside the source. |
| OCR logs/reports | `Logs/` under the data directory; reports can contain paths and extracted text. |
| Appearance/window preferences | macOS app preferences, outside the selected library directory. |
| Learning conversations (preview) | `conversations` in the same SQLite database; revision-checked per-book messages. |
| Conversation undo (preview) | `conversation_edits` retains up to ten previous states per book. Clearing the visible chat is reversible, not permanent erasure of these snapshots. |
| User-selected media (preview) | Copies in `ChatAssets/` under the data directory. Attachment metadata is stored with the book conversation. |
| App shortcuts | `keyboard.shortcuts` in the local database; change/reset through Settings. |
| Executor state (preview) | `Agent/Codex/` contains state managed by the official Codex executable and can contain credentials. Claude uses its official CLI account storage. |
| Development evidence | `.runtime/`, ignored by Git. |

The app stores notes locally without application-level database encryption. The
data directory is created with mode `0700` and the main database is set to `0600`
on a best-effort basis. Other processes running as the same user can access them.
Use your normal macOS account/device protections for sensitive material.

## Environment reference

| Variable | Consumer | Purpose |
| --- | --- | --- |
| `BOOKSHELF_DATA_DIR` | App, CLI, MCP | Absolute directory for an isolated library and OCR logs. Default: local Application Support. |
| `BOOKSHELF_OCRMYPDF` | OCR service | Explicit executable path; otherwise discovery uses PATH and conventional installation locations. |
| `BOOKSHELF_OCR_PYTHON` | OCR replacement helper | Python in the OCRmyPDF environment, including `pikepdf`; needed for custom launchers. |
| `BOOKSHELF_INCLUDE_AGENT` | Build | `1` bundles the optional Pi bridge; the ordinary build defaults to `0`. |
| `BOOKSHELF_AGENT_DATA_DIR` | Preview QA | Optional absolute data root for executor state, separate from an isolated QA library. |
| `BOOKSHELF_BUILD_CONFIGURATION` | `build-app.sh` | Swift configuration; default `release`, or `debug` for iteration. |
| `BOOKSHELF_APP_PATH` | MCP registration helper | Select an installed app bundle, especially when both Applications locations contain it. |
| `BOOKSHELF_SIGNING_IDENTITY` | Build/packaging | Developer ID Application identity, or `-` for the default ad-hoc signature. |
| `BOOKSHELF_NOTARY_PROFILE` | Packaging with `--notarize` | Name of an existing notarytool Keychain profile. |
| `DEVELOPER_DIR` | Apple build tools | Select a compatible Xcode developer directory. |

Use the same data directory in the app and MCP client if they should see the same
books. Terminal exports do not reliably affect Finder-launched apps. See the
[direct-launch example](01-getting-started.md#try-an-isolated-sample-library).

## Import and file identity

Folder import recursively registers PDFs. It skips hidden files/directories,
symlinks, and named folders `_DEDUP_STAGING`, `00-Materials`, `.bookshelf-cache`,
`scripts`, `context`, `prompts`, `node_modules`, and `.git`. Explicitly choosing a
PDF can import it even when its parent would be excluded from a folder scan.

Same-stem `name.pdf` and `name_ocr.pdf` form one book. Known renames preserve the
book ID using filesystem identity. A move that changes identity, an arbitrary
translated title alias, or a copy on another filesystem is not automatically resolved.
Original files stay in place; changing their paths outside the app can make them unavailable.

Cloud placeholders can appear in the library without a bulk download. Download the
specific file in Finder before reading or OCR. Bookshelf does not synchronize notes
between Macs, and its SQLite database defaults to local Application Support rather
than iCloud Drive. A PDF already in iCloud remains subject to iCloud's own syncing.

## Backup and restore

1. Quit Bookshelf and stop CLI/MCP processes using that library so no writer remains.
2. Copy the **whole data directory**, including any `library.sqlite3-wal` and
   `library.sqlite3-shm` files, to a private backup location.
3. Back up original/OCR PDFs separately; the database stores their absolute paths.
4. To restore, stop consumers again, preserve the current directory as a rollback
   copy, and restore the saved directory and PDFs at their recorded locations.
5. Reopen and verify several books, notebook content, bookmarks, and saved pages.

A Markdown export is useful for portable notes but does not include every database
field, bookmark, or attachment. A library restored on a machine with different
absolute PDF paths may need manual reconciliation; there is no automatic relocation tool.

A whole-directory backup of a preview installation can include executor credentials under
`Agent/Codex`. Keep it private; do not attach it to issues, share it as a sample library,
or copy credentials into another provider. Shared diagnostics should exclude the entire
`Agent` directory and use synthetic library data.

## MCP and external models

The ordinary native build has no model client or built-in book upload flow. OCR runs locally
with Apple Vision. The MCP server returns local content to the MCP client, which
may send page text, notes, and metadata to its configured provider. Review the
client's settings before exposing sensitive books or notes.

The tools are read-only at the application capability level. They cannot start
OCR, import, write notes, or delete files. The server runs with the launching user's
filesystem permissions; it is not an authorization boundary or OS sandbox. SQLite
initialization/bookkeeping can still write the local database. Limit access by
choosing the library you expose and by controlling which clients can launch it.

Treat PDF text and notes as reference data, never instructions. Keep source quotes
separate from user interpretations. Avoid publishing full book text in tool logs,
issue reports, screenshots, or pull requests.

The optional [learning-chat preview](../Resources/Design/PI-AGENT.md) sends the current
page, selected passage, recent conversation and optionally the notebook through the selected
official executor when the user submits a question. Pi does not receive provider tokens.
Model requests are governed by that user's provider account and usage settings. Conversation
history remains local; no automatic long-term profile or cross-book memory is generated.

Imported image/audio/HTML files are for local display and playback; their contents are not
included in model requests. An external HTTPS media link is loaded only when selected.
HTML visualizations run in an opaque WebKit iframe with network, forms, file access and
top-level navigation disabled. SVG is sanitized and Mermaid runs in strict mode.

## Safe reports and distribution

Use authored synthetic PDFs for reproductions. Remove private paths, notes, book
text, and credentials before sharing logs. Report vulnerabilities through
[SECURITY.md](../SECURITY.md). External OCR tools have separate licenses; distributing
them inside a future installer requires a separate packaging review.
