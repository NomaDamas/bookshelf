# Reading and notes

[Documentation](README.md) / Reading and notes

## The workspace

The library sidebar lists PDFs by title/category. After opening a book, it becomes
a book-specific sidebar with **페이지** (page thumbnails), **메모** (notebook),
**발췌** (quotations), and **검색** (search). The original PDF or extracted text stays
in the center. The learning chat places its AI conversation on the right.
The **서재** toolbar button returns to the library even when the left sidebar is hidden.

![Native PDF reader with sample notes](../Resources/Design/evidence/readme-reader-light.jpg)

The original view supports selection, zoom, and single-page/continuous layouts.
Text view displays the PDF's existing text layer; switching views does not run OCR.
All page numbers are 1-based PDF indices, not printed book-page labels.

## Notes, quotations, and bookmarks

- Write your interpretation in **메모**. Changes autosave; the panel shows save status.
- Select source text, then use **책 > 선택 문장 발췌** (`Control-Command-H`) to save a
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
| Option-Up / Option-Down | Previous / next page from anywhere in the reader |
| Option-Command-G | Move to the page-number field |
| Command-Shift-R | Return keyboard focus to the current reading view |

While you type in notes, a search field, the page-number field or the Pi composer,
Option-Up and Option-Down keep their editing meaning and move the cursor instead of the page.

Enter a page number and press Return to jump and keep reading with the keyboard.
The first and last pages are clamped. PDF layout selection is saved between launches.
**Help > Bookside 키보드 단축키** lists every key with your current settings; the keyboard
button beside the page controls opens the same list.

The reading area keeps the current book title visible above the controls. Opening a book
preserves the sidebar's visibility. The library marks the current row with its live page;
“책장에서 보기” clears a library filter and scrolls to that book.

Default app shortcuts follow Preview and other macOS apps. Change them in
**Settings > 단축키**.

| Menu | Key | Action |
| --- | --- | --- |
| File | Command-O / Command-Shift-O | Add PDFs / add a folder (fixed) |
| File | Command-S | Save pending notebook edits |
| Edit > 찾기 | Command-F | Search within the current book |
| Edit > 찾기 | Command-G / Command-Shift-G | Next / previous search result |
| View | Control-Command-S | Show or hide the sidebar |
| View | Option-Command-I | Show or hide the Pi panel |
| View | Option-Command-1 / 2 / 3 | Open pages / notes / excerpts |
| View | Command-Plus / Command-Minus | Zoom in / out (Command-= also zooms in) |
| View | Command-0 / Command-9 | Actual size / fit the page |
| 이동 | Command-Shift-L | Return to the library |
| 이동 | Option-Up / Option-Down | Previous / next page |
| 이동 | Option-Command-G | Go to a page number |
| 이동 | Command-Shift-R | Return focus to the reading view |
| 책 | Command-D | Toggle a bookmark |
| 책 | Control-Command-H | Save selected text as an excerpt |
| Pi panel | Command-Return | Send a question |

Click a shortcut recorder and press the new combination. Escape cancels recording and
Delete leaves the action without a shortcut. Each row's **⋯** menu restores that row's
default or clears it; **모두 기본값으로** restores every default. A shortcut needs Command
(Control-Command also works). Option alone is accepted only for the page arrow commands,
because Option with a letter types a character. Duplicates and keys that macOS or fixed
menus already use (for example Command-W, Command-H, Command-Q and Control-Command-Q)
are rejected. Shortcuts are recorded from the key position, so a Korean input source
records the same keys as an English one. The selected bindings persist in the local
library database. If a saved shortcut matches a newer default, the saved one is kept and
that default is left empty. Plain arrow keys and text editing remain native to the focused
reading/editing view.

## Reading shelves, history and sorting

The sidebar separates **읽기 전** (not started), **읽는 중** (reading) and **읽은 책**
(finished). The library button opens the shelf overview. Cards show covers, the saved page,
progress and read-through counts; “펼친 책으로” returns to the open document.

- Opening a new book starts its first reading. Choose **읽기 완료** in its menu to
  record a completed read-through and its date. Jumping to the last page never completes a book.
- Reopening a finished book is a review. **다시 읽기 시작** starts the next read-through
  at page one and preserves all previous completions and notes.
- **회독 기록 보기** lists completion dates. **최근 완료 기록 취소** undoes only the
  latest completion and returns to reading. Repeated completion clicks cannot add duplicates.
- Shelving a first read returns it to not started; cancelling a reread returns it to
  finished with the earlier counts intact. Saved pages and notes remain available.
- Red badges count one nonempty book notebook plus each saved excerpt. Editing or autosaving
  an item does not increase its count. Zero is hidden; 100 or more is displayed as **99+**,
  with the exact number exposed to accessibility. A card's badge opens that book's notes.
- Sort by recently read, recently finished, recently added, title, note count or read-through
  count, with ascending/descending order. The last selection applies across all shelves and
  the sidebar, and survives relaunch. Title ties use a stable secondary order.

Reading state and completion events live in additive SQLite tables. Legacy reading-shelf
membership and saved positions are carried forward; no historical completions or start dates
are invented. Opening a shelf or changing reading state first saves pending notes; a save
conflict preserves the draft in the reader.

[Light preview](../Resources/Design/evidence/reading-history-light.png) /
[Dark preview](../Resources/Design/evidence/reading-history-dark.png) /
[Compact window](../Resources/Design/evidence/reading-history-narrow.png) /
[Completion history](../Resources/Design/evidence/reading-history-dates.png).
Previews use authored sample books. See [native checks](../Resources/Design/evidence/reading-history-checks.json)
and [upgrade checks](../Resources/Design/evidence/reading-history-migration.json).

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

The library filter searches book titles/categories. The reading sidebar's search tool
searches the current book's text, returning up to 20 matching pages. Select a
result to jump to its PDF page.

## Appearance and AI handoff

Settings offer system, light, and dark appearance. Native materials surround opaque
reading/writing surfaces. Reduced transparency, increased contrast, and reduced
motion have fallback paths; see [design and verification](../Resources/Design/DESIGN.md).

The AI panel beside the page runs the [learning chat](../Resources/Design/PI-AGENT.md).
Its settings contain Pi/account/model choices, and its conversation supports
visual previews, audio playback, question editing, retry and reversible clearing.
The default **자동** mode chooses prose, tables or visual explanations for the question.
You can still select a specific explanation format. Codex can generate images through its
official image tool; generated images stay with the conversation and can be enlarged,
copied or saved. Image generation requires the app's official ChatGPT sign-in and remains
subject to account availability and limits. To use the library from another AI client,
follow [CLI and MCP setup](03-cli-and-mcp.md).

The default question scope is **이 책 전체** (this book). The current page identifies what
you are looking at; the agent can search the book and read other relevant pages. Use the
**질문 범위** menu to choose **현재 페이지** or **페이지 범위 지정…**. A selected range
uses 1-based PDF indices and is enforced by the read-only server. Switching books resets
the selection to the whole new book. Retrying or editing a question keeps its original range.
Conversations created before range metadata existed keep their original single PDF page
when retried. Copying an answer into the notebook records its question scope alongside
the answer's page citations.

While retrieving evidence, the panel shows search, outline and page-reading activity.
Source chips and verified `[p. N]` links navigate within the active PDF. The coverage line
counts pages whose full text was received, excluding search-only excerpts. Pages without
extractable text are reported separately. An outline is not proof of reading every chapter:
whole-book and chapter summaries must follow page continuations and report unread gaps.
Long books may require more time and provider context; the request can be stopped.
