# Reader loading and current-book visibility

The reader previously rebuilt an already-open PDF, scanned every text page on each selection, and hid the library after a book opened. The library also rendered expensive rows eagerly, including iCloud status queries on the main thread. These costs made switching books slow and removed the visual context of the selected book.

## Changes

- The library uses a lazy native scroll view. Only visible rows need views/covers, and local row indicators use filesystem metadata; opening a PDF still performs the complete availability check.
- Uncached cover generation is serialized at utility priority, with cancellation checks and a small image cache.
- The reader reuses at most two unchanged PDF documents, bounded by 512 MiB of source-file sizes. Memory-pressure notifications clear retained cache entries. This is a retention bound, not a total process-RAM guarantee; the active PDF and PDFKit rendering resources also consume memory.
- Cache identity includes path, filesystem identity, file size and nanosecond modification/change times. In-place replacement and OCR version changes cause a fresh read.
- Full text inspection runs after the initial reading surface can render, cancels between pages when the user switches books, and persists its result for the exact file version. Known unchanged files do not need another whole-book scan.
- Highlight redraw visits only pages previously touched by the reader. Cached documents do not restore deleted highlights, and late events from an old PDF view cannot change the current book's reading position.
- Opening a book preserves the chosen sidebar visibility. A persistent reading header shows the current title. The sidebar marks the row as reading, shows the live page, and can clear a filter and scroll directly to the current book.

## Measured result

The native app was operated in one window against two downloaded books and a copy of the real library database. The same OCR maintenance job continued in the background. Timings start at book selection and end after the PDF view has received the document and navigated to the reading page. They do not measure GPU presentation or iCloud download time.

| Scenario | Before | After |
| --- | ---: | ---: |
| First book after process startup | 2,009 ms | 1,155 ms |
| Four alternating book selections, median | 2,560 ms | 96 ms |
| Alternating selections, observed range | 2,326-2,831 ms | 90-125 ms |

The four-switch median decreased by 96.3% in this local sample. The OS file cache was warm; these numbers are not a guarantee for every PDF or device. The original full scan of the 630-page PDF took 1.7-1.9 seconds. The scan remains available when a file changes; repeated scans are avoided at the reader call site.

[Raw timing summary](evidence/reader-performance.json)

Temporary tagged probes were removed from production source after measurement. Development traces and the sampled stacks remain in the ignored `.runtime/performance-qa/` directory. An earlier URL-opening experiment created additional windows and was excluded from this comparison; the final measurements use sidebar selection in one window.

## Regression checks

`ReaderLoadingTests` exercises the real app model and PDFKit with isolated files and a real SQLite store:

- Opening a book keeps the sidebar and selecting the current book reuses its PDF and page.
- Switching away and back reuses a cached PDF; replacing the same path loads the new file.
- Inspection cache records survive store reopen and reject a changed file; cancellation stops between pages.
- A recreated view clears deleted reader highlights without removing original PDF annotations.
- An old PDF view cannot overwrite the current book's reading position.

The sidebar/current-book checks and document-reuse checks failed before the fix. The highlight and stale-view tests reproduced their respective failure modes before repair. The final core and app suites contain 20 passing tests.

## Native UI verification

The final interface was exercised in light/dark mode and at 1380x900 and 1000x700 points. The reading title stayed visible with the sidebar hidden. The reveal action cleared a nonmatching search and restored the selected row; page navigation updated the reading badge. PDF/text arrow keys and note editing remained scoped correctly.

A second check used the copied 711-book library. A book initially at row 150 was selected through search; reveal cleared the filter and scrolled its row inside the visible window. See [large-library check](evidence/large-library-check.json) and [native interaction checks](evidence/current-book-checks.json).

[Light screen](evidence/current-book-light.png) / [Dark screen](evidence/current-book-dark.png) / [Narrow screen](evidence/current-book-narrow.png). Public source screenshots use only the authored synthetic book.

The final app was installed and reopened with the existing book and saved page. The installed executable matches the release build, and notebook/highlight/bookmark table hashes stayed unchanged. Native accessibility inspection confirmed the persistent title, reading badge and loaded PDF. [Installation verification](evidence/reader-installation.json).
