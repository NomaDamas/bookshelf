# Getting started

[Documentation](README.md) / Getting started

## Install with Homebrew

With a current [Homebrew](https://brew.sh/) installation:

```sh
brew install --cask nomadamas/bookside/bookside
```

The [NomaDamas tap](https://github.com/NomaDamas/homebrew-bookside) selects the
Apple Silicon or Intel release, checks its SHA-256, and installs `Bookside.app`
in `/Applications` by default. It also links the app's `bookside-cli` into the
Homebrew `bin` directory. The fully qualified command adds the tap automatically;
on newer Homebrew versions, it establishes trust for this cask specifically.

This installs the same **ad-hoc signed, unnotarized developer preview** as the DMG
below. Homebrew keeps quarantine protections; follow the first-launch guidance
below if macOS blocks opening it. Until macOS allows the app, `bookside-cli` can wait
at a Gatekeeper prompt instead of returning
([#24](https://github.com/NomaDamas/bookside/issues/24)). OCR remains an optional,
separate installation.

Quit Bookside before updating:

```sh
brew update
brew upgrade --cask nomadamas/bookside/bookside
```

To remove the app and the CLI link, run:

```sh
brew uninstall --cask nomadamas/bookside/bookside
```

This leaves PDFs, notes, and reading history intact. The cask does not define a
`zap` operation that removes library data.

If you installed the `bookshelf` cask before the rename, quit Bookshelf and move it
to `bookside`:

```sh
brew update
brew trust --cask nomadamas/bookshelf/bookside
brew migrate --cask bookshelf
brew upgrade --cask bookside
```

Homebrew trusts casks by name, so the new name needs its own `trust`. See
[Coming from Bookshelf](https://github.com/NomaDamas/homebrew-bookside#coming-from-bookshelf)
in the tap for what each step does. The library stays where it is.

If you installed Bookside manually, check `/Applications` and `~/Applications`
before switching. Homebrew refuses to overwrite a different existing app; keep
the old copy until you have verified the new installation. If both locations
contain an app, open the intended one explicitly. For existing MCP registrations,
check that their executable paths still point to the intended app; see
[CLI/MCP setup](03-cli-and-mcp.md).

## Install the developer preview

The [v0.3.0 release](https://github.com/NomaDamas/bookside/releases/tag/v0.3.0)
provides separate DMGs for Apple Silicon (`arm64`) and Intel (`x86_64`). The deployment
target is macOS 14. Downloaded apps do not require Xcode or Python; optional OCR
has [separate dependencies](04-ocr.md#install-the-optional-engine). The learning chat needs
Node.js 22.19 or later and the official Claude Code or Codex executable.

1. Download the DMG for your Mac and its matching `.dmg.sha256` file from the release.
2. In that download folder, verify the checksum. For Apple Silicon:

    ```sh
    shasum -a 256 -c Bookside-0.3.0-macos-arm64.dmg.sha256
    ```

    Use the `x86_64` filename for Intel. Continue only if the result is `OK`.
3. Quit any existing Bookside, open the DMG, and drag `Bookside.app` to Applications.
4. Open Bookside from Applications. Replacing the app preserves the library data
   stored outside it; see [backup and restore](07-data-and-privacy.md#backup-and-restore).

These developer previews are **ad-hoc signed, not Developer ID signed or notarized
by Apple**. A checksum verifies the downloaded bytes, not Apple approval. Gatekeeper
may block the first launch. If you trust this release, follow Apple's
[instructions for opening an unnotarized app](https://support.apple.com/en-us/102445).
You can also build from source below.

Both architectures are built and checked by executing the copied CLI in CI. Native
UI verification has used Apple Silicon and macOS 26; older macOS and Intel UI
compatibility have not been verified end to end.

## Source build requirements

| Requirement | Details |
| --- | --- |
| macOS | Deployment target: 14. Native frameworks make this a macOS application. |
| Xcode / Swift | `Package.swift` declares Swift tools 6.0 and Swift language mode 5. Use a compatible full Xcode installation, version 26 or later: its `actool` compiles the Icon Composer app icon. |
| Python 3 | Used by the token and dependency-notice build helpers. |
| Node.js, pnpm, Bun | Node.js 22.19 or later, pnpm and Bun build the learning chat bridge that every build includes. |
| Git and network access | Needed to clone and fetch Swift packages on the first build. |
| OCR dependencies | Optional; see [OCR setup](04-ocr.md#install-the-optional-engine). |

The verified environment is macOS 26.6.2, Xcode 27, Swift 6.4, and Apple Silicon.
The tools declaration and deployment target are build settings, not proof of an
end-to-end run on Swift 6.0, macOS 14/15, or an Intel Mac.

## Build and open

```sh
git clone https://github.com/NomaDamas/bookside.git
cd bookside
./scripts/build-app.sh
./scripts/open-app.command
```

The build creates `dist/Bookside.app`, checks generated design tokens, copies the
OCR helper and dependency notices, and verifies an ad-hoc signature. The bundle
contains `Bookside` and `bookside-cli` in `Contents/MacOS/`. A release build also
writes the executables' debug symbols to `dist/dSYMs/`.

If `DEVELOPER_DIR` is unset, the build script prefers
`/Applications/Xcode.app/Contents/Developer` when it exists; otherwise the selected
developer directory is used. Check `xcode-select -p`, `xcodebuild -version`, and
`swift --version` if the build reports SDK or compiler errors. Set `DEVELOPER_DIR`
to your actual Xcode developer directory to override it without changing the
system-wide selection. Use the same toolchain for build and tests.

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
open "$HOME/Applications/Bookside.app"
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
export BOOKSIDE_DATA_DIR="$PWD/.runtime/demo/data"
dist/Bookside.app/Contents/MacOS/bookside-cli import "$PWD/.runtime/demo/sample.pdf"
dist/Bookside.app/Contents/MacOS/Bookside
```

This launches the executable directly so it inherits `BOOKSIDE_DATA_DIR`. Quit any
development instance first. A Finder/LaunchServices launch does not reliably inherit
terminal variables. The sample is a two-page raster PDF: reading and notes work
immediately; text selection/search require [OCR](04-ocr.md).

The variable also applies to later commands in that terminal. After closing the
sample app, run `unset BOOKSIDE_DATA_DIR` to use your normal library again.
The separate database does not isolate macOS appearance/window preferences.

## Troubleshooting

| Symptom | Check or action |
| --- | --- |
| Swift or SDK error | Check the active toolchain above; set `DEVELOPER_DIR` to a compatible full Xcode installation. |
| Stale token error | Run `python3 scripts/generate-reader-tokens.py --check`. Regenerate only after intentional token edits; see [development](06-development.md). |
| No selectable text | The PDF may be image-only. See [OCR](04-ocr.md). |
| Cloud icon or unavailable PDF | Download the file in Finder. Listing a placeholder does not download it. |
| Missing PDFs after folder import | Check excluded folder names, symlinks, extensions, and permissions. Try explicitly importing one PDF. |
| App and CLI show different books | Compare `BOOKSIDE_DATA_DIR`; run CLI `doctor`. |
| New code is not visible | Rebuild before reopening/reinstalling. Open/install helpers reuse an existing bundle. |
| OCR engine not found | Use [engine troubleshooting](04-ocr.md#engine-discovery-and-troubleshooting). |

For a reproducible failure, open a [bug report](https://github.com/NomaDamas/bookside/issues/new?template=bug_report.yml)
with the command, toolchain, and a synthetic example. Remove private paths/text from logs.
