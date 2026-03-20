# Simplify: Code Review Fixes for Commit 42cb7ef

## Context
The latest commit ("Add native SwiftUI sidebar, extract JS to external scripts, and add morphdom incremental updates") introduced several code quality and efficiency issues alongside the positive architectural changes. This plan addresses the most impactful findings from three parallel reviews (reuse, quality, efficiency).

## Fixes (ordered by impact)

### 1. Eliminate double file read in `load(from:)`
**File:** `QuickMDApp/MarkdownDocumentModel.swift:431-432`

`htmlBody(for:)` reads the file via `readFileContent`, then `load()` calls `readFileContent` again. Fix: refactor `htmlBody` to accept content+extension, or return the raw content alongside the HTML result so `load()` doesn't re-read.

### 2. Eliminate temp file round-trip in `rerender()`
**File:** `QuickMDApp/MarkdownDocumentModel.swift:394-404`

`rerender()` writes `rawContent` to a temp file just so `htmlBody(for:)` can read it back. Fix: add an `htmlBody(content:extension:)` overload that works from a string directly.

### 3. Deduplicate scroll-to-line logic
**File:** `QuickMDApp/ContentView.swift:448-482` and `1707-1718`

The `onTOCClick` handler reimplements the same line→character offset→glyph rect→scroll calculation as `scrollEditorToLine()`. Fix: extract a shared static helper and call it from both places.

### 4. Deduplicate fragment-scroll logic
**File:** `QuickMDApp/ContentView.swift:418-419` and `739-740`

Same `scrollIntoView` JS snippet in two places. Fix: extract a `scrollToFragment(_:in:)` helper on the Coordinator.

### 5. Deduplicate file-open logic (sidebar vs coordinator)
**File:** `QuickMDApp/ContentView.swift:1746-1762` vs `402-444`

The sidebar `onFileClick` reimplements tab-opening logic from `openFileLink()`. Fix: call through to the existing coordinator method.

### 6. Use `markdownExtensions` in `scanDirectoryForMarkdown`
**File:** `QuickMDApp/MarkdownDocumentModel.swift:259`

Local `mdExts` duplicates the static `markdownExtensions`. Fix: replace with `Self.markdownExtensions`.

### 7. Return `[FileNode]` directly from `scanDirectoryForMarkdown`
**File:** `QuickMDApp/MarkdownDocumentModel.swift:257-328`

Returns `[[String: Any]]` then immediately re-parses to `FileNode`. Fix: return `[FileNode]` directly, delete `convertToFileNodes()`, and use full path for directory IDs.

### 8. Fix `SidebarResizeHandle` drag gesture
**File:** `QuickMDApp/SidebarView.swift:329-336`

`DragGesture.onChanged` adds cumulative `translation.width` to `width` each frame, causing acceleration. Fix: track start width on drag begin, compute `width = startWidth + translation`.

### 9. Make `ISO8601DateFormatter` a static let in `log()`
**File:** `QuickMDApp/MarkdownDocumentModel.swift:120`

Creates a new formatter on every log call. Fix: `private static let logFormatter = ISO8601DateFormatter()`.

### 10. Debounce `refreshParsedComments()`
**File:** `QuickMDApp/ContentView.swift:1670-1675`

Runs regex over entire document on every keystroke (not debounced like the incremental update). Fix: move inside the existing debounce block.

### 11. Eliminate triple-parse on comment edit
**Files:** `QuickMDApp/ContentView.swift:341,602,610,672-680,1777-1796`

After a comment edit, markdown is parsed up to 3 times: `setContent→rerender()`, then `forceRefreshContent→markdownBodyHTML()`. Fix: have `setContent`/`rerender` return the parsed body HTML so `pushIncrementalUpdate` can reuse it, and remove the redundant `forceRefreshContent()` calls.

### 12. Guard `refreshFileTree()` on edit-driven reloads
**File:** `QuickMDApp/ContentView.swift:746`

Called on every `didFinish` navigation including edit-driven morphdom fallbacks. Fix: skip when reloading due to edits.

## Won't fix (acknowledged but low priority)
- **PreviewViewController duplication**: The extension runs in a separate process; sharing code requires a framework. Out of scope for this cleanup.
- **`sidebarPosition` stringly-typed**: Minor — works fine, low risk of typo.
- **`isNavigatingHistory` async timing**: Requires careful investigation of window lifecycle; skip for now.
- **`commentPanelOpen` close-button failsafe**: Edge case worth a future fix.
- **content-update.js unconditional setup calls**: Would require significant refactoring of the mutation tracking for marginal gain.

## Verification
1. `make install` — app builds and installs
2. Open a markdown file — renders correctly, sidebar works
3. Double-click a TOC heading — editor scrolls to correct line
4. Edit text — incremental updates work, no visible lag
5. Resize sidebar by dragging — smooth, follows cursor
6. Open file via sidebar file browser — opens in correct tab
7. Run unit + E2E tests: `xcodebuild test -scheme QuickMDApp -only-testing QuickMDTests CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES SWIFT_VERSION=5.0 SWIFT_ENABLE_EXPLICIT_MODULES=NO ENABLE_TESTABILITY=YES`
