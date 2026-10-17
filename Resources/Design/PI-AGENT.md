# Pi learning-agent experiment

This branch adds a native chat panel to Bookshelf. It uses Pi agent core for conversation state and streaming, with adapters that invoke unmodified official executables. The same panel can bypass Pi to compare the extra layer. The default is Pi enabled. Each message records the selected harness and learning profile; Pi replies are labeled accordingly.

## Scope

- Ask about the current PDF page, selected text and optionally the book notebook.
- Choose Claude or Codex, preserving the app's book-specific conversation.
- Choose a model and one of three learning profiles: plain explanation, comparison table or visual explanation.
- Use an English system prompt while answering in the user's requested language.
- Stream replies, stop a request, save a completed reply to the notebook and return to the question's PDF page.
- Store conversations in a separate SQLite table with revision checks. Chats do not count as notebook items unless explicitly copied to the notebook.
- Edit a question and regenerate from that point, retry an answer, remove a conversation tail or clear the chat. Up to ten prior edits can be restored, including after reopening the app.
- Read official per-request token usage and context-window size, when the executor provides them.
- View Mermaid, SVG, images and offline HTML; open user-selected audio/video with native playback controls.

The experiment does not add whole-library semantic retrieval, audio synthesis, arbitrary external skills or autonomous file-editing tools. HTML can run inline interaction code inside an isolated offline preview. The existing external MCP server stays read-only.

## Reading workspace and controls

Opening a PDF switches the left sidebar to pages, notes, excerpts and search. The document
stays in the center and the dedicated AI panel stays on the right. Both panels can collapse
through native AppKit split-view animation. The toolbar's **서재** button remains available
when the left sidebar is hidden.

The layout follows the Preview document/sidebar structure. Surfaces, composer density and
motion easing reuse the existing Aside source study; see [design](DESIGN.md). Settings are
split into General, AI connections and Shortcuts. The AI section owns Pi, official account
login/status and model selection. The shortcut recorder detects conflicts, saves choices
to the local database and supports resetting defaults.

The context indicator shows the latest request's input plus output tokens, not a lifetime
total or a guessed remaining balance. Claude input includes cache reads and cache creation;
Codex uses the `last` token breakdown. Missing usage/window metadata is shown as unavailable.
Older conversations remain readable without these optional fields.

Mermaid 11.17.2 and DOMPurify 3.4.17 are bundled locally. Mermaid uses strict mode; SVG is
sanitized. HTML runs in an opaque iframe with inline scripts/styles, data images and no
network, forms, file access, popups or top-level navigation. Native bridge messages from
child frames are rejected. The large preview supports zoom and source viewing.

The attachment button imports user-selected media into `ChatAssets/` and stores references
with that book. Audio supports play/pause, seeking and playback speed through AVFoundation.
External HTTPS media requires an explicit load action. Model-supplied local paths do not
grant filesystem access. Imported files are display material and are not sent to the model.

## Execution boundary

```text
SwiftUI chat and PDF context
    -> local JSONL bridge
    -> Pi agent core (optional)
    -> official Claude Code CLI OR official Codex App Server
    -> native response and per-book conversation storage
```

Pi does not receive provider credentials and does not use its direct Anthropic or OpenAI OAuth providers. Authentication remains inside the corresponding official executable. No API key fallback is configured. The bridge uses an allowlist of environment variables, so inherited API keys, alternate endpoints and OAuth token variables cannot silently change the selected subscription route.

The complete conversation is stored by Bookshelf. Each request includes at most the latest 12 completed messages, each capped at 6000 characters, plus the current question. Switching engines starts a fresh executor request with that context; it does not transplant provider-private reasoning, caches or opaque session state. The supplied page is capped at 10000 characters, notebook at 4000 and selection at 3000. Older context is omitted, not silently summarized.

## Learning profile isolation

`Sources/BookshelfAgent/instructions.ts` is the instruction source. Build output contains a generated `profile.json`, which the app's information button reads. The bridge does not discover skills, plugins or instructions from user/project directories.

- Claude uses `--safe-mode`, `--restricted`, `--disable-slash-commands`, `--tools ""`, `--disallowedTools "mcp__*"`, `--strict-mcp-config` and `--system-prompt`. `--bare` is deliberately excluded because it disables the subscription/keychain authentication path. The adapter rejects a run if its initialization event advertises any tools, MCP servers or skills.
- Codex rejects unknown configuration keys with `--strict-config` and uses a dedicated `CODEX_HOME` under Bookshelf's data directory and a dedicated working directory. It overrides the base instructions, disables automatic skill instructions and bundled skills, sets `project_doc_max_bytes=0`, disables shell/plugins/apps/multi-agent/image/view-image/skill-search/tool-suggest/sleep/web-search features and uses read-only sandboxing with no approval escalation. The app rejects unexpected client-side tool or credential requests and cancels the executor if tool-execution items appear in its event stream. Some fixed Codex runtime behavior and vendor-managed policies remain; this is not a claim that every internal tool or policy is replaced.
- Vendor and administrator-managed policies still apply. The app does not attempt to bypass them.

