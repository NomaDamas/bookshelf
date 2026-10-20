# Contributing to Bookside

Bug reports, documentation fixes, native UI improvements, and focused patches are
welcome. You do not need an AI account, the maintainer's library, or a private skill
to build the app or run its core tests.

## Start here

1. Read the [overview](README.md) and [getting started guide](docs/01-getting-started.md).
2. Fork the repository and clone your fork for a contribution. Create a focused branch.
3. Build with `./scripts/build-app.sh` and run `swift test`.
4. Use an isolated `BOOKSIDE_DATA_DIR` and synthetic PDFs for development.
5. Read [architecture](docs/05-architecture.md) before changing persistence, import,
   OCR, or the app/CLI boundary.

The [development guide](docs/06-development.md) defines the test prerequisites and
checks for each type of change.

## Report a bug

Search [existing issues](https://github.com/NomaDamas/bookside/issues) first, then
use the bug template. Include:

- What you did, expected behavior, and actual behavior.
- A minimal reproduction with an authored PDF if the problem depends on file content.
- macOS version, architecture, Xcode/Swift version, and source commit.
- The relevant command and a redacted log/error, or a native window screenshot.
- For OCR problems, the OCRmyPDF/AppleOCR versions, mode, and quality-report findings.

Do not attach commercial books, extracted copyrighted text, personal notebooks,
credentials, absolute private library paths, or an entire data directory.
For vulnerabilities, follow [SECURITY.md](SECURITY.md) instead of posting exploit details.

## Propose a change

Describe the user problem and a concrete example. For substantial changes to data
storage, OCR behavior, or MCP capabilities, discuss the contract in an issue before
building a large patch. Check current limitations so a proposal does not assume
an implemented feature such as EPUB support or cross-device note sync.

## Implementation contracts

The contracts every change must preserve, such as stable book identity, original PDF
bytes, notebook revisions, and read-only MCP tools, are listed once in
[AGENTS.md](AGENTS.md#preserve-these-contracts) for human and agent contributors alike.
Follow the native SwiftUI/AppKit/PDFKit structure; UI behavior requires a real native
run, including quit/relaunch for saved state.

## Submit a pull request

Keep one topic per pull request. The title should describe the resulting behavior;
Conventional Commit prefixes such as `docs:`, `fix:`, and `feat:` are useful.
The PR template asks for the problem, change, and validation evidence.

Include exact checks and results, screenshot comparisons for visual changes, and
what you did not verify. Distinguish the minimum deployment target from the actual
test environment. A screenshot proves appearance, not persistence or OCR correctness.
Link a tracked issue with `Closes #N` only when the change resolves it.

Before submitting, run relevant checks, `git diff --check`, and inspect the diff
for accidental assets/data. Keep `.build/`, `.runtime/`, `dist/`, and private PDFs
out of commits. Use synthetic content in test fixtures. Public screenshots and recordings
may also use a public-domain text when the capture record names its source.

## Documentation changes

README files are the short project entry points. Detailed guides live in `docs/`,
in reading order, and are linked from the index. Update the English/Korean README
when shared setup or capability claims change. Preserve useful details when moving
sections; verify relative links, heading anchors, images, and copyable commands.

`AGENTS.md` is the repository's coding-agent entry point; `CLAUDE.md` is a relative
symlink to it. It contains project contracts and conditional documentation pointers,
not personal workstation rules or a second full reference manual.

## Licensing

By submitting a contribution, you agree that your contributed code/docs may be
distributed under this repository's [MIT license](LICENSE). Include provenance and
appropriate notices for third-party material. External OCR tools are separately
installed and keep their own licenses.
