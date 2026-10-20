# Development and verification

[Documentation](README.md) / Development

Follow [getting started](01-getting-started.md) first. Commands below run from the
repository root on macOS with the same compatible Xcode toolchain used to build.

## Build modes

```sh
./scripts/build-app.sh
```

The default is a release app bundle. For faster iteration:

```sh
BOOKSIDE_BUILD_CONFIGURATION=debug ./scripts/build-app.sh
```

Both configurations write `dist/Bookside.app`; rebuild release before describing a
bundle as a release build. A release build strips the bundled executables and writes
their symbols to `dist/dSYMs/`; a debug build keeps symbols in the executables.
`swift build` alone does not assemble the `.app` resources, icon, metadata, notices,
and signature. Never point development commands at a
private library: use an absolute `BOOKSIDE_DATA_DIR` and synthetic PDFs.

## Core and app regression tests

```sh
swift test
python3 scripts/generate-reader-tokens.py --check
python3 scripts/app-metadata.py check
git diff --check
```

The XCTest suites use isolated files/databases. Core tests cover persistence,
revision conflicts, book identity, rescans, search offsets/spacing, and quality
checks. App-model tests cover document reuse/invalidation, reading-shelf membership,
pending note saves, and stale PDF-view events. These are not end-to-end native UI tests.
No OCR engine or AI credentials are needed for `swift test`.

The learning chat bridge in `Sources/BookshelfAgent` has its own TypeScript check and
Bun tests. They need Node.js, pnpm and Bun, but no provider account:

```sh
pnpm --dir Sources/BookshelfAgent install --frozen-lockfile --ignore-scripts
pnpm --dir Sources/BookshelfAgent run typecheck
pnpm --dir Sources/BookshelfAgent test
```

## OCR and MCP integration checks

First install the [OCR dependencies](04-ocr.md#install-the-optional-engine) and
build the bundle. These integration checks also require Poppler (`brew install poppler`)
and a discoverable `pdftotext`. It is optional for manual app review, but
`check-ocr.py` requires successful automatic attachment. Run the checks **sequentially**:

```sh
python3 scripts/check-ocr.py dist/Bookside.app/Contents/MacOS/bookside-cli
python3 scripts/check-ocr-review.py dist/Bookside.app/Contents/MacOS/bookside-cli
python3 scripts/check-mcp.py dist/Bookside.app/Contents/MacOS/bookside-cli
python3 scripts/check-reading-mcp.py dist/Bookside.app/Contents/MacOS/bookside-cli
python3 scripts/check-cancel.py dist/Bookside.app/Contents/MacOS/bookside-cli
```

`check-ocr.py` generates a two-page raster fixture and writes
`.runtime/ocr-check-result.json`. **`check-mcp.py` requires that file and its surviving
fixture/database**, even when you supply a different CLI path. Run OCR first; do
not clean `.runtime/` between those checks. The MCP check launches a real stdio
client and verifies all five tools, search modes, and invalid arguments. It sends
no model requests and uses no credentials.
`check-reading-mcp.py` uses the same fixture to verify the four in-app reading tools,
page-boundary enforcement, blocked book switching, coverage and Codex's initialization shape.

The review check exercises candidate acceptance, identity, rescan behavior, and
source protection. The cancellation check creates a larger synthetic fixture,
sends SIGINT, and verifies original hashes and partial-output cleanup. Results and
logs are written under `.runtime/`, which is ignored by Git. Do not run multiple
copies of this integration sequence in the same checkout: summary filenames are shared.

Known issue: under a macOS temporary checkout, `/var` and `/private/var` aliases
can bypass candidate withholding and fail the review check. See [issue #2](https://github.com/NomaDamas/bookside/issues/2).
The same check passes from a regular development directory. Use a non-aliased
checkout for the standard verification path; do not interpret that pass as a fix
for the temporary-path regression.

For changes to the replacement helper, run this with the **OCRmyPDF environment's
Python executable**, which must contain `pikepdf` and Pillow:

```sh
"$BOOKSIDE_OCR_PYTHON" scripts/check-ocr-preparation.py
```

Set `BOOKSIDE_OCR_PYTHON` to that actual interpreter first; this example deliberately
does not guess an environment path. The check covers nested invisible text while
preserving visible/mixed text, vectors, and pixels.

## Select checks by change

| Change | Required evidence |
| --- | --- |
| Docs only | Verify links/images and command examples; inspect the rendered README. |
| Store/import/search | `swift test`; relevant identity, conflict, Unicode/search regressions. |
| OCR service/helper | Core tests plus real OCR, review, cancellation, and helper preparation checks. |
| MCP | Protocol check after its OCR prerequisite; verify the advertised tool schema. |
| UI/focus/reader state | App tests plus a native app run; quit/relaunch for persistence changes. |
| Learning chat bridge | Bridge typecheck and Bun tests above; panel changes also need the UI checks. |
| Design tokens | Regenerate Swift constants, check drift, build, inspect light/dark and compact UI. |

## Screenshots and UI verification

Screenshots and recordings must come from the running native app. Their content is
either an authored fixture or a public-domain text whose source the capture record names.
Use the isolated sample setup in [getting started](01-getting-started.md#try-an-isolated-sample-library).
Capture only the app window, inspect the saved image, and exclude personal books,
notes, file paths, notifications, and unrelated desktop content.

The README's `readme-demo.gif`/`readme-demo.mp4` recording and the
`readme-reader-light.jpg` and `readme-reader-dark.jpg` screenshots are current
native captures. [Capture record](../Resources/Design/evidence/readme-capture.md)
records the source revision, content, editing, and environment. Other gallery images link
to existing dated [verification](../Resources/Design/verification.md) and
[reading-shelf checks](../Resources/Design/evidence/reading-shelf-checks.json).
They are real UI captures, not mockups.

For behavioral changes, check PDF/text navigation, first/last page boundaries,
normal editing keys inside notes/search/page fields, quotation selection, notebook
save status, shelf resume, and quit/relaunch. Include narrow and wide windows and
light/dark appearance. Record which accessibility modes were actually exercised;
source inspection alone does not verify VoiceOver or a system preference transition.

## Generated tokens and source layout

```sh
python3 scripts/generate-reader-tokens.py
python3 scripts/generate-reader-tokens.py --check
```

The JSON is canonical; commit both it and generated Swift after a token change.
The generator command writes the Swift file, while `--check` only checks drift.
For module responsibilities, see [architecture](05-architecture.md).

The [CI workflow](../.github/workflows/ci.yml) runs XCTest and, in parallel, the release
build with DMG/CLI execution on Apple Silicon and Intel, plus the bridge checks on Linux. OCR and interactive native UI checks
remain separate. A local passing run is evidence for that machine/toolchain. Include commands,
results, and any untested paths in your pull request. No version bump or public binary
release is implied by a documentation change. Follow [releasing](09-releasing.md)
for version changes, signing, packaging, and tags.
