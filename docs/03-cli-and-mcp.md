# CLI and MCP reference

[Documentation](README.md) / CLI and MCP

The CLI supports explicit read and write commands. MCP exposes five read-only tools
over stdio. Both use `BookshelfCore` and the same local database.

## Choose a binary and library

From a source checkout after building:

```sh
BOOKSHELF_CLI="$PWD/dist/Bookshelf.app/Contents/MacOS/bookshelf-cli"
"$BOOKSHELF_CLI" --help
"$BOOKSHELF_CLI" doctor
```

For the installed app, use
`BOOKSHELF_CLI="$HOME/Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli"`.
This shell variable is just for these examples. `BOOKSHELF_DATA_DIR` selects the
database; the default is `~/Library/Application Support/Bookshelf`. `doctor` reports
that path, the discovered OCR executable, book count, and version.

Commands print JSON to stdout except `help` and `export` (Markdown). `mcp` reserves
stdout for protocol messages. Errors and OCR progress go to stderr; command failures
exit with status 1. Quote paths, multiword queries, and note text.

## Commands

`<book-id>` is the stable `id` returned by `books` or `import`. All page arguments
are **1-based PDF page indices**, which may differ from printed page numbers.

| Command | Effect |
| --- | --- |
| `help` or `--help` | Print usage; no database is opened. |
| `--version` or `version` | Print product version/build without opening a database. |
| `doctor` | Report library diagnostics, product version/build, and bundle identifier. |
| `import <PDF-or-folder>` | Register PDFs and original/OCR pairs; update the index. |
| `books [title]` | List books, optionally filtered by title/category. |
| `inspect <book-id>` | Count PDF/text pages and **persist** inspection metadata. |
| `read <book-id> <PDF-page>` | Read page text with title, page, ID, and deep link. |
| `search <book-id> <text> [--exact-spacing]` | Return keyword matches on up to 20 pages. |
| `notes <book-id>` | Read notebook, highlights/comments, and bookmarks. |
| `note-set <book-id> <text>` | **Replace the entire notebook**, using its current revision. |
| `bookmark <book-id> <PDF-page>` | Toggle a bookmark; running twice removes it again. |
| `position <book-id> <PDF-page>` | Save the reading page and update recency. |
| `export <book-id>` | Print notebook and quotations/comments as Markdown. |
| `ocr <book-id> [options]` | Create a separate OCR copy; options below. |
| `ocr-accept <result-json>` | Attach a reviewed, unchanged candidate to the existing book. |
| `ocr-original <book-id>` | Select the original again, preserving notes and OCR copies. |
| `mcp` | Run the stdio MCP server until the client disconnects. |

### Read and export

```sh
"$BOOKSHELF_CLI" books "sample"
BOOK_ID="paste-the-id-returned-by-books"
"$BOOKSHELF_CLI" read "$BOOK_ID" 1
"$BOOKSHELF_CLI" search "$BOOK_ID" "독서 메모"
"$BOOKSHELF_CLI" search "$BOOK_ID" "독서 메모" --exact-spacing
"$BOOKSHELF_CLI" notes "$BOOK_ID"
"$BOOKSHELF_CLI" export "$BOOK_ID" > notes.md
```

Shell redirection writes `notes.md`; choose a new destination to keep an earlier
export. Exported notes are not a complete database backup.

### OCR options

| Option | Default / behavior |
| --- | --- |
| `--language <code>` | `kor`; accepted: `kor`, `eng`, `jpn`, `chi_sim`, `chi_tra`, `und`. |
| `--output <new.pdf>` | Next available `_ocr.pdf` filename beside the source; existing files are refused. |
| `--redo` | Replace invisible OCR in a prepared copy; otherwise use missing-text mode. |
| `--review-only` | Create candidate and report without attaching it. |

