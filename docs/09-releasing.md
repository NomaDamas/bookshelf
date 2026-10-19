# Versioning and macOS releases

[Documentation](README.md) / Releases

## Product identity and version source

| Surface | Identity |
| --- | --- |
| GitHub | `NomaDamas/bookside` |
| App bundle | `Bookside.app` |
| Bundle identifier | `org.nomadamas.bookside` |
| Swift package / core library | `Bookside` / `BookshelfCore` |
| CLI / MCP server name | `bookside-cli` / `bookside` |
| Deep links | `bookside://book/<id>?page=<number>` |

[`AppMetadata.json`](../Sources/BookshelfCore/Resources/AppMetadata.json) is the
single product/version source. The app, CLI `--version`/`doctor`, and MCP server
read the packaged resource. `scripts/app-metadata.py` generates `Resources/Info.plist`
and checks its agreement with the metadata and the Swift deployment target.

Marketing versions use numeric `MAJOR.MINOR.PATCH`; Git tags use `vMAJOR.MINOR.PATCH`.
The positive build number increases whenever the version setter advances the version.
GitHub's prerelease flag is separate from the numeric macOS bundle version.

```sh
python3 scripts/app-metadata.py version
python3 scripts/app-metadata.py check
```

For a future version, choose the appropriate number and run, for example:

```sh
python3 scripts/app-metadata.py set 0.2.1
```

The setter refuses equal/older versions and regenerates the plist. Review both
changed files, update [CHANGELOG.md](../CHANGELOG.md), and submit a release-preparation
PR. Never edit the version independently in Swift, Info.plist, a filename, or MCP.

## Build a local DMG

From a clean checkout of the source you want to distribute:

```sh
python3 scripts/release.py package
```

The command builds release configuration, checks the app's version/identity and
signature, packages it, mounts the DMG read-only, copies its app to a temporary
installation, and executes the copied CLI with an isolated data directory.
Packaging first completes an uncompressed filesystem image, then converts it to
LZMA-compressed ULMO with one compression worker (macOS 10.15 or later can open it).
Direct folder-to-UDZO creation produced invalid block offsets on Apple Silicon CI;
the final image must still pass `hdiutil verify`.
It also checks the `/Applications` drag-and-drop shortcut and required notices.
A negative probe temporarily withholds the copied app's resource bundle and requires
CLI failure, then restores it and verifies the signature again. This prevents a
build-machine `.build` cache from masking incomplete distribution assets. Resources
are resolved inside the app for both flat and macOS-style SwiftPM bundle layouts.
Temporary mounts are detached when verification exits.

On Apple Silicon, output is:

```text
dist/release/
  Bookside-0.1.0-macos-arm64.dmg
  Bookside-0.1.0-macos-arm64.dmg.sha256
  Bookside-0.1.0-macos-arm64.json
  Bookside-0.1.0-macos-arm64.dSYMs.zip
```

Intel builds use `x86_64`. Each build packages the host architecture; these are
separate native artifacts, not a universal binary. The JSON records the source
revision, dirty-source flag, minimum macOS, signature mode, notarization status, and
the symbols file. The app's executables are stripped; the `.dSYMs.zip` holds their
debug symbols for crash reports and is not needed to install or run the app.
A local build from edited source is marked dirty and is not an exact tagged release.

The packager refuses to overwrite existing outputs. Use a new `--output` directory
for another candidate. `--skip-build` reuses an already-built release bundle and
checks its version/commit and that `dist/dSYMs` matches its executables; only use it
when that build matches your working source.

To verify a trusted candidate again:

```sh
python3 scripts/release.py verify dist/release/Bookside-0.1.0-macos-arm64.dmg --arch arm64
```

This executes code from the supplied app. Use it for your own or otherwise trusted
artifacts, not as a malware scanner for an unknown DMG.

## Signing and notarization

By default, local and GitHub CI builds use **ad-hoc signing**. This checks the bundle's
integrity but does not establish a Developer ID identity or Apple notarization.
Downloaded previews may be blocked by Gatekeeper. The workflows create draft
prereleases and describe this limitation in the generated notes.

For a properly credentialed local release, set `BOOKSIDE_SIGNING_IDENTITY` to your
full **Developer ID Application:** identity and `BOOKSIDE_NOTARY_PROFILE` to an
existing `notarytool` Keychain profile, then run:

```sh
python3 scripts/release.py package --notarize
```

