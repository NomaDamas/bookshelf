# Pi learning chat

Bookside includes a native chat panel. It uses Pi agent core for conversation state and streaming, with adapters that invoke unmodified official executables. The same panel can bypass Pi to compare the extra layer. The default is Pi enabled. Each message records the selected harness and learning profile. A reply's summary line names the executor and model (for example `Claude / Sonnet`); its tooltip says whether Pi handled the request.

## Scope

- Ask across the selected book by default, using the current page as the reader's location. Restrict a request to the current page or an explicit PDF page range when needed.
- Choose Claude or Codex, preserving the app's book-specific conversation.
- Choose a model. The default automatic profile selects prose, comparison tables, diagrams or interactive explanations for the question; plain explanation, comparison table and visual explanation remain optional overrides.
- Use an English system prompt while answering in the user's requested language.
- Stream replies, stop a request, save a completed reply to the notebook and return to the question's PDF page.
- Store conversations in a separate SQLite table with revision checks. Chats do not count as notebook items unless explicitly copied to the notebook.
- Edit a question and regenerate from that point, retry an answer, remove a conversation tail or clear the chat. Up to ten prior edits can be restored, including after reopening the app.
- Read official per-request token usage and context-window size, when the executor provides them.
- View Mermaid, SVG, images and offline HTML; open user-selected audio/video with native playback controls.
- Generate illustrations through Codex's official image tool, see progress in chat, and reopen, enlarge, copy or save the resulting PNG. Claude can produce tables, Mermaid, SVG and HTML; it does not expose a bitmap-generation tool in this integration.
- Search/read progress, verified page citations and complete-page coverage stay with each response. Clicking a source opens that PDF page. Retry/edit uses the original range.

The chat does not add whole-library semantic retrieval, audio synthesis, arbitrary external skills or autonomous file-editing tools. HTML can run inline interaction code inside an isolated offline preview. The existing external MCP server stays read-only.

## Reading workspace and controls

