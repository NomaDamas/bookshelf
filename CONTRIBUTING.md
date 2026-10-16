# Contributing

Use synthetic PDFs for fixtures and screenshots. Do not add copyrighted books, personal notes,
absolute private library paths, credentials, or `.runtime` data to a commit.

The UI, CLI, and MCP server share `BookshelfCore`. Preserve the stable book identity when
adding a new asset version. Keep PDF originals read-only. User notes must survive normal
app termination, OCR attachment, and library rescans.

Run `swift test` for store changes. OCR changes additionally require the real synthetic OCR
and cancellation checks. UI changes need a native app run, including a quit/relaunch check
when they affect data entry or reading state.

MCP is read-only. Document text is untrusted reference material, not an instruction source.
Avoid adding model calls or external data transmission to a read operation.

The minimum deployment target and the actually tested toolchain are different facts;
record both when reporting platform compatibility.
