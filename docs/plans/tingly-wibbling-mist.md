# Refactor: Line-Anchored Sync Algorithm + Native SwiftUI Sidebars

## Context

Two problems, one fix:

1. **Scroll sync is fraction-based** — `scrollTop / scrollHeight` ratio mapped between editor and renderer. This desyncs immediately on headings, images, lists, or any formatting where rendered block heights differ from source line counts. The Grok conversation correctly identifies this as broken and prescribes `data-source-line` anchored mapping.

2. **Sidebars are HTML/JS inside the WKWebView** — ~600 lines of JS + ~200 lines of CSS. Native sidebars are faster, feel better, and integrate with macOS properly.

The sync algorithm must be fixed **first** because it becomes the shared foundation: TOC clicks, comment jumps, and scroll sync all use the same line-anchored mapping.

**Goal**: Replace fraction-based sync with line-anchored sync using `data-source-line`, then migrate sidebars to native SwiftUI using the same line-based navigation.

## Critical Files

- [MarkdownDocumentModel.swift](QuickMDApp/MarkdownDocumentModel.swift) — Replace `editorSyncScript` with line-anchored version; remove sidebar JS/HTML/CSS; add `headingDataScript`
- [ContentView.swift](QuickMDApp/ContentView.swift) — Replace `scrollEditorToFraction` with `scrollEditorToLine`; replace `onScrollFractionChange` with `onTopLineChange`; restructure layout for native sidebar
- [MarkdownEditorView.swift](QuickMDApp/MarkdownEditorView.swift) — Replace `ScrollFractionObserver` with `TopLineObserver` that reports the line number at top of editor viewport
- [QuickMDApp.swift](QuickMDApp/QuickMDApp.swift) — Update sidebar menu items to use SwiftUI state
- **New file**: `QuickMDApp/SidebarView.swift` — Native SwiftUI sidebar (activity bar, TOC, Comments, Files)
- [PreviewViewController.swift](QuickMDPreviewExtension/PreviewViewController.swift) — Remove sidebar HTML/CSS/JS
- [EditorRendererSyncE2ETests.swift](QuickMDTests/EditorRendererSyncE2ETests.swift) — Update tests

---

## Phase 0: Line-Anchored Sync Algorithm (Foundation)

This replaces the current fraction-based sync with `data-source-line` element mapping. The app already injects `data-source-line` on every block element via `SourceMappedHTMLFormatter` (line 2506) — that stays unchanged.

### 0.1 Replace `editorSyncScript` (MarkdownDocumentModel.swift, lines 1696-1791)

**Current**: Fraction-based. JS reports `scrollTop / (scrollHeight - clientHeight)` as a 0-1 fraction. Swift applies same fraction to editor.

**New**: Line-anchored. JS finds the topmost visible `[data-source-line]` element and reports its line number + how far the element is scrolled past the viewport top (element visibility fraction for sub-line smoothness).

