# Plan: Cmd+/- Zoom and Cmd+0 Reset

## Context

The app has a `fontSizeScript` in `MarkdownDocumentModel.swift` that listens for Cmd+=/-, Cmd+0 keydown events inside the WKWebView. However, macOS/SwiftUI intercepts these shortcuts at the app level before they reach the web view. There are no View menu items for zoom, making the feature undiscoverable and non-functional.

## Changes

### 1. Expose zoom functions from `fontSizeScript` (`MarkdownDocumentModel.swift:428-449`)

Refactor the IIFE to expose `window.__zoomIn()`, `window.__zoomOut()`, and `window.__zoomReset()` functions so they can be called from Swift via `evaluateJavaScript`. Keep the keydown listener as a fallback.

```javascript
window.__zoomIn = function() { ... };
window.__zoomOut = function() { ... };
window.__zoomReset = function() { ... };
```

### 2. Add View menu items (`QuickLookMarkdownApp.swift`)

Add a `CommandGroup` in the `commands` block with:

- **Zoom In** — `Cmd+=` (`.keyboardShortcut("=")` or `"+"`)
- **Zoom Out** — `Cmd+-` (`.keyboardShortcut("-")`)
- **Actual Size** — `Cmd+0` (`.keyboardShortcut("0")`)

Each calls `evalJS("window.__zoomIn()")` etc. Place under `CommandGroup(replacing: .textSize)` or `CommandGroup(after: .toolbar)` in the View menu area.

### Files to modify

- `QuickLookMarkdownApp/MarkdownDocumentModel.swift` — refactor `fontSizeScript` to expose callable functions
- `QuickLookMarkdownApp/QuickLookMarkdownApp.swift` — add View > Zoom menu items with keyboard shortcuts

## Verification

1. Build and run the app
2. Open a markdown file
3. Cmd+= should increase font size, Cmd+- should decrease, Cmd+0 should reset to default
4. Menu bar should show View > Zoom In / Zoom Out / Actual Size with correct shortcuts
