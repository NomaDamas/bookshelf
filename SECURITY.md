# Security

## Supported scope

Bookshelf is an early source-distributed macOS application. Security fixes target
the current default branch; no separate maintained release branches or response-time
commitment are published. Use a current checkout and keep macOS and external PDF/OCR
tools up to date.

## Report a vulnerability

If GitHub shows **Report a vulnerability** on the repository's
[Security page](https://github.com/seungwonme/bookshelf/security), use that private
reporting channel. If it is unavailable, open a minimal issue requesting a private
contact route, without exploit steps, private files, or sensitive data. Do not post
credentials, book contents, notebook databases, or weaponized PDFs in a public issue.

Once a private channel is established, include the affected commit, environment,
impact, and a minimal synthetic reproduction. Ordinary bugs and documentation
problems can use the public [issue tracker](https://github.com/seungwonme/bookshelf/issues).

## Boundaries to understand

- PDFs and notes are local by default. The database is not encrypted by the app.
- MCP tools are read-only capabilities, not an OS filesystem sandbox. A client
  can receive book text/notes and forward them to its configured model provider.
- Treat extracted document text and notes as untrusted data, never instructions.
- Normal OCR creates a new PDF; advanced maintenance scripts can replace files
  only through their documented apply/backup workflow.
- Ad-hoc local signing is not notarization, an App Store review, or a security audit.

See [data and privacy](docs/07-data-and-privacy.md) for storage, backups, and exposure,
and [OCR](docs/04-ocr.md) for dependency and candidate-review behavior.