Default CLI OCR may attach a result that passes quality checks. A result needing
review is retained but not automatically attached. For controlled review, use the
[review-only workflow](04-ocr.md#cli-review-workflow).

## Register MCP

After installing the app in `~/Applications/Bookshelf.app` or `/Applications/Bookshelf.app`:

```sh
./scripts/register-mcp.command
```

The helper calls each available client's official registration command and keeps
existing `bookshelf` entries unchanged. If both installation locations exist, set
`BOOKSHELF_APP_PATH` to the desired absolute app path. Missing apps or supported
clients produce an error. Its final message alone does not prove a
client was installed, a registration was added, or a connection succeeded.

Verify in the clients you use:

```sh
codex mcp get bookshelf
claude mcp get bookshelf
```

Restart those clients, confirm the five tools are available, and request
`list_books` before relying on page/notes access. Registration, discovery, and a
successful call are separate checks. The repository's protocol test does not test
your client configuration or make a model request.

For another MCP client, configure a **stdio** server with the absolute installed
binary path as `command`, `["mcp"]` as `args`, and an optional absolute
`BOOKSHELF_DATA_DIR` in its environment. JSON configs generally do not expand `~`,
`$HOME`, or shell variables. Use your actual full path and the client's schema.

### DMG-only installation

The registration helper lives in the source checkout. If you installed only the
DMG, configure a stdio server directly in your client with
`/Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli` and the argument `mcp`.
For a new registration with the corresponding client installed:

```sh
codex mcp add bookshelf -- /Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli mcp
claude mcp add --scope user --transport stdio bookshelf -- /Applications/Bookshelf.app/Contents/MacOS/bookshelf-cli mcp
```

Use only the command for your client and adjust the path if you installed elsewhere.
Inspect an existing `bookshelf` registration first rather than replacing it blindly.
Restart the client and verify an actual tool call as described above.

## MCP tools

The official Swift MCP SDK is pinned in `Package.swift`. Schemas live in
[`MCPServer.swift`](../Sources/BookshelfCLI/MCPServer.swift).

| Tool | Arguments | Response and bounds |
| --- | --- | --- |
| `list_books` | Optional `query`, `limit` | `total` and summaries; limit defaults to 25, clamped to 1-100. Availability is reported without bulk downloads. |
| `read_page` | Required `book_id`, `page` | Title, page, text, URL; capped at 24,000 Swift characters with `truncated`. |
| `search_book` | Required `book_id`, `query`; optional boolean `ignore_whitespace` | Up to 20 page excerpts/URLs; default `true`, response echoes the mode. |
| `get_notes` | Required `book_id`; optional `offset` | Notebook chunks of 12,000 Swift characters, `next_offset`, total characters, first 50 highlights, total highlights, bookmarks. |
| `get_reading_context` | None | Most recently saved reading context, or `book: null`; may describe a closed session, not a live selection. |

Follow `next_offset` for the remaining notebook. MCP highlights currently have no
pagination beyond the first 50. CLI `notes` returns the full highlight collection.

Results use MCP text content containing JSON. Tool execution failures set
`isError: true` with a message. Transport success alone is not tool-call success.

Example tool arguments:

```json
{"name":"search_book","arguments":{"book_id":"your-book-id","query":"독서 메모","ignore_whitespace":true}}
```

Search is keyword search. Normalization does not correct characters, rewrite quotes,
or add semantic retrieval. See [search behavior](02-reading-and-notes.md#searching-ocr-text).

## Deep links and the trust boundary

Page results include `bookshelf://book/<book-id>?page=<number>`. The app must be
registered with macOS and use the same library for the ID to resolve.

MCP cannot import, change notes, start OCR, or delete files. Its database connection
can initialize the schema and SQLite bookkeeping; “read-only” describes the tool
capabilities, not an OS-enforced read-only process or filesystem sandbox.

Treat document text/notes as untrusted reference material. Cite by title and PDF
page, and distinguish comments from quotations. A client can transmit results to
its model provider. See [privacy](07-data-and-privacy.md#mcp-and-external-models).