```javascript
(function() {
  var syncEnabled = true;
  window.__editorSyncPause = function() { syncEnabled = false; };
  window.__editorSyncResume = function() { syncEnabled = true; };

  // Find the topmost visible element with data-source-line
  function getTopVisibleLine() {
    var elements = document.querySelectorAll('[data-source-line]');
    var viewportTop = 0; // relative to documentElement
    var best = null;
    var bestTop = Infinity;

    for (var i = 0; i < elements.length; i++) {
      var rect = elements[i].getBoundingClientRect();
      // Find element whose top is closest to (but >= 0) or the last element above viewport
      if (rect.bottom > 0) {
        // This element is at least partially visible
        var line = parseInt(elements[i].getAttribute('data-source-line'), 10);
        // fractionPast: how much of this element is above the viewport top (0 = just appeared, 1 = fully scrolled past)
        var fractionPast = 0;
        if (rect.top < 0 && rect.height > 0) {
          fractionPast = Math.min(1, -rect.top / rect.height);
        }
        return { line: line, fractionPast: fractionPast };
      }
    }
    return null;
  }

  // Report scroll position as line number to Swift
  var scrollTimer = null;
  function onScroll() {
    if (!syncEnabled) return;
    if (scrollTimer) clearTimeout(scrollTimer);
    scrollTimer = setTimeout(function() {
      var info = getTopVisibleLine();
      if (info && window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.editorSync) {
        window.webkit.messageHandlers.editorSync.postMessage({
          type: 'scroll', line: info.line, fractionPast: info.fractionPast
        });
      }
    }, 30);
  }

  window.addEventListener('scroll', onScroll, {passive: true});

  // Expose function for Swift to scroll renderer to a specific source line
  window.__scrollToLine = function(line, fractionPast) {
    fractionPast = fractionPast || 0;
    var elements = document.querySelectorAll('[data-source-line]');
    var target = null;
    // Find the element with the largest data-source-line <= line
    for (var i = 0; i < elements.length; i++) {
      var elLine = parseInt(elements[i].getAttribute('data-source-line'), 10);
      if (elLine <= line) target = elements[i];
      else break;
    }
    if (target) {
      var rect = target.getBoundingClientRect();
      var scrollOffset = rect.top + window.scrollY - (fractionPast * rect.height);
      window.scrollTo({ top: Math.max(0, scrollOffset), behavior: 'auto' });
    }
  };

  // Expose getTopVisibleLine for external queries
  window.__getTopVisibleLine = getTopVisibleLine;

  // Keep __setScrollFraction as deprecated fallback during transition
  window.__setScrollFraction = function(fraction) {
    var el = document.documentElement;
    var maxScroll = el.scrollHeight - el.clientHeight;
    if (maxScroll > 0) el.scrollTop = fraction * maxScroll;
  };

  // Double-click handling (unchanged from current)
  document.addEventListener('dblclick', function(e) {
    // ... existing dblclick code stays exactly the same ...
  });
})();
```

### 0.2 Replace `scrollEditorToFraction` with `scrollEditorToLine` (ContentView.swift, lines 386-401)

**Current**: `scrollEditorToFraction(_ fraction: CGFloat)` — applies `fraction * maxScroll` to editor.

**New**: `scrollEditorToLine(_ line: Int, fractionPast: CGFloat)` — finds the character offset of `line` in source text, scrolls that line to the top of the editor viewport, then adjusts by `fractionPast`.

```swift
private func scrollEditorToLine(_ line: Int, fractionPast: CGFloat = 0) {
    guard let model = AppDelegate.activeModel,
          let textView = findEditorTextView(),
          let scrollView = textView.enclosingScrollView,
          let layoutManager = textView.layoutManager,
          let textContainer = textView.textContainer else { return }

    let source = model.rawContent
    let adjustedLine = line + model.frontmatterLineCount - 1 // 0-based
    let lines = source.components(separatedBy: "\n")
    guard adjustedLine >= 0 && adjustedLine < lines.count else { return }

    // Calculate character offset for this line
    var charOffset = 0
    for i in 0..<adjustedLine {
        charOffset += lines[i].count + 1 // +1 for newline
    }

    // Get the glyph rect for this character position
    let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: min(charOffset, (source as NSString).length - 1), length: 1), actualCharacterRange: nil)
    let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

    // Scroll to this line, offset by fractionPast * line height
    WebViewStore.shared.suppressEditorToRenderer = true
    let targetY = lineRect.origin.y + (fractionPast * lineRect.height) - textView.textContainerInset.height
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, targetY)))
    scrollView.reflectScrolledClipView(scrollView.contentView)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
        WebViewStore.shared.suppressEditorToRenderer = false
    }
}
```

### 0.3 Update bridge handler (ContentView.swift, line 301-307)

**Current**: `case "editorSync"` with `type == "scroll"` reads `fraction`.

**New**: Reads `line` and `fractionPast` instead:

```swift
if type == "scroll" {
    guard !WebViewStore.shared.isEditReload,
          let line = body["line"] as? Int else { return }
    let fractionPast = body["fractionPast"] as? Double ?? 0
    scrollEditorToLine(line, fractionPast: CGFloat(fractionPast))
}
```

