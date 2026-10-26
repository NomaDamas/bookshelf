# Bookside native workspace

Bookside reuses the visual grammar of [Aside / Glass workspace](https://github.com/seungwonme/ui-references/tree/main/references/aside-glass), a source study of Aside 1.0.928.1. This is a SwiftUI/AppKit implementation in the existing reader. The historical web prototype is not part of this app; see [architecture](../../docs/05-architecture.md#generated-assets-and-native-design).

## Source and adaptation

The reference's `tokens.json`, `DESIGN.md`, preview and extraction evidence were inspected before implementation. Source facts and Bookside choices are different:

| Rule | Source evidence | Native implementation |
| --- | --- | --- |
| Neutral selection and subtle borders | Aside accent/border alpha, muted navigation states | Semantic foreground with the same low opacity; blue is reserved for actions and bookmarks |
| Compact controls | Default 32px button, 14px/12px type, 4px spacing unit | 32pt hit targets; 13pt system control font and 14pt note text |
| Soft continuous corners | Aside radius-md, radius-lg, radius-xl | Converted to point dimensions and SwiftUI continuous rounded rectangles |
| Sidebar | Source width 280px, compact rows, right hairline | 280pt ideal width with native split resizing; taller book rows accommodate covers and two-line titles |
| Translucent surfaces | Source common glass uses a surface fill, blur, inner edge and outer ring | Public AppKit sidebar/under-window materials blend behind the window; the OS owns blur and vibrancy |
| Foreground and font | Geist and theme-specific source colors | macOS system font and semantic text/background colors, including Korean fallback |
| Content surface | Source conversation surface and composer card | Opaque PDF/text and notebook surfaces for sustained reading |

The forest wallpaper, experimental Liquid Glass shader layers, Aside logo and bundled typefaces are not included. Their native pixel equality was never established by the source study. Bookside uses [NSVisualEffectView](https://developer.apple.com/documentation/appkit/nsvisualeffectview) for native material behavior. The resulting interface follows the reference's hierarchy, not a screenshot reproduction.

## Tokens and ownership

`tokens.json` is the dimension/opacity source. Its DTCG `px` dimensions map to macOS points. Run `python3 scripts/generate-reader-tokens.py` from the repository root after changing a token. `ReaderTokens.swift` is generated; `build-app.sh` rejects a stale copy. Semantic colors and native materials are defined in `ReaderStyle.swift`, so macOS retains control of their appearance and accessibility behavior.

### Type scale

Text sizes use five tokens. Aside declares text-xs (12px), text-sm (14px) and text-base (16px) but no smaller step, so the two smallest steps take macOS standard sizes.

| Token | pt | Origin | Used for |
| --- | --- | --- | --- |
| `footnoteFont` | 10 | macOS label size (`NSFont.labelFontSize`) | Status tags, media captions and clocks, reading-coverage lines, Pi gutter marks |
| `detailFont` | 11 | macOS small system size (`NSFont.smallSystemFontSize`) | Counts, dates, save status, helper lines, notices, code in chat |
| `captionFont` | 12 | Aside text-xs | Secondary labels and messages, shortcut rows, chat turn lines and tables, compact and segmented controls |
| `controlFont` | 13 | Aside text-sm at the macOS system size | Controls, rows, toolbar titles, settings and empty-state text, quotes, search hits, OCR text |
| `bodyFont` | 14 | Aside text-sm | Notes, chat messages and editors, headings that differ from body text only by weight, the page field |

A token names its step's main use; a call site takes the step that matches its size. SF Symbols sized with `.font` use the same steps, as `ReaderIconButton` already did. Sizes outside the scale stay literal: the 7pt Pi status dots, and 16pt or larger titles and empty-state symbols.

## Screen rules

- The library is a quiet material sidebar with a search field and neutral selected row. Cover/title/progress form one hit target. Opening a PDF replaces this with the book's pages, notes, excerpts and search tools; returning to the library restores book navigation.
- Reading status uses three shelves: 읽기 전, 읽는 중 and 읽은 책. Read-through counts and dates stay with each book. Red count badges are reserved for saved note items; they hide zero and cap the display at 99+. Shelf and sidebar sorting share one persisted selection.
- The reader has one inset surface. Its toolbar and footer use the same shared heights. The document remains the largest area; hiding either side panel preserves the reading context.
- Notes use an opaque writing surface inside the left material sidebar. Save status and bookmarks stay near the editor. Search, excerpts and PDFKit thumbnails share that location. The Pi panel is always on the right.
- The Pi panel reads as a transcript on the panel canvas. Turns are separated by space and type weight, not bubbles or borders; rich visuals keep their own quiet surfaces. The header, composer rows and transcript lines are specified in [Pi learning chat](PI-AGENT.md#reading-workspace-and-controls).
- Settings use grouped surfaces and native pickers. Appearance can follow the system or use light/dark mode, persisted in app preferences.
- OCR review is the new screen used to check reuse beyond the reference: equal source/result panes, plain metrics, native page controls, explicit acceptance. Return in a field does not accept a PDF; acceptance remains Command-Return.

## Accessibility and behavior

Buttons retain native actions, labels and keyboard access. Search fields keep their visible magnifier and a focus outline. Disabled page actions are visibly dimmed. Reduced transparency selects an opaque system background; increased contrast strengthens surface edges; reduced motion removes panel-toggle animation. These fallback paths are implemented, with live verification scope recorded separately.

The native minimum window is 1000 by 650 points. Panels can be resized or hidden; no mobile/web breakpoint is added to this macOS app. Notes and search text keep normal editing keys. PDF and text reading views retain page navigation keys.

## Wordmark and app icon

In the wordmark a bookmark ribbon takes the place of the dot on the i; the app icon pairs a serif B with the same ribbon hanging from the tile's top edge. Colors are ink `#1E3550`, paper `#F4EDE0` and highlighter `#F5C842`. The letters are [Newsreader](https://github.com/google/fonts/tree/main/ofl/newsreader) 1.003 (SIL Open Font License) at weight 600 and the 72 pt optical size.

`Resources/Brand` is generated by `swift scripts/generate-brand.swift <Newsreader[opsz,wght].ttf>` from the repository root. Its SVGs hold outlines, so building does not need the font.

| Asset | Use |
| --- | --- |
| `wordmark.svg`, `wordmark-dark.svg` | README header on light and dark GitHub themes |
| `AppIcon.icon` | Icon Composer source. `build-app.sh` compiles it with actool into `Assets.car` for macOS 26 and `AppIcon.icns` for earlier systems |
| `social-preview.png` | 1280 x 640 image for the repository's Settings > Social preview. GitHub has no API for it, so upload it again after regenerating |

macOS 26 shows an icon that does not follow Apple's icon grid inside a gray tile, as it did with the previous generated icon ([before and after](evidence/app-icon-macos26.png), rendered by `NSWorkspace` on macOS 26.6.2). Check a new icon in Finder or the Dock before merging.

The Dark icon style in System Settings > Appearance paints a layer that has no dark fill in the tile color, so the letter layer sets paper as its dark fill; without it the B turned navy on a near-black tile ([0.3.0 and fixed](evidence/app-icon-dark-style.png)). Icon Composer's `ictool` renders every style without changing that setting. From the repository root, with `--rendition` set to `Default`, `Dark`, `TintedLight`, `TintedDark`, `ClearLight` or `ClearDark`:

```sh
"$(xcode-select -p)/../Applications/Icon Composer.app/Contents/Executables/ictool" Resources/Brand/AppIcon.icon \
  --export-image --output-file icon-dark.png --platform macOS --rendition Dark --width 512 --height 512 --scale 1
```

## Preview layout and Aside motion

Preview 11.0's compiled `PVDocument.nib` identifies `LeftSplitRootView`, `SidebarView`,
`MainSplitRootView` and `PVSplitViewController`. Its menu archive contains thumbnail and
sidebar-toggle actions. This supports the document/sidebar layout; it does not establish
runtime pixel measurements or a copied Preview appearance. The AI inspector is a Bookside
addition.

The bounded REA archive result and the verified Aside source facts are recorded in
[`reader-workspace-reference.json`](evidence/reader-workspace-reference.json).

Aside's matching source CSS declares a 150ms default transition with `cubic-bezier(.4,0,.2,1)`.
The composer source uses a radius-2xl card, a fine ring, and grouped editor/attachment/send
controls. The token source preserves these origins. Bookside's 240ms native split animation
and 200ms message treatment are adaptations, not measured Aside interaction durations.
Reduced Motion removes optional animations. Streaming text is batched at short intervals;
scrolling back through a conversation leaves a control to return to the newest reply.

See `verification.md` for observed behavior and screenshots. Screenshots contain an authored synthetic book, not a user's copyrighted library or personal notes.