The panel sits to the right of the document and collapses through native AppKit split-view
animation. The reading guide describes the rest of the [workspace](../../docs/02-reading-and-notes.md#the-workspace)
and the [shortcut settings](../../docs/02-reading-and-notes.md#reading-controls); surfaces, composer density
and motion easing follow [design](DESIGN.md). **Settings > Pi** owns official account
login/status, model selection and the advanced switch that sends requests to the executor
without Pi. Signing in to an executor there does not change the engine the current
conversation uses.

The panel is called Pi in its header, settings and notices. Frequent controls stay visible;
occasional ones move to the header's ⋯ menu:

- Header: one line with the bold title and the current page in secondary text (the window
  toolbar already shows the book title),
  and a ⋯ menu with undo, copy conversation, clear conversation (confirmed), context usage,
  learning instructions and connection settings.
- Composer: a top row with the question scope, notes and explanation menus, the field, and a
  bottom row with 자료 열기, the executor/model menu and send/stop. The three menus mark the
  current choice with the native checkmark, and their labels match the item names. The scope
  label carries the reader's page (`이 책 전체, 27쪽에서`, `현재 쪽(27쪽)`, `27~40쪽`).
- When sending is unavailable, one line under the field gives the reason: Node.js missing,
  account not connected or still being checked, sign-in in progress, PDF loading, a page range
  being chosen, a question being edited, or a question over 10000 characters.
- A missing runtime or disconnected account shows a notice line with **연결하기**, which opens
  **Settings > Pi**. Account status checks run separately from replies and sign-in, so opening
  a book never disables the panel. Errors can be dismissed.
- Questions show the page they were asked from; editing happens in place. "여기부터 지우기"
  is in the message's context menu, asks for confirmation and can be restored with undo.
- Replies end with source page chips. Copy, regenerate (latest reply only) and save-to-notes
  icons sit on the turn's summary line, each with a tooltip.
- The empty conversation and the latest completed reply offer three fixed prompts (explain this
  page, summarize this chapter, quiz me). Choosing one fills the field; nothing is sent until
  the reader sends it.

### Transcript

The conversation reads as a transcript rather than chat bubbles. Turns are separated by space
and type weight, without borders or backgrounds. Answers stay in the proportional reading font.

- A question is one line marked with `❯` in medium weight. The answer is plain body text under
  it, aligned to the same text column; status marks sit in a narrow column to the left.
- Tool steps appear between the question and the answer, one line each, with the bold step
  name, its arguments in secondary text and a child result line:
  `● 책 읽기 (27~29쪽)` / `└ 3쪽 읽음`. Steps come from the bridge's existing events: the
  `activity` sentences from `bookToolActivity` and Codex image generation open a step, an
  empty `activity` closes the oldest open one, and `reading` coverage or a generated image
  fills its result. The step names are 책 검색, 책 읽기, 읽은 범위 확인, 목차 확인 and
  그림 만들기; an unknown sentence is shown as sent. A page read reports the pages the call
  asked for, so reading a page again still counts.
- Status marks: a spinner while a step runs, an orange ring when the reader has to act (a
  failed step or turn, sign-in in the browser, a connection notice), a green dot when done
  and a gray dot when interrupted.
- Each finished turn ends with a muted summary line, for example
  `✻ 12초 동안 작업, 오후 9:41 완료, Claude / Sonnet`, or `완료하지 못함` / `중단됨`. While the
  reply runs it reads `✻ 생각하는 중, 8초`, then `답변 쓰는 중` once text arrives, ticking
  once a second.
- Steps and the finish time are saved with the reply (`steps`, `finished`). Both are optional,
  so conversations saved earlier still open; their summary line shows only the state and the
  executor/model.

The Pi menu's context usage item shows the latest request's input plus output tokens, not a
lifetime total or a guessed remaining balance; choosing it opens the token breakdown. Claude input includes cache reads and cache creation;
Codex uses the `last` token breakdown. Missing usage/window metadata is shown as unavailable.
Older conversations remain readable without these optional fields.

Mermaid 11.17.2 and DOMPurify 3.4.17 are bundled locally. Mermaid uses strict mode; SVG is
sanitized. HTML runs in an opaque iframe with inline scripts/styles, data images and no
network, forms, file access, popups or top-level navigation. Native bridge messages from
child frames are rejected. The large preview supports zoom and source viewing.

The 자료 열기 button (document icon) imports user-selected media into `ChatAssets/` and stores references
with that book. Audio supports play/pause, seeking and playback speed through AVFoundation.
External HTTPS media requires an explicit load action. The native viewer never opens
paths supplied in answer text. Imported files are display material and are not sent to the model.

Codex generated images arrive as official `imageGeneration` events. The bridge validates
PNG bytes (32 MiB and 40 million pixels maximum), gives each a new UUID filename in
`ChatAssets/`, and emits only attachment metadata to the native app. It never reads an
event's `savedPath` or a path from answer text. The native app validates the PNG again
before attaching it to the active response. Image-only answers are valid. Duplicate events
are ignored, cancellation discards late results, and clear/undo retains image references.
Image failures show an explicit notice; there is no paid API-key fallback. Account limits
and provider policies still apply. Image generation can take several minutes; the turn
timeout is ten minutes and the stop control stays available.

## Execution boundary

```text
SwiftUI chat and PDF context
    -> local JSONL bridge
    -> Pi agent core (optional)
    -> official Claude Code CLI OR official Codex App Server
    -> native response and per-book conversation storage
```

Pi does not receive provider credentials and does not use its direct Anthropic or OpenAI OAuth providers. Authentication remains inside the corresponding official executable. No API key fallback is configured. The bridge uses an allowlist of environment variables, so inherited API keys, alternate endpoints and OAuth token variables cannot silently change the selected subscription route.

The complete conversation is stored by Bookside. Each request includes at most the latest 12 completed messages, each capped at 6000 characters, plus the current question. Switching engines starts a fresh executor request with that context; it does not transplant provider-private reasoning, caches or opaque session state. The supplied page is capped at 10000 characters, notebook at 4000 and selection at 3000. Older context is omitted, not silently summarized.

The app starts a private `reading-mcp` instance with a fixed book ID, library directory and
page range. Four tools provide the outline, keyword search, paginated page reading and
coverage. Neither the model nor tool arguments can change the book or filesystem path.
Claude uses a per-tool output ceiling of 64,000 tokens so bounded CJK page chunks keep
their complete JSON envelope. The server still limits reads to 24,000 characters per call.
The whole-book scope is the default; narrower scopes exclude current-page text/selection
outside the boundary and omit prior conversations with a different scope. Optional notes
remain user reference material. Local PDF-page links only target pages confirmed by the app or matching tool results. Concurrent tool results merge coverage
monotonically. Search excerpts do not count as full page reads, and unread/empty pages
remain visible. Complete summaries must follow page continuations and check coverage.

## Learning profile isolation

`Sources/BookshelfAgent/instructions.ts` is the instruction source. Build output contains a generated `profile.json`, which the Pi menu's 학습 지침 보기 item shows. The bridge does not discover skills, plugins or instructions from user/project directories.

- Claude account status/login and legacy tool-free requests use `--safe-mode`. Book-reading requests use `--restricted`, empty `--setting-sources`, explicit `disableAllHooks`, `--disable-slash-commands`, `--tools ""`, `--strict-mcp-config` and one explicit `--mcp-config` server. Only its four read-only tools are allowed. `CLAUDE_CODE_DISABLE_CLAUDE_MDS`, `CLAUDE_CODE_DISABLE_AUTO_MEMORY` and `CLAUDE_CODE_DISABLE_ATTACHMENTS` prevent ambient memory/instruction files and `@` file expansion. `--bare` is excluded because it disables subscription/keychain authentication. Initialization rejects unexpected tools, MCP servers, custom plugins or skills; built-in vendor plugins/policies remain.
- Codex rejects unknown configuration keys with `--strict-config` and uses a dedicated `CODEX_HOME` under Bookside's data directory and a dedicated working directory. It overrides the base instructions, disables automatic skill instructions and bundled skills, sets `project_doc_max_bytes=0`, disables shell/plugins/apps/multi-agent/view-image/skill-search/tool-suggest/sleep/web-search features and uses read-only sandboxing with no approval escalation. The official image-generation feature is enabled for new images from descriptions. The app accepts image-generation events and rejects other unexpected tool-execution items and client-side tool or credential requests. Some fixed Codex runtime behavior and vendor-managed policies remain; this is not a claim that every internal tool or policy is replaced.
- Vendor and administrator-managed policies still apply. The app does not attempt to bypass them.

Codex also receives the explicit book-scoped MCP configuration, with a four-tool allowlist
and a required startup handshake. `mcpToolCall` events are accepted only for that server
and those names; other unexpected execution items still stop the run. Swift MCP SDK 0.12.1
rejects object-valued experimental client capabilities, including Codex `codex/auth-change`.
The server's transport adapter ignores only unsupported experimental extensions during
initialization. It preserves standard capabilities and every later message. No SDK checkout
or provider executable is patched.

The learning guidelines borrow clarity principles from ASD-STE100, adapted to the user's response language. They are not a claim of certified STE compliance. Source material is explicitly treated as reference data. Answers must distinguish supplied text from added examples, and cite PDF indices using `[p. N]`.

## Account and policy basis

Reviewed 2026-10-16. These links document the implemented route, not a blanket legal assurance or an exemption from account-specific limits.

- [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance#can-customers-offer-claude-code-in-their-products) permits offering an unmodified Claude Code executable under the described conditions. Each user authenticates with their own account; the product must not collect or intermediate their subscription credentials or resell usage. The page expressly distinguishes an end user signing into the official binary from a third party routing extracted subscription tokens.
- [Claude plan / Agent SDK guidance](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) describes subscription usage for the SDK, `claude -p` and third-party applications. This app chooses the official locally installed executable and its own account flow.
- [Claude CLI reference](https://code.claude.com/docs/en/cli-reference) documents safe/restricted mode, tool restrictions and full system-prompt replacement. Authentication remains enabled in safe mode.
- [Codex App Server authentication](https://learn.chatgpt.com/docs/app-server#auth-endpoints) permits the local/open-source integration route described there. Commercial or hosted services require the appropriate Sign in with ChatGPT path. This prototype is a local personal/open-source app, with no hosted service or credential relay.
- The image event contract was checked on 2026-10-19 against the installed Codex 0.163.0 generated schema and the upstream [image-generation integration test](https://github.com/openai/codex/blob/rust-v0.163.0/codex-rs/app-server/tests/suite/v2/imagegen_extension.rs). Generation stays inside the official executable; Bookside does not call its internal image endpoint directly.

Provider limits and any account-level extra-usage settings remain controlled by the provider. The prototype does not advertise unlimited usage or report the Pi adapter's placeholder token/cost fields as billing estimates.

## Build and install

The chat needs Node.js 22.19 or later at runtime and the official Claude Code and/or Codex executables. pnpm and Bun build the bridge as part of every [source build](../../docs/01-getting-started.md#source-build-requirements). Tested local executors: Claude Code 2.1.303 and Codex 0.163.0. Older versions may lack the isolation flags.

Every build bundles the bridge, including the release DMGs and the Homebrew cask:

```sh
./scripts/build-app.sh
./scripts/install-local.command
```

Conversations live in the library database's conversations table, and executor state lives under the library directory's `Agent/` folder. Through 0.2.0 the chat shipped as a separate `Bookside Pi.app` (`org.nomadamas.bookside.pi`) that shared the same library, so its conversations and Codex sign-in appear in Bookside. `install-local.command` reports a remaining preview app; quit it and move it to the Trash.

Open **Settings > Pi** and use the official connection buttons. Pi is on unless the advanced
direct-request switch is turned on. Choose the executor/model there or in the composer. Claude uses the official `sonnet`, `opus`
and `haiku` aliases; Codex lists models returned by the signed-in official App Server.
Automatic selection follows the executor default. Claude can use an existing official CLI
subscription login. Codex deliberately uses a separate app-owned configuration directory,
so it needs its own initial ChatGPT sign-in. The app cannot finish account verification
on the user's behalf.

The bridge is bundled, but the executors and Node runtime are not redistributed. Pi dependencies are pinned to 0.85.1. The build includes notices only for dependencies actually present in Bun's output metadata and fails if a required notice is absent. The shared Pi MIT notice is copied from upstream revision `d981de1229ef899957bbe968bc8dcda02a21f477` because its npm packages omit the monorepo license file.

## Verification

- All 60 Swift tests passed on macOS 26.6.2 / Apple Silicon with Swift 6.4. They cover persistence/undo conflicts, preserved unsent drafts, shortcuts, asset boundaries, generated-image validation/reopen/undo, bounded book retrieval, page continuations, source links, coverage persistence, MCP initialization, Markdown fences, renderer URLs, small pipe frames and stale replies on book switches.
- All 20 Bun tests and the TypeScript check passed with Node 26.8.1 and Bun 1.4.0. They cover English instructions, automatic defaults, isolated executor profiles, explicit model forwarding, Pi/direct streaming, reading progress/source events, latest-response usage, image-only replies, large image events, duplicate images, failure/cancellation and billing guards. Linux CI verifies these credential-free paths and bundled notices.
- Earlier tool-free Claude Max requests returned Korean and English explanations. The current reading profile exposed exactly four scoped bookside tools, one bookside MCP server and no skills. Live Claude requests retrieved a distant warranty passage, refused to infer its value after narrowing the scope to pages 1–3, and read all six fixture pages before summarizing both chapters.
- On 2026-10-19, a fresh official Codex App Server process confirmed the app-owned ChatGPT subscription login. A native Pi/Codex request returned a 1312 by 1199 PNG plus a source-grounded explanation. The app displayed it, enlarged it, copied it, exported identical PNG bytes, and restored it after clear/undo and relaunch. The same book then continued through Claude Sonnet without losing the generated image. No credentials were copied.
- Native checks with authored PDFs verified library return, all four book tools, search, clear/undo, custom shortcuts, account controls, selected Sonnet inference, question edit/regeneration/undo, interactive HTML and M4A playback. Media, model choice and shortcuts survived relaunch. Automatic mode selected both a Markdown table and Mermaid for a comparison/process question without either format being explicitly requested. [Account acceptance](https://github.com/NomaDamas/bookside/issues/8) and [automatic/image evidence](evidence/automatic-learning-checks.json) record the boundaries.
- On 2026-10-20 the Pi panel layout passed 68 Swift tests, including status checks that leave the panel enabled, Settings sign-in that keeps the conversation engine, composer block reasons, scope labels and conversation copy. A native debug build with an isolated library and a seeded synthetic conversation showed the empty, conversation, inline-edit, minimum-width (320 pt), disconnected-Codex and Settings > Pi states; menus were checked through their accessibility items. No model request or sign-in was made.
- Native screenshots use authored synthetic PDF pages. Private source books, notes, account tokens and raw authentication URLs must not be committed as evidence.
- On 2026-10-20, the original five-tool MCP protocol and the four-tool scoped protocol passed after the real synthetic OCR prerequisite. A real Codex App Server listed all four reading tools after the compatibility fix. Codex inference then returned the account usage limit, so live book-retrieval answers through Codex remain unverified in [issue #15](https://github.com/NomaDamas/bookside/issues/15); no alternate billing route was used. See [book-scope evidence](evidence/book-reading-checks.json).

Private logs and fixtures live in `.runtime/reader-workspace-qa/`; earlier bridge checks
remain in `.runtime/pi-agent-qa/`. `BOOKSIDE_DATA_DIR` isolates QA library data.
`BOOKSIDE_AGENT_DATA_DIR`, when explicitly set for local QA, selects the app-owned agent
directory independently so credentials do not need to be copied between profiles.
