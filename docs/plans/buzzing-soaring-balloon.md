# Plan: Add 15 Features to QuickMD

## Context
QuickMD is a macOS Quick Look extension + standalone app. The app uses SwiftUI + WKWebView with scripts injected via WKUserScript. The extension inlines scripts in HTML. Both share Resources/ and swift-markdown. We're adding 15 features across 3 phases.

**Pattern for new JS features:** Add `static let` in MarkdownDocumentModel → inject via WKUserScript in ContentView → inline `<script>` in PreviewViewController → CSS in both `wrapHTML()` methods.

## Critical Files
- `QuickMDApp/MarkdownDocumentModel.swift` — all scripts, CSS, HTML generation
- `QuickMDApp/ContentView.swift` — WKUserScript injection, WebView setup
- `QuickMDApp/QuickMDApp.swift` — menus, keyboard shortcuts
- `QuickMDPreviewExtension/PreviewViewController.swift` — extension mirror (inline scripts)

---

## Phase 1: JS/CSS Features (both app + extension)

### 1. Print Stylesheet [S]
- Add `@media print` CSS block in both `wrapHTML()` methods
- Hide TOC, copy buttons, speak button, find bar, reading stats
- Optimize: `page-break-after: avoid` on headings, `page-break-inside: avoid` on pre/table
- Show link URLs after anchor text

### 2. Task Lists [S]
- Test if `HTMLFormatter.format()` outputs checkbox HTML for `- [ ]` / `- [x]`
- If yes: CSS-only (style `input[type="checkbox"]` in `.markdown-body li`)
- If no: Add `taskListScript` JS to post-process `<li>` text nodes into checkbox elements
- CSS: remove list bullets for task lists, style checkboxes

### 3. Word Wrap Toggle [S]
- Add `static let wordWrapScript` — toggles `white-space: pre-wrap` on `<pre>` blocks
- Expose `window.__toggleWordWrap`
- Menu: Tools > Toggle Word Wrap (Cmd+Option+W)

### 4. Anchor Links [S]
- Add `static let anchorLinksScript` — runs AFTER TOC script (which assigns heading IDs)
- Prepend `<a class="heading-anchor" href="#slug">#</a>` to each heading
- CSS: hidden by default, visible on heading hover, dark mode variants

### 5. Emoji Shortcodes [S]
- Add `static let emojiScript` with ~200-entry shortcode→Unicode map
- Walk text nodes in `.markdown-body`, skip `<pre>`/`<code>` ancestors
- Replace `:shortcode:` with emoji character
- Run before highlight.js

### 6. Footnotes [M]
- Add `static let footnotesScript` — JS post-processor:
  - Find `[^id]` references in text nodes (not in code), replace with superscript links
  - Find `[^id]: text` definition paragraphs, collect and remove from flow
  - Append `<section class="footnotes"><hr><ol>...</ol></section>` with backlinks
- Run early, before highlight.js
- CSS: smaller font, styled separator, superscript links

### 7. Frontmatter [M]
- **Swift** (both targets): In `htmlBody(for:)`, detect `---` delimited YAML at file start, strip before markdown conversion, embed raw YAML in hidden `<div id="frontmatter-data">`
- **JS**: `frontmatterScript` uses `jsyaml.load()` (already bundled) to parse, renders styled banner with title/date/author/tags
- CSS: subtle background, tag pills, border-bottom
- Run after js-yaml loaded, before reading stats

---

## Phase 2: App-Only Swift Features

### 8. Auto-Detect Encoding [S]
- Both targets: Replace `String(contentsOf:encoding:.utf8)` with fallback chain
- Try: UTF-8 → `NSString.stringEncoding(for:)` → UTF-16 → Latin-1
- In `htmlBody(for:)` and `load(from:)`

### 9. Recent Files [S]
- In `load(from:)`: call `NSDocumentController.shared.noteNewRecentDocumentURL(url)`
- Menu: File > Open Recent submenu with recent URLs + Clear Menu
- Use `NSDocumentController.shared.recentDocumentURLs`

### 10. Export to PDF [S]
- Menu: File > Export as PDF... (Cmd+Shift+E)
- `NSSavePanel` → `WebViewStore.shared.webView.createPDF(configuration:)` → write data
- Print stylesheet (Feature 1) automatically cleans output

### 11. Live Reload [M]
- Add `DispatchSource.makeFileSystemObjectSource` file watcher to MarkdownDocumentModel
- `@Published var autoReload = false`, `startWatching(url:)` / `stopWatching()`
- On file change: 100ms delay then `load(from:)`
- Menu: Tools > Auto-Reload toggle (Cmd+Shift+A)

### 12. Custom CSS Themes [M]
- Scan `~/Library/Application Support/QuickMD/themes/` for `.css` files on startup
- `@AppStorage("customTheme")` stores selected filename
- In `wrapHTML()`: append custom CSS after built-in styles
- Theme menu: list built-in + discovered custom themes

### 13. Presentation Mode [M]
- Add `static let presentationScript` — JS-only implementation:
  - `window.__startPresentation()` splits `.markdown-body` children on `<hr>` into slides
  - Fullscreen overlay, one slide at a time, centered content
  - Arrow keys / click to navigate, Escape to exit, slide counter
- CSS: fullscreen overlay, large centered text, dark mode variants
- Menu: Tools > Presentation Mode (Cmd+Shift+P)

### 14. File Tabs [M]
- Use macOS native window tabbing (simplest approach)
- Set `NSWindow.allowsAutomaticWindowTabbing = true` in `applicationDidFinishLaunching`
- Each new file opens in new window → user can merge into tabs via Window menu
- Minimal code changes

---

## Phase 3: Split Editor + Image Paste

### 15. Split Editor [L]
- Create `MarkdownEditorView: NSViewRepresentable` wrapping `NSTextView` in `NSScrollView`
- `ContentView` becomes `HSplitView`: editor left, WebView right
- Model: add `@Published var rawContent: String`, populate on `load(from:)`
- Debounced re-render (300ms) on rawContent changes
- Save: `func save()` writes rawContent to file, wire to Cmd+S
- Toggle: Tools > Show Editor (Cmd+\)
- Entitlements: add `com.apple.security.files.user-selected.read-write`

### 16. Image Paste [M] (requires Split Editor)
- In editor's `NSTextView`, override paste to detect image on pasteboard
- Save as `pasted-image-TIMESTAMP.png` next to the markdown file
- Insert `![](pasted-image-TIMESTAMP.png)` at cursor
- Trigger re-render

---

## Implementation Order

Execute in this order (small → large, dependencies respected):

1. Print Stylesheet [S]
2. Task Lists [S]
3. Word Wrap Toggle [S]
4. Anchor Links [S]
5. Emoji Shortcodes [S]
6. Auto-Detect Encoding [S]
7. Recent Files [S]
8. Export to PDF [S]
9. Footnotes [M]
10. Frontmatter [M]
11. Live Reload [M]
12. Custom CSS Themes [M]
13. Presentation Mode [M]
14. File Tabs [M]
15. Split Editor [L]
16. Image Paste [M]

## Verification
1. `xcodegen generate && xcodebuild -scheme QuickMDApp build` succeeds
2. `xcodebuild -scheme QuickMDTests test` — all tests pass (add tests for new features)
3. Playwright browser verification for JS features (footnotes, emoji, frontmatter, presentation, etc.)
4. Manual test: Quick Look extension renders correctly for markdown + code files