The learning guidelines borrow clarity principles from ASD-STE100, adapted to the user's response language. They are not a claim of certified STE compliance. Source material is explicitly treated as reference data. Answers must distinguish supplied text from added examples, and cite PDF indices using `[p. N]`.

## Account and policy basis

Reviewed 2026-10-16. These links document the implemented route, not a blanket legal assurance or an exemption from account-specific limits.

- [Claude Code legal and compliance](https://code.claude.com/docs/en/legal-and-compliance#can-customers-offer-claude-code-in-their-products) permits offering an unmodified Claude Code executable under the described conditions. Each user authenticates with their own account; the product must not collect or intermediate their subscription credentials or resell usage. The page expressly distinguishes an end user signing into the official binary from a third party routing extracted subscription tokens.
- [Claude plan / Agent SDK guidance](https://support.claude.com/en/articles/15036540-use-the-claude-agent-sdk-with-your-claude-plan) describes subscription usage for the SDK, `claude -p` and third-party applications. This app chooses the official locally installed executable and its own account flow.
- [Claude CLI reference](https://code.claude.com/docs/en/cli-reference) documents safe/restricted mode, tool restrictions and full system-prompt replacement. Authentication remains enabled in safe mode.
- [Codex App Server authentication](https://learn.chatgpt.com/docs/app-server#auth-endpoints) permits the local/open-source integration route described there. Commercial or hosted services require the appropriate Sign in with ChatGPT path. This prototype is a local personal/open-source app, with no hosted service or credential relay.

Provider limits and any account-level extra-usage settings remain controlled by the provider. The prototype does not advertise unlimited usage or report the Pi adapter's placeholder token/cost fields as billing estimates.

## Build and local preview

Requirements in addition to the native build: Node.js 22.19 or later at runtime, pnpm and Bun for building the bridge, plus the official Claude Code and/or Codex executables. Tested local executors: Claude Code 2.1.301 and Codex 0.163.0. Older versions may lack the isolation flags.

```sh
./scripts/install-pi-preview.command
open "$HOME/Applications/Bookshelf Pi.app"
```

The ordinary build keeps the existing external-AI workflow and does not require Node, pnpm or Bun. The preview script opts into the bridge with `BOOKSHELF_INCLUDE_AGENT=1`.

This installs a separate `Bookshelf Pi.app` with a bundle ID derived from the canonical identifier with a `.pi` suffix (`org.nomadamas.bookshelf.pi` currently); the existing Bookshelf app remains installed. It shares the normal library and notebook database, and adds the conversations table. The preview does not register the `bookshelf` URL scheme.

Open **Settings > AI 연결**, enable Pi and use the official connection buttons. Choose
the executor/model there or in the chat composer. Claude uses the official `sonnet`, `opus`
and `haiku` aliases; Codex lists models returned by the signed-in official App Server.
Automatic selection follows the executor default. Claude can use an existing official CLI
subscription login. Codex deliberately uses a separate app-owned configuration directory,
so it needs its own initial ChatGPT sign-in. The app cannot finish account verification
on the user's behalf.

The bridge is bundled, but the executors and Node runtime are not redistributed. Pi dependencies are pinned to 0.85.1. The build includes notices only for dependencies actually present in Bun's output metadata and fails if a required notice is absent. The shared Pi MIT notice is copied from upstream revision `d981de1229ef899957bbe968bc8dcda02a21f477` because its npm packages omit the monorepo license file.

## Verification

- All 52 Swift tests passed on macOS 26.6.2 / Apple Silicon with Swift 6.4. They cover persistence/undo conflicts, preserved unsent drafts, shortcuts, asset boundaries, Markdown fences, renderer URLs, Unicode and small pipe frames, and stale replies on book switches.
- All nine Bun tests and the TypeScript check passed with Node 26.8.1 and Bun 1.4.0. They cover English instructions, isolation, explicit model forwarding, Pi/direct streaming, reported token usage, unexpected-tool rejection, subscription-mode billing guards and cancellation. Linux CI verifies these credential-free paths and bundled notices.
- Real Claude Max requests through Pi returned Korean and English source-grounded explanations with empty tools, MCP-server and skill lists.
- Codex App Server startup and unauthenticated account status were checked with the final strict configuration. Live subscription inference requires completing the app-owned login.
- Native checks with authored PDFs verified library return, all four book tools, search, clear/undo, custom shortcuts, account controls, selected Sonnet inference, question edit/regeneration/undo, interactive HTML and M4A playback. Media, model choice and shortcuts survived relaunch. Live Codex sign-in remains tracked in [issue #8](https://github.com/NomaDamas/bookshelf/issues/8).
- Native screenshots use authored synthetic PDF pages. Private source books, notes, account tokens and raw authentication URLs must not be committed as evidence.

Private logs and fixtures live in `.runtime/reader-workspace-qa/`; earlier bridge checks
remain in `.runtime/pi-agent-qa/`. `BOOKSHELF_DATA_DIR` isolates QA library data.
`BOOKSHELF_AGENT_DATA_DIR`, when explicitly set for local QA, selects the app-owned agent
directory independently so credentials do not need to be copied between profiles.
