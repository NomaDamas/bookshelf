# Local OCR

[Documentation](README.md) / OCR

OCR makes an image-only PDF searchable/selectable or improves an existing invisible
text layer. Reading PDFs and writing notes do not require an OCR installation.

## Install the optional engine

Install [uv](https://docs.astral.sh/uv/getting-started/installation/) and
[Homebrew](https://brew.sh/) if needed, then:

```sh
uv tool install ocrmypdf --with "ocrmypdf-appleocr @ git+https://github.com/mkyt/OCRmyPDF-AppleOCR.git"
brew install ghostscript
```

The integration has been verified with OCRmyPDF 17.10.0 and AppleOCR 0.4.0.
The command above resolves upstream packages at installation time; it is not a
reproducible dependency lock. Python, OCRmyPDF, AppleOCR, and Ghostscript are
external tools, not bundled app components. Install Poppler with `brew install poppler`
if you also want the second text extractor used by quality checks. Without it,
results require manual review and default CLI automatic attachment exits with a
review-needed error. Poppler is required by the integration test sequence.

## Create and review a copy

1. Open a downloaded PDF and choose **텍스트 인식…** for missing text, or
   **기존 OCR 개선…** to replace its existing invisible text layer.
2. Choose a new output PDF. Existing paths and the original are refused.
3. Wait for the local process and quality report. You can cancel from the app.
4. Compare the original and result in the review screen. Check extracted text,
   page appearance, and a literal phrase you can read on the page.
5. Accept the copy or keep the current PDF. Acceptance preserves the book ID,
   notebook, highlights, bookmarks, and progress.

![OCR review with an authored sample document](../Resources/Design/evidence/ocr-review-dark.png)

The app always opens review before attaching output. Unaccepted candidates stay
excluded from rescans and can be reopened with **생성한 OCR 사본 검토…**.
A known [temporary-path alias issue](https://github.com/NomaDamas/bookside/issues/2)
can bypass candidate withholding under `/var` / `/private/var`; use a regular
library path while that issue is open.

**원본 PDF 사용** returns to the source without deleting OCR copies or notes;
that selection survives a rescan. Accepted versions continue to belong to one book.

## CLI review workflow

Set `BOOKSIDE_CLI` and `BOOK_ID` using the [CLI guide](03-cli-and-mcp.md).
Use a new report destination for each run:

```sh
"$BOOKSIDE_CLI" ocr "$BOOK_ID" --redo --review-only > ocr-result.json
```

Progress goes to stderr. Successful JSON includes the output path, source/output
hashes, inspection, quality findings, and a report location. Inspect the report
and PDFs before accepting:

```sh
"$BOOKSIDE_CLI" ocr-accept ocr-result.json
```

To restore the source selection:

```sh
"$BOOKSIDE_CLI" ocr-original "$BOOK_ID"
```

The accept command is the user's explicit review decision. It rechecks source and
candidate hashes; it does not itself review the text. Without `--review-only`, CLI
OCR can automatically attach a result that passes checks, but refuses attachment
when quality flags require review. MCP cannot start or accept OCR.

## Processing contract

The worker uses Apple Vision `accurate`, the `sandwich` renderer, ordinary PDF
output, `--optimize 0`, overwrite protection, and two jobs. Missing-text mode uses
`--skip-text`; replacement mode uses `--redo-ocr`. Replacement first invokes the
bundled `prepare-ocr-replacement.py` helper to clear render-mode-3 invisible text
from supported page/Form streams in a separate prepared copy. This prevents old
nested OCR text from being retained alongside new text.

Output defaults to the first free `title_ocr.pdf`, then `title_2_ocr.pdf`, and so on.
Cancellation interrupts the worker and removes private partial/prepared output.
A completed but unaccepted candidate is kept for review. Logs and result reports
live in `Logs/` under the selected Bookside data directory.

## Quality checks and limitations

Checks cover page count/geometry, text presence, excess character spacing, text
loss, and PDFKit/Poppler agreement on every page. Poppler is optional; skipped
checks are reported rather than counted as passing.

Rendered appearance is compared on **up to three text-bearing pages**, not the
entire book. Quartz rounding is allowed on at most 0.001% of pixels (minimum four),
with at most 8/255 difference per channel. Larger changes require review.
These checks identify risks; they do not certify every recognized word.

Text detection counts pages with any extractable text. A scanned page with a small
existing text header may be skipped by missing-text mode. Bookside does not
implicitly force-rasterize such pages. Search whitespace normalization can improve
matching without altering a PDF; it does not repair recognition errors.

For the narrower invisible-spacing problem, see [advanced maintenance](08-pdf-maintenance.md).
Those tools have a different mutation boundary from the app's new-copy workflow.

## Engine discovery and troubleshooting

Discovery checks executable `BOOKSIDE_OCRMYPDF`, then `PATH`, `~/.local/bin`,
`/opt/homebrew/bin`, and `/usr/local/bin`. CLI `doctor` reports the selected path.
Set overrides in the process that launches Bookside; terminal variables may not
reach an app opened from Finder.

The replacement helper normally uses the Python interpreter in the OCRmyPDF
launcher's shebang. If using a custom launcher, set `BOOKSIDE_OCR_PYTHON` to the
matching environment's Python with `pikepdf` installed. Keep the virtual environment
executable path; resolving its symlink to a base interpreter loses its packages.

| Symptom | Next check |
| --- | --- |
| Engine not found | Run `command -v ocrmypdf` and CLI `doctor`; check discovery paths. |
| AppleOCR option/plugin error | Check the AppleOCR plugin is installed in the same environment as OCRmyPDF. |
| Ghostscript error | Check `command -v gs` and the OCR log. |
| Replacement helper fails | Check launcher interpreter, `pikepdf`, and `BOOKSIDE_OCR_PYTHON`. |
| Cloud-only source | Download that PDF in Finder, then retry. |
| Candidate needs review | Inspect quality flags and compare source/result; keep the original if uncertain. |
| Source or candidate changed | Acceptance refuses stale hashes. Generate and review a fresh candidate. |

Run the real [synthetic OCR checks](06-development.md#ocr-and-mcp-integration-checks)
to verify the installed dependency combination. Avoid testing repairs on a private
library while diagnosing an installation.
