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

- The library is a quiet material sidebar with a search field and neutral selected row. Cover/title/progress form one hit target.
- The reader has one inset surface. Its toolbar and footer use the same shared heights. The document remains the largest area; hiding either side panel preserves the reading context.
- Notes use an opaque writing surface inside a material inspector. Save status, book title and bookmarks stay near the editor. Search and excerpts share the same panel grammar.
- Settings use grouped surfaces and native pickers. Appearance can follow the system or use light/dark mode, persisted in app preferences.
- OCR review is the new screen used to check reuse beyond the reference: equal source/result panes, plain metrics, native page controls, explicit acceptance. Return in a field does not accept a PDF; acceptance remains Command-Return.

## Accessibility and behavior

Buttons retain native actions, labels and keyboard access. Search fields keep their visible magnifier and a focus outline. Disabled page actions are visibly dimmed. Reduced transparency selects an opaque system background; increased contrast strengthens surface edges; reduced motion removes panel-toggle animation. These fallback paths are implemented, with live verification scope recorded separately.

The native minimum window is 1000 by 650 points. Panels can be resized or hidden; no mobile/web breakpoint is added to this macOS app. Notes and search text keep normal editing keys. PDF and text reading views retain page navigation keys.

See `verification.md` for observed behavior and screenshots. Screenshots contain an authored synthetic book, not a user's copyrighted library or personal notes.
