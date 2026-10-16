# Native verification

Aside design baseline verified on macOS 26.6.2 / Apple Silicon, 2026-10-16, in commit `b48c9a5`. Later loading and current-book changes are recorded in [PERFORMANCE.md](PERFORMANCE.md). The source remains compatible with the macOS 14 deployment target; earlier macOS versions were not exercised.

## Scope and evidence

The reference package's `validate aside-glass --ready` check passed with 90 source tokens. That check verifies reference records, not native appearance. The app was separately built, ad-hoc signed, launched and operated through macOS Accessibility and real keyboard/paste events.

The screenshots below contain a two-page authored fixture. The first version deliberately has character-spaced OCR; a later screenshot shows the same book after accepting an improved OCR copy. This is test data, not a customer's book or notebook.

| Check | Result | Evidence |
| --- | --- | --- |
| Native original/text reading surfaces and notebook | Pass | [Light reader](evidence/reader-light.png), [text reader](evidence/reader-text-light.png), [dark reader](evidence/reader-dark.png) |
| Light/dark switching in settings | Pass | [Light settings](evidence/settings-light.png), [dark settings](evidence/settings-dark.png) |
| Wide and narrow layouts | Pass at 1380x900 and 1000x700 points | [Narrow light](evidence/reader-narrow.png), [narrow dark](evidence/reader-narrow-dark.png) |
| Page turning in PDF and text modes | Pass for left/right keys | [Native checks](evidence/native-checks.json) |
| Editing keys stay in notes; autosave and relaunch | Pass | [Native checks](evidence/native-checks.json) |
| Whitespace-insensitive search and clearing results | Pass with actual Korean input | [Search](evidence/search-light.png), [native checks](evidence/native-checks.json) |
| Empty excerpt panel | Visually checked | [Empty excerpts](evidence/quotes-empty-light.png) |
| OCR review, a screen absent from the source reference | Pass | [Text comparison](evidence/ocr-review-dark.png), [PDF comparison](evidence/ocr-review-pdf-dark.png) |
| OCR page input Return does not accept; literal phrase; keep/accept preserve notes and page | Pass | [Native checks](evidence/native-checks.json) |
| Disabled last-page button and input focus ring | Visually checked | [Reader](evidence/reader-light.png), [OCR phrase field](evidence/ocr-review-dark.png) |
| Core regression suite | 15 tests, 0 failures | `swift test` |
| Release build, token generation, Python lint and diff whitespace | Pass | `build-app.sh`, `generate-reader-tokens.py --check`, Ruff, `git diff --check` |

## Installed app

The verified release was installed in the user's Applications folder and reopened. Its executable SHA-256 matches the release build (`95efe54b2438318363761b4cb92e35d05add3573a59f7a2e89df7ce10b0a9bc0`). The existing reading page and text mode were restored. Notebook, highlight and bookmark table hashes were unchanged across installation. Private library content and the installed-app screenshot are kept out of this repository's evidence.

## Boundaries

Native materials and controls intentionally differ from the web reference's pixel values. Their composition belongs to AppKit, while the notebook and book content remain opaque. Source token/provenance hashes are retained in `reference.json`.

Reduced-transparency, increased-contrast and reduced-motion branches were inspected in code; the user's global accessibility settings were not changed for this run. Full VoiceOver navigation, every hover state, OCR cancellation/error presentation and macOS 14/15 rendering were not re-exercised in this design pass. Existing OCR integration checks are documented in the [development guide](../../docs/06-development.md#ocr-and-mcp-integration-checks).

The legacy web prototype and the ongoing library maintenance worker were left intact. The worker uses its own fixed CLI snapshot; installing the reader does not replace that executable. This verification does not mean the library-wide OCR batch has finished.
