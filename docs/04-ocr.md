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

Output defaults to the first free `name_ocr.pdf`, then `name_2_ocr.pdf`, and so on, where
`name` is the source file name without `.pdf` or a trailing `_ocr`.
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

## Tables and formulas (structure layer)

The text layer above stays the source for search and selection. The optional
structure layer adds, for each page, Markdown with HTML tables and LaTeX formulas
plus the position of every layout block. PaddleOCR-VL-1.6 with the PP-DocLayoutV3
layout model produces it on this Mac. A result belongs to one PDF file version and
reaches Pi only after you accept it. The app review screen is planned in
[issue #44](https://github.com/NomaDamas/bookside/issues/44); until then the CLI runs,
shows and accepts results.

### Install the structure engine

The engine needs Apple Silicon. Install the PaddleOCR pipeline and the mlx-vlm server
as two uv tools:

```sh
uv tool install --python 3.12 "paddleocr[doc-parser]==3.7.0" --with "paddlepaddle==3.3.1"
uv tool install --python 3.12 "mlx-vlm==0.7.6"
```

These commands and versions were verified on an M5 Pro with macOS 26.6. The first
run downloads `PaddlePaddle/PaddleOCR-VL-1.6` (1.8 GB) into the Hugging Face cache
and PP-DocLayoutV3 (126 MB) plus a 10 MB font into `~/.paddlex`. While it runs,
the server takes about 4.5 GB of memory and the pipeline about 1.1 GB.

Discovery checks `BOOKSIDE_STRUCTURE_PYTHON` (the Python of the PaddleOCR
environment), then the interpreter of a `paddleocr` launcher in `PATH`,
`~/.local/bin`, `/opt/homebrew/bin` or `/usr/local/bin`. It checks
`BOOKSIDE_MLX_VLM_SERVER`, then `mlx_vlm.server` in the same places.
`BOOKSIDE_STRUCTURE_MODEL` replaces the model name, for example to try a 4-bit
build. `structure-status` reports what was found.

### Run, review and accept

```sh
"$BOOKSIDE_CLI" structure "$BOOK_ID" --pages 12-30 > structure-run.json
"$BOOKSIDE_CLI" structure-status "$BOOK_ID" --pages 12-30 > structure-review.json
"$BOOKSIDE_CLI" structure-accept "$BOOK_ID" --pages 12-30
```

- `structure` starts its own mlx-vlm server on a free localhost port, sends one
  recognition request at a time, and stops the server when it ends. Progress goes
  to stderr. Logs are in `Logs/` under the data directory.
- Each finished page is stored at once as a `candidate`. After Ctrl-C or a failure,
  the finished pages stay stored, and `--resume` skips every page that already has
  a result.
- Without `--resume`, candidate and `needs_review` pages in the range are
  recomputed. Accepted pages are never replaced.
- A page that trips a guard (see the pitfalls below) is stored as `needs_review`
  with its reasons. `structure-accept` never accepts it; run `structure` on it again.
- `structure-status --pages` prints the Markdown and blocks to review. Compare them
  with the page image before you accept. Like `ocr-accept`, `structure-accept` is
  your review decision; it does not check the content itself.

### What is stored

Results are keyed by book ID, the SHA-256 of the active PDF file and the page.
Accepting an OCR copy or choosing the original changes the active file, so the
other version's results stop showing. `structure-status` lists them under
`otherVersions`, and switching back shows them again.

| Field | Content |
| --- | --- |
| `state` | `candidate`, `accepted` or `needs_review`. |
| `markdown` | Page Markdown. Tables are HTML without Paddle's inline styles, and a line break inside a cell is `<br>`. Display formulas are `$$...$$` with their formula number as `\tag{...}`. Footnotes and side notes follow a `---` line. Figures are `[figure]`. |
| `blocks` | Every layout block in reading order: `type` (the Paddle label), `bbox`, and `markdown` (tables), `latex` (formulas) or `text`. Running headers, footers and page numbers appear only here. |
| `bbox` | `[x, y, width, height]` in PDF points from the lower-left corner of the crop box, in unrotated page space. Add `geometry.cropBox` x and y to get PDFKit page coordinates. |
| `engine`, `geometry` | Engine, model, layout model, PaddleOCR and mlx-vlm versions, concurrency, render DPI, crop box, rotation and image size. |

Pages are rendered at 200 DPI, with the longer side capped at 2,400 pixels.

### How Pi reads it

`read_pages` returns an accepted page's structure Markdown in place of its text
layer and marks it `source: "structure"`; other pages are `source: "text_layer"`.
Candidates and `needs_review` pages never reach Pi. On the 40 measured pages, the
stored Markdown was 1.12 times as long as the text layer (prose 0.96, tables 1.49,
formulas 1.40). Sending both would be 2.12 times as long and would fit about half
as many pages in one 24,000-character call. The Markdown keeps footnotes and
formula numbers; it drops only running headers, footers and page numbers, which
answers do not need because citations use PDF page indices. `search_book` still
searches the text layer.

### Measured on this Mac

40 pages from a personal library were measured on an M5 Pro with 48 GB (macOS 26.6.2):
Korean scanned prose, tables and formulas (10 pages each) and 10 born-digital
Korean pages whose embedded text is the ground truth.

| Engine (sequential requests) | Prose CER (digital, median) | Table grids exact | Formula pages parsed (KaTeX) | s/page median (contended) | Peak memory |
| --- | --- | --- | --- | --- | --- |
| **PaddleOCR-VL-1.6 + PP-DocLayoutV3** (mlx-vlm 0.7.6 server) | **0.25%** | **21/21** | 76/79 | 17.5 (range 7.1-31.3) | server 4.5 GB + client 1.1 GB |
| Apple Vision `RecognizeDocumentsRequest` | 1.15% | 20/21 | no formulas | 0.6 | 0.24 GB |
| GLM-OCR (mlx-vlm) | 10.24% (Korean final consonants misread) | 18/21 | 101/101 | 19.9 | server 5.2 GB + client 1.6 GB |

Other sessions loaded the machine during the timing, so the seconds are an upper
bound. A quiet stretch gave about 6 s per page for Paddle. A 300-page book takes
30 to 90 minutes. Starting the server and loading the pipeline takes about 9 s; the
first run after installing took about 2 minutes, with the model already downloaded.

### Pitfalls

- mlx-vlm 0.7.6 corrupts output under concurrent requests: pages are cut at the
  token limit, repeat text or lose text. The PaddleOCR SDK default is concurrent,
  so Bookside fixes `vl_rec_max_concurrency=1`. Two sequential runs gave identical
  output on 40 of 40 pages. Do not run two `structure` commands at once; each one
  starts its own server.
- Output depends on the rendered pixels. Bookside renders with pdfium; the
  measurement above rendered with MuPDF. On three born-digital pages run again
  through the CLI, every block matched except one dense table, whose cell values
  were the same but whose line breaks inside cells were gone.
- Guards mark a page `needs_review`: text in which a 4-120 character unit repeats
  five or more times over at least 200 characters, a request that the server log
  reports as stopped at the token limit, or a formula with unbalanced braces or
  unmatched `\begin`/`\end`. On the 40 measured pages they flagged one page, where
  three matrices were misread. Repeated matrix entries such as `\boxed{0}` are content
  and are not flagged.
- Paddle writes a line break inside a table cell as the two characters `\n`.
  Bookside turns it into `<br>` between two ordinary characters outside math. It
  keeps a `\n` next to a quote, backtick or backslash, because a programming
  book's table may show the escape sequence itself.
- Paddle leaves formula numbers, footnotes, headers and footers out of its Markdown.
  Bookside puts formula numbers and footnotes back and keeps all of them as blocks.
- Paddle's line-level `spotting` boxes drift on some pages, so Bookside does not
  use them. Positions inside text come from the Apple Vision text layer.
- The 4-bit model has not been measured. Measure it before making it the default.
- If the CLI is force-killed, the helper notices at its next page and stops its
  server. If the helper itself is force-killed, the server keeps running; find it
  with `pgrep -fl mlx_vlm.server`.

| Symptom | Next check |
| --- | --- |
| Engine not found | Run `structure-status` and check its `engine` paths; set the two variables above. |
| Server does not become ready | Check the server log named in the error; the first run downloads the model. |
| Many `needs_review` pages | Read the reasons in `structure-status`; check that nothing else sends requests to mlx-vlm. |
| Results disappeared | Check `otherVersions`: a different PDF version is active. |
