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

Reduced-transparency, increased-contrast and reduced-motion branches were inspected in code; the user's global accessibility settings were not changed for this run. Full VoiceOver navigation, every hover state, OCR cancellation/error presentation and macOS 14/15 rendering were not re-exercised in this design pass. Existing OCR integration checks remain documented in the main README.

The legacy web prototype and the ongoing library maintenance worker were left intact. The worker uses its own fixed CLI snapshot; installing the reader does not replace that executable. This verification does not mean the library-wide OCR batch has finished.


## Reading history and sorting

Verified on the same macOS environment, 2026-10-16. The three reading shelves now share
persistent sorting, completion history and red note-count badges. Native checks used four
authored PDFs with 0, 3, 5 and over 99 notes, plus one- and four-read-through histories.

- `swift test`: 34 tests passed, including read-through persistence, idempotent completion,
  undo, OCR identity, legacy membership migration, note item counts, note-save conflicts,
  reread page reset and sort preference persistence.
- [17 native behavior checks](evidence/reading-history-checks.json): sorting and direction
  across categories/relaunch, dated history, fifth read-through and undo, review without
  starting a reread, note-badge navigation and count updates after deletion.
- [Light](evidence/reading-history-light.png), [dark](evidence/reading-history-dark.png),
  [1000x700-point window](evidence/reading-history-narrow.png) and
  [history](evidence/reading-history-dates.png) were visually inspected. Exact counts are
  exposed through Accessibility, while the displayed badge caps at 99+.
- [Real-library-copy migration](evidence/reading-history-migration.json): all 711 books,
  note/highlight/bookmark hashes and saved positions were preserved. Twelve books retained
  their reading status; past completions were not inferred.
- [Installed app](evidence/reading-history-installation.json): release build and installed
  executable match. The running app was closed normally, reopened after installation,
  and its active book/page and all note/highlight/bookmark records were preserved.

Full VoiceOver navigation and older macOS versions were not tested in this change.
Native automation waited for asynchronous menu actions before checking database state.
Private backup data and installed-app captures remain in the ignored runtime directory.
