# Plan: Sync Editor Scroll to Preview

## Context
When editing in split view, scrolling the editor doesn't move the preview. The user expects the rendered HTML to track the editor's scroll position so they can see what they're editing.

## Approach: Percentage-Based Scroll Sync

Markdown source and rendered HTML don't have a 1:1 line mapping (images expand, code blocks change size, etc.), so exact line-based sync is unreliable. Instead, use **proportional scroll**: when the editor is 40% scrolled, scroll the WebView to 40%.

CodeEditorView's `Position.verticalScrollPosition` is the pixel offset (`documentVisibleRect.origin.y`). We compute the scroll fraction from `offset / (contentHeight - viewportHeight)` and apply the same fraction to the WebView via JavaScript.

## Changes

### 1. `MarkdownEditorView.swift` — Expose position changes
- Add an `onScrollChange: (CGFloat) -> Void` callback
- Watch `position.verticalScrollPosition` with `onChange` and call the callback with the raw pixel offset

### 2. `ContentView.swift` — Bridge editor scroll to WebView
- Store editor scroll offset in `@State`
- On change, compute scroll fraction and call `WebViewStore.shared.webView?.evaluateJavaScript(...)` to set `document.documentElement.scrollTop` proportionally
- Debounce the scroll sync (50ms) to avoid excessive JS evaluation during fast scrolling

### 3. JS scroll helper
Add a small JS snippet (either inline in ContentView or as a static property on the model) that:
```javascript
function __syncScroll(fraction) {
  var max = document.documentElement.scrollHeight - document.documentElement.clientHeight;
  document.documentElement.scrollTop = fraction * max;
}
```

## Files to Modify
| File | Change |
|------|--------|
| `QuickMDApp/MarkdownEditorView.swift` | Add `onScrollChange` callback, `onChange(of: position)` |
| `QuickMDApp/ContentView.swift` | Receive scroll offset, compute fraction, call JS on WebView |

## Verification
```bash
xcodegen generate && xcodebuild -scheme QuickMDApp build CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""
xcodebuild -scheme QuickMDTests test CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""
```
- Open a long markdown file, toggle editor with Cmd+E
- Scroll editor down — preview should follow proportionally
- Scroll to bottom of editor — preview should be at bottom
- Scroll to top — preview should return to top
