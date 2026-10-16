# README native captures

Captured on 2026-10-16 from the native app built at source revision `5f638f1`.
The documentation branch does not change app source.

| Item | Record |
| --- | --- |
| Environment | macOS 26.6.2, Apple Silicon, Xcode 27.0 / Swift 6.4 |
| Build | `scripts/build-app.sh`, release configuration, signature verified |
| UI | SwiftUI/AppKit/PDFKit, 1380 x 900 point window |
| Captures | [Light](readme-reader-light.jpg), [dark](readme-reader-dark.jpg) |
| Method | Native window screenshot; no composited or generated UI |
| Isolation | Dedicated `BOOKSHELF_DATA_DIR` and a copy of the built bundle with a separate documentation bundle ID |
| Content | Three authored eight-page PDFs and sample notebook text created for this capture; no commercial book or private notebook |

The selected sample is titled “생각을 정리하는 독서”. Its page says that it is an
authored public example, not text from a published book. The other sample titles
are “학습을 위한 질문 노트” and “A Practical Guide to Reading”. The sample text
illustrates reading with a question, keeping source quotations, and writing a
separate interpretation. It is included in the screenshots under the repository's
MIT license.

The app visibly shows the selected book, PDF page 3 of 8, a saved sample notebook,
and a page-3 bookmark. Light appearance was selected through the app's settings;
the dark capture follows the system appearance. The operating system's capture
indicator may appear in the title bar. Neither image was edited to remove UI.

For a reproducible basic fixture, use `scripts/make-fixture.swift` as described in
[development](../../../docs/06-development.md#screenshots-and-ui-verification).
That fixture is a scanned test document; the authored README sample has different
content and an embedded text layer. Existing shelf/OCR screenshots retain their
original verification records.
