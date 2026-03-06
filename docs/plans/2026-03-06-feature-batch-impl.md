# Feature Batch Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Implement 10 features across 3 phases: quick editor wins, medium UI features, and larger subsystems.

**Architecture:** All features modify existing files. Editor features go in MarkdownEditorView.swift, preview features in MarkdownDocumentModel.swift (JS scripts) and ContentView.swift (WebView coordination), menus in QuickMDApp.swift.

**Tech Stack:** SwiftUI, WKWebView, CodeEditorView, NSTextView, AppKit

---

## Phase 1: Quick Wins

### Task 1: Auto-show editor on double-click

**Files:**
- Modify: `QuickMDApp/ContentView.swift:100-106` (dblclick handler)
- Modify: `QuickMDApp/ContentView.swift:59-68` (WebViewStore)
- Modify: `QuickMDApp/ContentView.swift:652` (onAppear)

Add `showEditorCallback: (() -> Void)?` to WebViewStore. Wire it in onAppear to set `showEditor = true`. In dblclick handler, if `findEditorTextView()` returns nil, call the callback, delay 0.5s, then call `jumpEditorToWord`.

### Task 2: Empty tabs on launch cleanup

**Files:**
- Modify: `QuickMDApp/QuickMDApp.swift:17-26` (applicationDidFinishLaunching)
- Modify: `QuickMDApp/ContentView.swift:663-673` (onAppear empty tab logic)

Improve empty tab detection: check `representedURL` instead of counting windows. Only close blank windows when another window has content.

### Task 3: Spell check toggle

**Files:**
- Modify: `QuickMDApp/QuickMDApp.swift` (add AppStorage + menu toggle)
- Modify: `QuickMDApp/MarkdownEditorView.swift` (apply on appear)

Add `@AppStorage("spellCheck")` (default true). Toggle in Tools menu sets `textView.isContinuousSpellCheckingEnabled`. Apply setting on editor appear.

### Task 4: Auto-pair markdown syntax

**Files:**
- Modify: `QuickMDApp/MarkdownEditorView.swift` (AutoPairHandler + installer)
- Modify: `QuickMDApp/QuickMDApp.swift` (toggle)

Install NSEvent local monitor on editor NSTextView. Handle pairs: `**`/`**`, `*`/`*`, backtick/backtick, `~~`/`~~`, `(`/`)`, `[`/`]`, `{`/`}`. Code fence: backticks + Enter inserts closing fence. Wrap selection when selected. Skip closing char if next char matches. Toggleable via `@AppStorage("autoPair")`.

### Task 5: Word count status bar

**Files:**
- Modify: `QuickMDApp/MarkdownEditorView.swift` (EditorStatusBar view)

Add `EditorStatusBar` showing `Ln X, Col Y | Words: N | Chars: N | ~N min read`. Place below CodeEditor in MarkdownEditorView body. Derive line/col from CodeEditor.Position, word count from text split.

---

## Phase 2: Medium Features

### Task 6: Custom CSS Themes menu

**Files:**
- Modify: `QuickMDApp/MarkdownDocumentModel.swift` (add builtInThemes array)
- Modify: `QuickMDApp/QuickMDApp.swift` (expand Theme menu)

Add `static let builtInThemes: [(name: String, css: String)]` with GitHub (empty/default), Dracula, Solarized Light, Solarized Dark, Nord, Sepia. Each theme overrides .markdown-body colors, pre/code backgrounds, link/heading colors. Expand Theme menu: built-in themes, Force Light/Dark, user custom CSS files from themes directory, "Custom CSS..." file picker that copies to themes dir, "Open Themes Folder" button.

### Task 7: Export to HTML

**Files:**
- Modify: `QuickMDApp/QuickMDApp.swift` (add menu item)

Add "Export as HTML..." (Cmd+Shift+H) after PDF export. Write `model.html` directly to user-chosen file via NSSavePanel. Full self-contained HTML with inlined JS/CSS.

### Task 8: Search across preview and editor

**Files:**
- Modify: `QuickMDApp/ContentView.swift` (SearchBar view, search methods, state)
- Modify: `QuickMDApp/MarkdownDocumentModel.swift` (JS search highlight script)
- Modify: `QuickMDApp/QuickMDApp.swift` (modify Find menu item)

Add JS script `searchHighlightScript` with `__searchHighlight(query)`, `__searchScrollTo(idx)`, `__searchClear()` that wraps text matches in `<mark>` tags. Add `SearchBar` SwiftUI view at top of ContentView with query field, match count, prev/next/close buttons. Cmd+F toggles the bar. `performSearch` highlights in both preview (via JS) and editor (via NSTextStorage attributes). Navigation scrolls both panes to current match.

---

## Phase 3: Larger Features

### Task 9: Preserve scroll position on auto-reload

**Files:**
- Modify: `QuickMDApp/ContentView.swift:59-68` (WebViewStore flags)
- Modify: `QuickMDApp/ContentView.swift:280-296` (didFinish handler)
- Modify: `QuickMDApp/MarkdownDocumentModel.swift:246-265` (startWatching)

Add `isFileWatcherReload` and `preReloadScrollFraction` to WebViewStore. In startWatching event handler, capture scroll fraction via JS before calling load(), set flag. In didFinish, if flag is set, restore scroll position using `__setScrollFraction`.

### Task 10: Image paste and drag-drop

**Files:**
- Modify: `QuickMDApp/MarkdownEditorView.swift` (ImagePasteHandler + installer)
- Modify: `QuickMDApp/ContentView.swift` (pass currentFileURL to editor)

Install NSEvent monitor for Cmd+V on editor textView. Check NSPasteboard for PNG/TIFF/image file URLs. On image: generate `image-YYYYMMDD-HHmmss.png`, create `images/` subdir next to .md file, write PNG, insert `![](images/filename)` at cursor. If no file saved yet, show alert. Add `currentFileURL` closure property to MarkdownEditorView, pass `model.currentURL` from ContentView.
