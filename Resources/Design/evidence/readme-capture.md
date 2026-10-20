# README native captures

## Demo recording

Recorded on 2026-10-20 from the native app built at source revision `77046c1`
(merged into `main` as `3a090ee`). That revision fixed excerpt highlights that
appeared only after turning the page; the bug showed up during this recording.

| Item | Record |
| --- | --- |
| Environment | macOS 26.6.2, Apple Silicon, Xcode 27.0 / Swift 6.4, dark appearance |
| Build | `scripts/build-app.sh`, release configuration |
| UI | 1380 x 900 point window |
| Recording | ScreenCaptureKit with a filter that includes only the app's windows, 60 fps, cursor shown. Pointer and keyboard input was scripted at a human pace, so every click and keystroke was a real event in the app |
| Isolation | A new `BOOKSIDE_DATA_DIR` for each scene and a copy of the built bundle with a separate bundle ID |
| Content | See below; the comment, notebook text and Pi question were written for the demo |
| Pi | A live answer from Claude through the local Claude Code sign-in. The answer is shown as returned |
| Editing | Remotion: cuts, zoom, speed-up, English captions, and title and credit cards. Every sped-up part shows its rate (for example `6×`). App pixels were not edited. macOS draws a capture indicator in place of the window buttons while a window is recorded |
| Files | [`readme-demo.mp4`](readme-demo.mp4): 1920 x 1080, 30 fps, H.264, 1:34. [`readme-demo.gif`](readme-demo.gif): 960 x 540, 10 fps, 38 s cut of the same recording |

The book is Franz Kafka's *The Metamorphosis* in Ian Johnston's English translation,
from the Feedbooks PDF edition (54 pages). The German original is in the public domain,
and the translator released this translation into the public domain on the condition
that the source is acknowledged. The Feedbooks file adds a notice asking that it not be
used commercially; this repository shows its pages only in non-commercial documentation,
with the source credited in the video and here.

The "scanned pages" book is PDF pages 3 to 8 of the same file, rasterized at 200 dpi
onto a tinted, slightly rotated page with no text layer. It shows OCR on a document
that has no text to start with.

## Screenshots

Captured on 2026-10-16 from the native app built at source revision `5f638f1`.
The documentation branch does not change app source.

| Item | Record |
| --- | --- |
| Environment | macOS 26.6.2, Apple Silicon, Xcode 27.0 / Swift 6.4 |
| Build | `scripts/build-app.sh`, release configuration, signature verified |
| UI | SwiftUI/AppKit/PDFKit, 1380 x 900 point window |
| Captures | [Light](readme-reader-light.jpg), [dark](readme-reader-dark.jpg) |
| Method | Native window screenshot; no composited or generated UI |
| Isolation | Dedicated `BOOKSIDE_DATA_DIR` and a copy of the built bundle with a separate documentation bundle ID |
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