### 0.4 Replace `ScrollFractionObserver` with `TopLineObserver` (MarkdownEditorView.swift, lines 607+)

**Current**: `ScrollFractionObserver` reports `scrollView.contentView.bounds.origin.y / maxScroll` as a 0-1 fraction.

**New**: `TopLineObserver` computes the source line number visible at the top of the editor viewport:

```swift
struct TopLineObserver: NSViewRepresentable {
    var onTopLineChange: ((Int, CGFloat) -> Void)?  // (line, fractionPast)

    // On scroll, find the character at the top-left of the visible rect,
    // convert to line number, compute how far past that line we've scrolled
    func computeTopLine(from scrollView: NSScrollView, textView: NSTextView) {
        let visibleRect = scrollView.contentView.bounds
        let topPoint = NSPoint(x: textView.textContainerInset.width, y: visibleRect.origin.y + textView.textContainerInset.height)
        let charIndex = textView.layoutManager?.characterIndex(for: topPoint, in: textView.textContainer!, fractionOfDistanceBetweenInsertionPoints: nil) ?? 0

        // Count newlines up to charIndex to get line number
        let nsSource = (textView.string as NSString)
        let prefix = nsSource.substring(to: min(charIndex, nsSource.length))
        let lineNumber = prefix.components(separatedBy: "\n").count  // 1-based

        // fractionPast: how far into this line we've scrolled
        // (get the rect of this line, compute offset)
        // ... compute fractionPast similarly to JS side ...

        onTopLineChange?(lineNumber, fractionPast)
    }
}
```

### 0.5 Update editor→renderer sync (ContentView.swift, lines 1228-1248)

**Current**: `onScrollFractionChange` sends `__setScrollFraction(fraction)` to JS.

**New**: `onTopLineChange` sends `__scrollToLine(line, fractionPast)` to JS:

```swift
MarkdownEditorView(text: $model.rawContent, position: $editorPosition, onTopLineChange: { line, fractionPast in
    WebViewStore.shared.lastEditorLine = line
    guard !WebViewStore.shared.suppressEditorToRenderer else { return }
    scrollSyncTask?.cancel()
    scrollSyncTask = Task { @MainActor in
        try? await Task.sleep(nanoseconds: 50_000_000)
        guard !Task.isCancelled else { return }
        guard let webView = WebViewStore.shared.webView else { return }
        webView.evaluateJavaScript("if(window.__editorSyncPause) __editorSyncPause()") { _, _ in }
        webView.evaluateJavaScript("if(window.__scrollToLine) __scrollToLine(\(line), \(fractionPast))") { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                webView.evaluateJavaScript("if(window.__editorSyncResume) __editorSyncResume()") { _, _ in }
            }
        }
    }
})
```

### 0.6 Bidirectional guard

Keep existing pattern: `suppressEditorToRenderer` flag + `__editorSyncPause` / `__editorSyncResume`. Both prevent feedback loops. The 200ms delay after programmatic scroll gives time for scroll events to settle.

---

## Phase 1: Native SwiftUI Sidebar Views (Additive)

### 1.1 Data models

Add to `MarkdownDocumentModel.swift`:

```swift
struct TOCHeading: Identifiable, Equatable {
    let id: String       // slug ID for scrolling
    let text: String     // heading text
    let level: Int       // 1-6
    let sourceLine: Int  // data-source-line value — used for editor jump
}

enum SidebarPanel: String, CaseIterable { case toc, comments, files }

@Published var tocHeadings: [TOCHeading] = []
@Published var activeTOCHeadingID: String? = nil
@Published var parsedComments: [(range: NSRange, comment: String, annotatedText: String)] = []
```

Comments: reuse existing `parseComments(in:)` (line 2777). Populate `parsedComments` on every content change (debounced with edit).

Files: reuse existing `injectFileTree` pattern but populate a Swift `[FileNode]` instead of calling JS.

### 1.2 New `SidebarView.swift`

