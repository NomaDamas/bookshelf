# OCR a library book

OCR writes a new searchable PDF beside the source and leaves the original untouched. Accepting the copy keeps the book ID, notebook, highlights, bookmarks and progress.

## Before starting

1. Confirm the user wants OCR for this book. It writes a new file into their library folder.
2. Run `bookside-cli doctor`. If `ocrmypdf` is `not found`, install the engine and stop until it is available:
    - `uv tool install ocrmypdf --with "ocrmypdf-appleocr @ git+https://github.com/mkyt/OCRmyPDF-AppleOCR.git"`
    - `brew install ghostscript`
    - `brew install poppler` for the second text check. Without it every result needs manual review.
3. Make sure the source PDF is downloaded locally (see "When `read` fails" in SKILL.md).

## Run it for review

Use the review flow so the user decides what gets attached:

```sh
bookside-cli ocr <id> --review-only > <new-result>.json
```

- `--language` defaults to `kor`. Use `eng`, `jpn`, `chi_sim`, `chi_tra` or `und` to match the book.
- Add `--redo` when the PDF already has a poor text layer that should be replaced. Without it, only pages missing text are recognized.
- Output goes to the next free `<title>_ocr.pdf` beside the source. `--output <new.pdf>` picks another path; existing files are refused.
- Progress goes to stderr. Large books take minutes, so run it in the background and report when it finishes.
- Use a new result file name for each run; the JSON is what `ocr-accept` reads.

## Review and attach

1. Read the result JSON: output path, quality findings and the report location.
2. Compare a few pages. `bookside-cli read <id> <page>` still reads the current PDF; read the candidate with `pdftotext -f <page> -l <page> "<output.pdf>" -`.
3. Show the user the findings. Attach only when they approve: `bookside-cli ocr-accept <new-result>.json`.
4. To go back to the original PDF later: `bookside-cli ocr-original <id>`. OCR copies and notes stay.

Without `--review-only`, the CLI attaches a result automatically when it passes the quality checks and keeps it unattached when a check needs review.
