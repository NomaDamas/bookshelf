# Getting started

[Documentation](README.md) / Getting started

## Requirements

| Requirement | Details |
| --- | --- |
| macOS | Deployment target: 14. Native frameworks make this a macOS application. |
| Xcode / Swift | `Package.swift` declares Swift tools 6.0 and Swift language mode 5. Use a compatible full Xcode installation. |
| Python 3 | Used by the token and dependency-notice build helpers. |
| Git and network access | Needed to clone and fetch Swift packages on the first build. |
| OCR dependencies | Optional; see [OCR setup](04-ocr.md#install-the-optional-engine). |

The verified environment is macOS 26.6.2, Xcode 27, Swift 6.4, and Apple Silicon.
The tools declaration and deployment target are build settings, not proof of an
end-to-end run on Swift 6.0, macOS 14/15, or an Intel Mac.

## Build and open

```sh
git clone https://github.com/NomaDamas/bookshelf.git
cd bookshelf
./scripts/build-app.sh
./scripts/open-app.command
```

The build creates `dist/Bookshelf.app`, checks generated design tokens, copies the
OCR helper and dependency notices, and verifies an ad-hoc signature. The bundle
contains `Bookshelf` and `bookshelf-cli` in `Contents/MacOS/`.

If `DEVELOPER_DIR` is unset, the build script prefers
`/Applications/Xcode.app/Contents/Developer` when it exists; otherwise the selected
developer directory is used. Check `xcode-select -p`, `xcodebuild -version`, and
`swift --version` if the build reports SDK or compiler errors. Set `DEVELOPER_DIR`
to your actual Xcode developer directory to override it without changing the
system-wide selection. Use the same toolchain for build and tests.

The repository has no published binary release or notarized installer. Build the
source locally; there is no release download step to follow.

## Read your first PDF

1. Choose **PDF 추가…** (`Command-O`) for PDFs, or **폴더 추가…**
   (`Command-Shift-O`) to scan a folder recursively.
2. Select a book in the sidebar. Download cloud-only files in Finder first.
3. Read **원문** (original PDF) or switch to **텍스트** (extracted text).
4. Write in **메모** (notebook). Wait for **저장됨** (saved).
5. Quit and reopen. Select the book to resume its saved page and notes.

PDFs stay at their original paths. The first folder below an imported root becomes
the category; you do not need the maintainer's folder layout. Only PDFs are imported.
Scans skip hidden folders, symlinks, and [documented exclusions](07-data-and-privacy.md#import-and-file-identity).

## Install and update locally

```sh
./scripts/install-local.command
open "$HOME/Applications/Bookshelf.app"
```

The installer copies the build and checks its signature. It builds only when the
local executable is missing. For an update, quit the app, update your checkout,
run `./scripts/build-app.sh` explicitly, then run the installer again. Installing
an existing `dist/` bundle alone does not rebuild changed source.

Library data is outside the bundle, so replacing the app preserves the database.
See [backup and restore](07-data-and-privacy.md#backup-and-restore) before testing
changes that affect stored data.

## Try an isolated sample library

From the repository root after building:

```sh
mkdir -p .runtime/demo
swift scripts/make-fixture.swift "$PWD/.runtime/demo/sample.pdf" 2
export BOOKSHELF_DATA_DIR="$PWD/.runtime/demo/data"
dist/Bookshelf.app/Contents/MacOS/bookshelf-cli import "$PWD/.runtime/demo/sample.pdf"
dist/Bookshelf.app/Contents/MacOS/Bookshelf
```

This launches the executable directly so it inherits `BOOKSHELF_DATA_DIR`. Quit any
development instance first. A Finder/LaunchServices launch does not reliably inherit
terminal variables. The sample is a two-page raster PDF: reading and notes work
immediately; text selection/search require [OCR](04-ocr.md).

The variable also applies to later commands in that terminal. After closing the
sample app, run `unset BOOKSHELF_DATA_DIR` to use your normal library again.
The separate database does not isolate macOS appearance/window preferences.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| Swift or SDK error | Check the active toolchain above; set `DEVELOPER_DIR` to a compatible full Xcode installation. |
| Stale token error | Run `python3 scripts/generate-reader-tokens.py --check`. Regenerate only after intentional token edits; see [development](06-development.md). |
| No selectable text | The PDF may be image-only. See [OCR](04-ocr.md). |
| Cloud icon or unavailable PDF | Download the file in Finder. Listing a placeholder does not download it. |
| Missing PDFs after folder import | Check excluded folder names, symlinks, extensions, and permissions. Try explicitly importing one PDF. |
| App and CLI show different books | Compare `BOOKSHELF_DATA_DIR`; run CLI `doctor`. |
| New code is not visible | Rebuild before reopening/reinstalling. Open/install helpers reuse an existing bundle. |
| OCR engine not found | Use [engine troubleshooting](04-ocr.md#engine-discovery-and-troubleshooting). |

For a reproducible failure, open a [bug report](https://github.com/NomaDamas/bookshelf/issues/new?template=bug_report.yml)
with the command, toolchain, and a synthetic example. Remove private paths/text from logs.