```
SidebarView
├── VStack(spacing: 0)
│   ├── ActivityBar (HStack of 3 icon buttons: TOC/Comments/Files)
│   │   └── Comment count badge on Comments icon
│   └── Panel content (switched by activePanel)
│       ├── .toc → TOCPanelView
│       │   ├── List of headings, indented by level
│       │   ├── Active heading highlighted (accent color)
│       │   ├── Collapsible sections via DisclosureGroup
│       │   └── Click → scrolls both preview AND editor to that line
│       ├── .comments → CommentsPanelView
│       │   ├── List of (annotatedText, commentText) from parsedComments
│       │   ├── Edit/Delete buttons on hover
│       │   └── Click → scrolls editor to comment range
│       └── .files → FilesPanelView
│           ├── Recursive List with DisclosureGroup for directories
│           └── Click → opens file via handleLinkClick
```

**TOC click** uses the new line-anchored sync:
```swift
// Scroll preview to heading
webView.evaluateJavaScript("document.getElementById('\(heading.id)')?.scrollIntoView({behavior:'smooth'})")
// Scroll editor to heading's source line
scrollEditorToLine(heading.sourceLine)
```

**Comment click** scrolls editor to comment range (existing `setSelectedRange` + `scrollRangeToVisible` code from `sidebarClick` handler, line 282-292).

### 1.3 ContentView layout change

```
VStack {
  SearchBar (conditional)
  HStack(spacing: 0) {
    if sidebarPosition == .leading && showSidebar { SidebarView(...).frame(width: sidebarWidth); ResizeHandle }
    // Main content (WebView or HSplitView with WebView + Editor)
    if sidebarPosition == .trailing && showSidebar { ResizeHandle; SidebarView(...).frame(width: sidebarWidth) }
  }
}
```

New state on ContentView:
```swift
@AppStorage("showSidebar") var showSidebar = true
@AppStorage("sidebarPosition") var sidebarPosition = "leading"
@AppStorage("sidebarWidth") var sidebarWidth: Double = 220
@State private var activePanel: SidebarPanel = .toc
```

### 1.4 Sidebar resize

Native drag gesture on a thin `Rectangle()` — updates `sidebarWidth` (min 100, max 500).

---

## Phase 2: JS Bridge for TOC Data

### 2.1 New `headingDataScript` (replaces `tocScript`)

Lightweight JS — no DOM sidebar rendering, just data extraction:
1. Assigns slug IDs to headings (same logic as current `tocScript` lines 1028-1037)
2. Posts heading list to Swift: `window.webkit.messageHandlers.tocData.postMessage([{id, text, level, sourceLine}])`
3. `IntersectionObserver` tracks active heading, posts `{activeHeadingID: "slug"}` on change
4. Exposes `window.__rebuildHeadingData()` for incremental updates after morphdom

### 2.2 New `tocData` bridge handler in `WebView.Coordinator`

```swift
case "tocData":
    if let array = body as? [[String: Any]] {
        // Full heading list update
        let headings = array.compactMap { dict -> TOCHeading? in
            guard let id = dict["id"] as? String,
                  let text = dict["text"] as? String,
                  let level = dict["level"] as? Int else { return nil }
            let sourceLine = dict["sourceLine"] as? Int ?? 0
            return TOCHeading(id: id, text: text, level: level, sourceLine: sourceLine)
        }
        DispatchQueue.main.async {
            AppDelegate.activeModel?.tocHeadings = headings
        }
    } else if let dict = body as? [String: Any], let activeID = dict["activeHeadingID"] as? String {
        DispatchQueue.main.async {
            AppDelegate.activeModel?.activeTOCHeadingID = activeID
        }
    }
```

Register in `makeNSView`: `config.userContentController.add(coordinator, name: "tocData")`

---

## Phase 3: Remove JS Sidebar (Destructive — Do Atomically)

### 3.1 Delete JS scripts from `MarkdownDocumentModel.swift`

| Script | Lines | Action |
|--------|-------|--------|
| `tocScript` | ~1000-1173 | **Delete**, replaced by `headingDataScript` |
| `commentsSidebarScript` | ~1939-2053 | **Delete**, replaced by SwiftUI `CommentsPanelView` |
| `filesBrowserScript` | ~2057-2151 | **Delete**, replaced by SwiftUI `FilesPanelView` |
| `sidebarArrangeScript` | ~2155-2228 | **Delete**, replaced by SwiftUI sidebar state |

