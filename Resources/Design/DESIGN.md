# Bookshelf native workspace

Bookshelf reuses the visual grammar of [Aside / Glass workspace](https://github.com/seungwonme/ui-references/tree/main/references/aside-glass), a source study of Aside 1.0.928.1. This is a SwiftUI/AppKit implementation in the existing reader. The web prototype remains a separate worktree.

## Source and adaptation

The reference's `tokens.json`, `DESIGN.md`, preview and extraction evidence were inspected before implementation. Source facts and Bookshelf choices are different:

| Rule | Source evidence | Native implementation |
| --- | --- | --- |
| Neutral selection and subtle borders | Aside accent/border alpha, muted navigation states | Semantic foreground with the same low opacity; blue is reserved for actions and bookmarks |
| Compact controls | Default 32px button, 14px/12px type, 4px spacing unit | 32pt hit targets; 13pt system control font and 14pt note text |
| Soft continuous corners | Aside radius-md, radius-lg, radius-xl | Converted to point dimensions and SwiftUI continuous rounded rectangles |
| Sidebar | Source width 280px, compact rows, right hairline | 280pt ideal width with native split resizing; taller book rows accommodate covers and two-line titles |
| Translucent surfaces | Source common glass uses a surface fill, blur, inner edge and outer ring | Public AppKit sidebar/under-window materials blend behind the window; the OS owns blur and vibrancy |
| Foreground and font | Geist and theme-specific source colors | macOS system font and semantic text/background colors, including Korean fallback |
| Content surface | Source conversation surface and composer card | Opaque PDF/text and notebook surfaces for sustained reading |

The forest wallpaper, experimental Liquid Glass shader layers, Aside logo and bundled typefaces are not included. Their native pixel equality was never established by the source study. Bookshelf uses [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) for native material behavior. The resulting interface follows the reference's hierarchy, not a screenshot reproduction.

## Tokens and ownership

`tokens.json` is the dimension/opacity source. Its DTCG `px` dimensions map to macOS points. Run `python3 scripts/generate-reader-tokens.py` from the repository root after changing a token. `ReaderTokens.swift` is generated; `build-app.sh` rejects a stale copy. Semantic colors and native materials are defined in `ReaderStyle.swift`, so macOS retains control of their appearance and accessibility behavior.

## Screen rules

- The library is a quiet material sidebar with a search field and neutral selected row. Cover/title/progress form one hit target. Opening a PDF replaces this with the book's pages, notes, excerpts and search tools; returning to the library restores book navigation.
- Reading status uses three shelves: 읽기 전, 읽는 중 and 읽은 책. Read-through counts and dates stay with each book. Red count badges are reserved for saved note items; they hide zero and cap the display at 99+. Shelf and sidebar sorting share one persisted selection.
- The reader has one inset surface. Its toolbar and footer use the same shared heights. The document remains the largest area; hiding either side panel preserves the reading context.
- Notes use an opaque writing surface inside the left material sidebar. Save status, book title and bookmarks stay near the editor. Search, excerpts and PDFKit thumbnails share that location. The optional AI panel is exclusively on the right.
- The AI composer groups page/notes context, explanation profile, input, attachments, model selection and send/stop. Assistant prose uses the panel canvas; the user's questions and rich visuals have their own quiet surfaces. Edit, retry, clear and undo remain discoverable controls.
- Settings use grouped surfaces and native pickers. Appearance can follow the system or use light/dark mode, persisted in app preferences.
- OCR review is the new screen used to check reuse beyond the reference: equal source/result panes, plain metrics, native page controls, explicit acceptance. Return in a field does not accept a PDF; acceptance remains Command-Return.

## Accessibility and behavior

Buttons retain native actions, labels and keyboard access. Search fields keep their visible magnifier and a focus outline. Disabled page actions are visibly dimmed. Reduced transparency selects an opaque system background; increased contrast strengthens surface edges; reduced motion removes panel-toggle animation. These fallback paths are implemented, with live verification scope recorded separately.

The native minimum window is 1000 by 650 points. Panels can be resized or hidden; no mobile/web breakpoint is added to this macOS app. Notes and search text keep normal editing keys. PDF and text reading views retain page navigation keys.

## Preview layout and Aside motion

Preview 11.0's compiled `PVDocument.nib` identifies `LeftSplitRootView`, `SidebarView`,
`MainSplitRootView` and `PVSplitViewController`. Its menu archive contains thumbnail and
sidebar-toggle actions. This supports the document/sidebar layout; it does not establish
runtime pixel measurements or a copied Preview appearance. The AI inspector is a Bookshelf
addition.

The bounded REA archive result and the verified Aside source facts are recorded in
[`reader-workspace-reference.json`](evidence/reader-workspace-reference.json).

Aside's matching source CSS declares a 150ms default transition with `cubic-bezier(.4,0,.2,1)`.
The composer source uses a radius-2xl card, a fine ring, and grouped editor/attachment/send
controls. The token source preserves these origins. Bookshelf's 240ms native split animation
and 200ms message treatment are adaptations, not measured Aside interaction durations.
Reduced Motion removes optional animations. Streaming text is batched at short intervals;
scrolling back through a conversation leaves a control to return to the newest reply.

See `verification.md` for observed behavior and screenshots. Screenshots contain an authored synthetic book, not a user's copyrighted library or personal notes.
