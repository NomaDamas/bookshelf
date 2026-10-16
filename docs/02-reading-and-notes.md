# Reading and notes

[Documentation](README.md) / Reading and notes

## The workspace

The left sidebar lists PDFs by title/category. The center shows the original PDF
or extracted text. The right panel switches between **메모** (notebook), **발췌**
(quotations), and **검색** (search). Resize or hide panels to give the document more room.

![Native PDF reader with sample notes](../Resources/Design/evidence/readme-reader-light.jpg)

The original view supports selection, zoom, and single-page/continuous layouts.
Text view displays the PDF's existing text layer; switching views does not run OCR.
All page numbers are 1-based PDF indices, not printed book-page labels.

## Notes, quotations, and bookmarks

- Write your interpretation in **메모**. Changes autosave; the panel shows save status.
- Select source text, then use **선택 문장 메모** (`Command-Shift-H`) to save a
  quotation. Add your own comment in **발췌**. PDF selections can retain page coordinates.
- Use `Command-D` to toggle the current page's bookmark.
- Use **메모 내보내기…** or the share button to export notebook text and quoted
  passages/comments as Markdown. Bookmarks and full database metadata are not included.

If saving fails, keep the draft open. **다시 저장** retries; **내 내용 복사 후 다시
불러오기** copies your draft before reloading. A revision conflict means another
writer changed the notebook; copying your draft avoids losing your work when you reload.
Normal book switching, shelf navigation, and app termination attempt to flush pending notes.

## Reading controls

Click the original PDF or text reading area to use these keys. Switching to text view focuses
the reading area automatically. Notes, search fields, PDF form fields, and the page-number
field keep their normal editing keys.

| Key | Action |
| --- | --- |
| Left / Right | Previous / next PDF page |
| Space / Shift-Space | Next / previous PDF page |
| Page Down / Page Up (Fn-Down / Fn-Up) | Next / previous PDF page |
| Home / End (Fn-Left / Fn-Right) | First / last PDF page |
| Up / Down | Scroll within the reading area |
| Command-Shift-R | Return keyboard focus to the current reading view |
| Command-Shift-L | Show the currently reading shelf |
| Command-Option-Left / Right | Previous / next page from anywhere in the reader |

Enter a page number and press Return to jump and keep reading with the keyboard.
The first and last pages are clamped. PDF layout selection is saved between launches.
The keyboard button beside the page controls opens an in-app reference.

The reading area keeps the current book title visible above the controls. Opening a book
preserves the sidebar's visibility. The library marks the current row with its live page;
“책장에서 보기” clears a library filter and scrolls to that book.

Additional shortcuts:

| Key | Action |
| --- | --- |
| Command-O / Command-Shift-O | Add PDFs / add a folder |
| Command-F | Search within the current book |
| Command-D | Toggle a bookmark |
| Command-Shift-H | Save selected text as a quotation |
| Command-S | Save pending notebook edits |
| Command-0 | Toggle the library sidebar |
| Command-Shift-M | Toggle the notes panel |

## Currently reading

Choose “읽는 중” in the sidebar or press Command-Shift-L to open the dedicated reading shelf.
Cards show covers, saved pages and progress in recent-reading order. Selecting a card resumes
that book; “읽던 책으로” returns to the previously open reading surface.

Books with a saved reading position appear automatically. A card's menu can exclude a book
from this shelf; the book, notebook and position remain in the library. Reopening an excluded
book preserves that choice. Add it again from the book options or the sidebar context menu.
The context menu can also add a book before it has been opened. These choices persist locally.
Opening the shelf saves pending notes and the current page; a note-save conflict keeps the
editor open so the draft can be recovered.

[Light preview](../Resources/Design/evidence/reading-shelf-light.png) /
[Dark preview](../Resources/Design/evidence/reading-shelf-dark.png) /
[Compact window](../Resources/Design/evidence/reading-shelf-narrow.png).
Previews use authored sample books. [Native checks](../Resources/Design/evidence/reading-shelf-checks.json)
cover resume, live progress, exclusions across restart, empty state, re-adding, the shortcut and note preservation.

## Searching OCR text

The search panel enables “띄어쓰기 무시” by default. `설득의 심리학` can find `설 득 의 심 리 학`,
and `Deep Learning` can find `DE EP LEARN ING`, including line breaks, tabs and Unicode spaces.
Soft hyphens and zero-width spaces are ignored in this search projection too.
PDF files, extracted source text, quotations and page numbers stay unchanged.

Turn the checkbox off when word boundaries matter: removing spaces also makes `the rapist`
match `therapist`. This feature does not correct misspelled characters, rewrite grammar,
or remove visible punctuation/hyphens. It does not install a language model or upload book text.

CLI search uses the same default. Pass `--exact-spacing` to preserve spacing.
The MCP `search_book` tool accepts `ignore_whitespace: false` for the same behavior and returns
the chosen mode alongside original page excerpts.

The sidebar filter searches book titles/categories. The right-hand search panel
searches the current book's text, returning up to 20 matching pages. Select a
result to jump to its PDF page.

## Appearance and AI handoff

Settings offer system, light, and dark appearance. Native materials surround opaque
reading/writing surfaces. Reduced transparency, increased contrast, and reduced
motion have fallback paths; see [design and verification](../Resources/Design/DESIGN.md).

**AI로 이어가기** copies a prompt identifying the current book and PDF page to the
clipboard. Paste it into a configured client. It does not run a model in Bookshelf.
For tool access, follow [CLI and MCP setup](03-cli-and-mcp.md).