The build signs nested executables and the app with hardened runtime and a timestamp.
The packager signs the DMG, submits it with `xcrun notarytool`, staples the accepted
ticket, validates stapling, and only then calculates the final checksum.
An Apple Development certificate is not a distribution certificate. Notarization
needs your own Apple developer credentials; none are bundled or installed by these scripts.

The committed workflows intentionally contain no certificate import or signing
secrets. Use your secret-management process to provision credentials before adding
an automated signing environment. Do not put private keys, passwords, or certificate
exports in this repository or in shell command logs.

Apple's [notarization guide](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
describes certificate and hardened-runtime requirements. A configured notarization
path is not proof that a candidate was notarized; check its JSON and actual ticket.

## CI and tag-triggered drafts

[`ci.yml`](../.github/workflows/ci.yml) runs on pull requests, pushes to `main`, and
manual dispatch. On Apple Silicon (`macos-26`) and Intel (`macos-26-intel`), a test job
runs metadata/token checks and XCTest while a separate packaging job runs the release
build, DMG creation, and copied-CLI verification, so both finish in parallel. A Linux job
runs the bridge typecheck and tests. Jobs cache dependency sources (SwiftPM checkouts and
the pnpm store) but never build products, so every build starts clean. Packaging jobs
upload short-lived workflow artifacts. OCR integration and native GUI interaction
are separate local checks; passing these jobs does not prove either one.
If packaging fails after creating a DMG, CI retains it for one day as a
`Failed-DMG-diagnostic-*` artifact. These files are for diagnosis, not distribution;
retaining them does not change the failed check to a pass.

[`release.yml`](../.github/workflows/release.yml) runs only for pushed `v*` tags:

1. Require the tag to equal the metadata version and point to the checked-out commit.
2. Require that commit to belong to `origin/main` history and the checkout to be clean.
3. Test and package both architectures.
4. Upload each DMG, checksum, metadata file, and symbols zip.
5. Create a **draft prerelease**, using the matching changelog section. An existing
   release causes a failure instead of silently replacing its assets.

The build jobs have read-only repository permissions. Only the draft-creation job
has `contents: write`. Actions are pinned to immutable commit SHAs. The workflow
uses the standard hosted runners, not the paid `-large` / `-xlarge` labels.

After merging the version-preparation PR and verifying CI, a maintainer can create
and push an annotated tag. For the initial version:

```sh
git fetch origin
git tag -a v0.1.0 origin/main -m "Bookside 0.1.0"
git push origin v0.1.0
```

This is an external release action; it is not performed by a local build or ordinary
PR merge. Verify the tag and final main commit first. Open the resulting draft,
review assets/checksums, record the actual signing status and known issues, then
publish when approved. Never move a published tag or replace its assets; release
a new version instead. A failed workflow can leave a draft that must be inspected
before retrying publication.

## Homebrew distribution

The [Bookside tap](https://github.com/NomaDamas/homebrew-bookside) owns
`Casks/bookside.rb`. It downloads the published DMGs with architecture-specific
SHA-256 checksums; it does not rebuild the app or change its signing status.
Do not duplicate the cask in this repository.

After publishing and checking a new GitHub Release, open a version update PR in
the tap. Its README documents the version/checksum changes and macOS installation
checks. Review the version, both checksums, the version-specific preview exception,
and the signing caveat against the release's manifests before merging the update.

Tap livecheck includes published numeric preview tags. It detects available
versions; it does not publish a cask update automatically. Users receive a merged
cask update through `brew update` and `brew upgrade --cask nomadamas/bookside/bookside`.

## Install, update, and compatibility

Open the DMG and drag `Bookside.app` to Applications, or use the local installer
for `~/Applications`. Quit the old app first. Metadata/CLI verification does not
prove an interactive Gatekeeper launch on another person's Mac.

The bundle ID `org.nomadamas.bookside` succeeds the pre-rename
`org.nomadamas.bookshelf` and the older `org.bookshelf.reader`. New libraries live
at `~/Library/Application Support/Bookside`. While that folder does not exist and
`Application Support/Bookshelf/library.sqlite3` does, Bookside keeps using the old
folder in place, so notes and PDF identities do not move. The app copies only a
valid legacy appearance preference when no new choice exists. It leaves the old
preference domains intact. The local installer recognizes all three bundle IDs; it
refuses to overwrite an unrelated app. Because the app name changed, installing
`Bookside.app` does not replace `Bookshelf.app`; the local installer reports a
remaining pre-rename copy so it can be removed after the library is confirmed.

When you change the installation location, inspect existing MCP registrations; the
registration helper's discovery and pre-rename handling are in [CLI/MCP](03-cli-and-mcp.md#register-mcp).
