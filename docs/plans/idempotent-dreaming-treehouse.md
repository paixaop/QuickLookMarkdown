# Fix: Anchor fragment navigation when opening file links

## Context

When clicking a link like `[Security & Auth](../08-crosscutting-concepts/security-auth.md#tls-termination)`, the app opens the target file but doesn't scroll to the `#tls-termination` section. This happens because:

1. The app loads file content via `loadHTMLString(html, baseURL:)` which ignores URL fragments
2. The fragment is preserved in the URL object but never acted upon after the page loads

## Plan

### 1. Store pending fragment on `MarkdownDocumentModel`

Add a `pendingFragment: String?` property to `MarkdownDocumentModel`.

In `load(from:)` ([MarkdownDocumentModel.swift:307](QuickMDApp/MarkdownDocumentModel.swift#L307)), extract and store the fragment from the URL before loading:

```swift
pendingFragment = url.fragment
```

### 2. Scroll to fragment after page load

In `webView(_:didFinish:)` ([ContentView.swift:611](QuickMDApp/ContentView.swift#L611)), after the existing scroll-restore logic, check for a pending fragment and scroll to it:

```swift
if let fragment = AppDelegate.activeModel?.pendingFragment {
    AppDelegate.activeModel?.pendingFragment = nil
    let js = "document.getElementById('\(fragment)')?.scrollIntoView({behavior:'auto'})"
    webView.evaluateJavaScript(js) { _, _ in }
}
```

This must run **after** the TOC script assigns heading IDs (which happens via `WKUserScript` at document end, before `didFinish` fires).

### 3. Handle the new-tab path

When `openInNewTab` is true, the fragment is already in `AppDelegate.pendingURL`. The new tab's `onAppear` calls `model.load(from: url)` ([ContentView.swift:1371](QuickMDApp/ContentView.swift#L1371)), so step 1 will capture the fragment, and step 2 will scroll to it when `didFinish` fires.

### 4. Handle already-open tab with fragment

In `openFileLink()` ([ContentView.swift:340](QuickMDApp/ContentView.swift#L340)), the existing-tab check compares `standardizedFileURL` (which strips fragments). When the file is already open, we need to scroll to the fragment directly:

```swift
if let fragment = url.fragment {
    // Scroll to the anchor in the already-loaded page
    webView.evaluateJavaScript("document.getElementById('\(fragment)')?.scrollIntoView({behavior:'auto'})")
}
```

This requires getting a reference to the window's WebView. The simplest approach: set `pendingFragment` on the model and have the existing window's WebView pick it up (e.g., via a published property change that triggers JS evaluation).

## Files to modify

- [MarkdownDocumentModel.swift](QuickMDApp/MarkdownDocumentModel.swift) — add `pendingFragment` property, set it in `load(from:)`
- [ContentView.swift](QuickMDApp/ContentView.swift) — scroll to fragment in `didFinish`, handle already-open tab case

## Verification

1. Open a markdown file that links to another file with an anchor (e.g., `[link](other.md#some-heading)`)
2. Click the link — should open the file AND scroll to the heading
3. Test with `openLinksInNewTab` both on and off
4. Test clicking a link to a file that's already open in another tab — should switch to that tab and scroll
5. Test pure anchor links within the same page still work (regression check)