### 3.2 Remove sidebar HTML from `wrapHTML` (lines 2798-2821)

Set `sidebarsMarkup = ""`. Keep `#layout` div but remove flex layout tied to sidebar.

### 3.3 Remove sidebar CSS (~lines 3010-3200)

Delete: `#sidebar-container`, `#sidebar-icons`, `.sidebar-icon`, `#sidebar-panels`, `.sidebar-panel`, `#sidebar-resize`, `#toc-*`, `#comments-header`, `#comments-list`, `.comment-item`, `.comment-annotated`, `.comment-text`, `.comment-actions`, `#files-*`, `.file-item`, `.dir-*`, `.comment-badge`, all `has-sidebar`/`has-toc` layout rules.

**Keep**: `.qmd-comment`, `.qmd-comment-flash` (in-content comment highlights).

### 3.4 Simplify `editorSyncScript`

Since sidebar HTML is gone, `getScrollContainer()` always returns `document.documentElement`. Remove `has-sidebar`/`has-toc` class checks.

### 3.5 Update `contentUpdateScript`

- Remove `__buildCommentsList()` calls (lines 2409, 2450)
- Remove `__buildTOC()` calls (lines 2410, 2451)
- Replace with `if (window.__rebuildHeadingData) __rebuildHeadingData();`
- Swift side re-parses comments on every debounced content update

### 3.6 Update `WKUserScript` injections in `makeNSView`

Stop injecting: `tocScript`, `commentsSidebarScript`, `filesBrowserScript`, `sidebarArrangeScript`.
Add: `headingDataScript`.

### 3.7 Keep `commentScript`

In-content comment tooltips + click-to-edit on `<mark>` elements stays — it operates on rendered content, not the sidebar.

---

## Phase 4: Update Menus & Keyboard Shortcuts

In `QuickMDApp.swift`:

- **"Toggle Sidebar"** (line 787) → toggle SwiftUI `showSidebar` via `FocusedValue`
- **"Show Comments"** (line 791) → set `activePanel = .comments` + `showSidebar = true` via `FocusedValue`
- Add **"Move Sidebar to Other Side"** menu item → toggles `sidebarPosition`

New `FocusedValueKey`s: `showSidebar`, `activePanel`, `sidebarPosition`.

---

## Phase 5: Update Quick Look Extension

Remove sidebar HTML, CSS, and JS from `PreviewViewController.swift`. The extension is read-only — no sidebar.

---

## Phase 6: Update Tests

- Remove `commentsSidebarScript` and `sidebarArrangeScript` injections from E2E test helper `loadMarkdown`
- Add `headingDataScript` to test helper
- Add E2E test: load HTML → verify `__getTopVisibleLine()` returns correct line numbers
- Add E2E test: verify `__scrollToLine(N)` scrolls to correct element
- Add E2E test: verify `tocData` bridge message with correct heading data
- Update/delete tests checking sidebar DOM elements

---

## Verification

1. **Build & install**: `make install`
2. **Line-anchored scroll sync**: Open a file with headings + images + code blocks. Scroll editor → preview follows at the correct section. Scroll preview → editor follows. No desync on large images or code blocks.
3. **Double-click jump**: Double-click word in preview → editor jumps to correct word (unchanged)
4. **TOC navigation**: Click heading in native TOC → both preview and editor scroll to that heading
5. **Active heading**: Scroll preview → correct heading highlights in TOC
6. **Comments panel**: Add comment → appears in native sidebar with badge; click → editor jumps to comment
7. **Files panel**: Shows directory contents; click opens file
8. **Sidebar toggle**: Cmd+Ctrl+S shows/hides native sidebar
9. **Sidebar position**: Move sidebar left/right via menu
10. **Sidebar resize**: Drag divider to resize
11. **Quick Look**: `qlmanage -p some.md` shows clean preview without sidebar
12. **Tests**: `make test` passes
