# Advanced PDF text-layer maintenance

[Documentation](README.md) / PDF maintenance

These scripts serve an advanced audit/repair workflow. Most readers should use
[the app's OCR review](04-ocr.md) instead. Unlike the app's new-copy OCR workflow,
**applying a spacing repair replaces a PDF in place after backing it up**.

## Scope

The optional scripts below audit and repair one specific failure mode in some AppleOCR PDFs:
standalone invisible spaces inserted between Korean characters. They do not rewrite grammar,
run a language model, or replace recognized letters. They require Poppler and a Python environment
with `pikepdf` and Pillow, in addition to the Swift/PDFKit probe. Use Python 3.11
or newer for this workflow: validation, application, and batch maintenance all
use `hashlib.file_digest`.

- `pdf-text-probe.swift`: extract PDFKit text/geometry for selected pages or `all` pages.
- `audit-text-layer.py`: compare sampled PDFKit/Poppler text. A clean sample is not proof that every page is accurate.
- `repair-ocr-spacing.py`: propose removal of separately positioned invisible GlyphLessFont spaces only where a complete, unambiguous source-text match supports it. Without `--output`, it is a dry run.
- `validate-text-layer.py`: compare all PDFKit/Poppler non-whitespace text, page geometry, image stream bytes, and chosen rendered pages.
- `stage-spacing-repairs.py` / `finalize-spacing-repairs.py`: prepare candidates and restore any pages where either extractor's reading order changes. Unsupported or ambiguous text remains untouched.
- `apply-spacing-repairs.py`: verify source/candidate hashes, back up originals, then replace files atomically. A dry run is the default; `--apply` is explicit.
- `restore-text-layer-backup.py`: restore originals only if the current PDF still matches the recorded repair; keep a copy of the repaired file too.

The argparse-based tools listed above support `--help`. The standalone restore tool accepts its backup directory directly; it is not a dry-run command.
Keep the virtual environment's Python executable path when passing `--python`; resolving its symlink
to a base interpreter bypasses the environment's installed dependencies.
Placeholder downloads require an explicit file list and `--download-placeholders`; normal auditing
does not download them. A FileProvider timeout leaves the PDF unmodified and its audit incomplete.
Do not apply a candidate with a failed validation report. These tools do not edit the global OCR skill
or an installed third-party package. The app continues to use explicit Apple Vision `accurate` mode.

## Workflow and command contracts

Inspect each tool's `--help` and use an isolated copy before operating on a library.
Do not supply a guessed cloud materializer: the repository does not bundle one.

| Tool | Inputs and mutation boundary |
| --- | --- |
| `audit-text-layer.py` | `root output --probe <binary> --materializer <executable>`; writes reports, default sampling. `--all-pages` inspects all pages. |
| `repair-ocr-spacing.py` | `input --report <json>`; proposes changes, writes a new PDF only with `--output`. |
| `validate-text-layer.py` | `original repaired --probe <binary> --report <json>`; compares candidates. `--render-pages` selects visual checks. |
| `stage-spacing-repairs.py` | `audit output --python <interpreter> --probe <binary>`; creates staged candidates. |
| `finalize-spacing-repairs.py` | `audit stage output --probe <binary>`; restores pages with reading-order changes into final candidates. |
| `apply-spacing-repairs.py` | `manifest --library-root <dir> --backup-dir <dir>`; previews by default, backs up and replaces with `--apply`. |
| `restore-text-layer-backup.py` | `<backup-directory>`; restores immediately if recorded hashes match, retaining the repaired file. |
| `maintain-pdf-library.py` | Requires audit, library, output, backup, CLI, probe, and data directories; dry-run by default. `--apply` enables backed-up repairs/OCR attachment. |
| `report-pdf-maintenance.py` | `<job-directory> [--watch]`; writes status/report artifacts without modifying the library. |
| `restore-library-maintenance.py` | `<job-directory>`; preview by default. `--apply --stop-running` stops the job and restores selections/backups, preserving OCR copies/notes. |
| `finish-pdf-maintenance.py` | `<job-directory>`; job finalization helper with side effects, not a generic health check. Inspect its source and job inputs first. |

Compile the PDFKit probe from the repository:

```sh
mkdir -p .runtime/tools
swiftc scripts/pdf-text-probe.swift -o .runtime/tools/pdf-text-probe
```

The audit requires an external `--materializer` and invokes it for resident files
as well as explicitly requested downloads. Its command contract is
`<executable> <pdf-path> --wait <seconds>`; a nonzero exit makes the audit incomplete.
This helper is **not included in the repository**, so the full-library audit is not
a standalone setup path. Supply a compatible helper before running it.
Placeholder downloads also require an explicit `--file-list` and
`--download-placeholders`; default auditing skips cloud-only files.

The maintenance runner expects the audit's artifacts, a fixed built CLI, and an
explicit data directory. Inspect the plan, candidate validation, hashes, and backups
before any `--apply`. Keep that CLI snapshot unchanged while a job uses it.
A report showing incomplete/unsupported pages is not proof of a clean library.
