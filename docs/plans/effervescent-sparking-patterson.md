# Fix: Comment placement bugs + save-on-close dialog

## Context

When adding a comment via right-click context menu in the WebView renderer, two bugs occur:

1. **File not saved**: The comment silently fails to be added — no error, no change to the file
2. **First letter missing**: When the comment IS added, the first letter of the selected word is excluded from the annotated range

**Root cause**: Both bugs stem from the same timing issue. In `addCommentAction` ([ContentView.swift:151-165](QuickMDApp/ContentView.swift#L151-L165)), `__getSelectionSourceInfo()` is called via `evaluateJavaScript` AFTER the user clicks the context menu item. By that point, the WebView selection has been collapsed or shifted by the menu interaction.

- **Bug 1**: Selection is fully collapsed → `__getSelectionSourceInfo()` returns `null` → `sourceLine = -1` → primary path skipped → editor fallback finds no selection → nothing happens
- **Bug 2**: Selection start shifted by 1 character → `offsetInBlock` is off by 1 → first letter excluded from the computed `NSRange`

## Fix

### 1. Capture selection info eagerly in `willOpenMenu` (context menu path)

**File**: [ContentView.swift](QuickMDApp/ContentView.swift)

In `willOpenMenu` (lines 92-149), replace the two separate JS evaluations with a single atomic call that captures both text and source info at once:

```javascript
(function() {
    var text = window.__getSelectionText ? __getSelectionText() : '';
    var info = window.__getSelectionSourceInfo ? __getSelectionSourceInfo() : null;
    return { text: text, info: info };
})()
```

This eliminates the race window entirely. Store the result and pass a dictionary through `representedObject`:

```swift
addItem.representedObject = [
    "text": selectedText,
    "sourceLine": sourceInfo?["sourceLine"] ?? -1,
    "offsetInBlock": sourceInfo?["offsetInBlock"] ?? -1,
    "endOffsetInBlock": sourceInfo?["endOffsetInBlock"] ?? -1
] as [String: Any]
```

Remove one `DispatchGroup` entry (net simpler code).

### 2. Update `addCommentAction` to use pre-captured info

**File**: [ContentView.swift](QuickMDApp/ContentView.swift) lines 151-165

Read source info from the `representedObject` dictionary instead of re-querying JS:

```swift
@objc private func addCommentAction(_ sender: NSMenuItem) {
    guard let info = sender.representedObject as? [String: Any],
          let text = info["text"] as? String else { return }
    let sourceLine = info["sourceLine"] as? Int ?? -1
    let offsetInBlock = info["offsetInBlock"] as? Int ?? -1
    let endOffsetInBlock = info["endOffsetInBlock"] as? Int ?? -1
    commentCoordinator?.showCommentEditor(
        index: -1, comment: "", annotatedText: text,
        isNew: true, sourceLine: sourceLine,
        offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock
    )
}
```

### 3. Apply same atomic JS pattern to Cmd+K path (secondary)

**File**: [ContentView.swift](QuickMDApp/ContentView.swift) lines 1622-1642

The notification-based path (`.addCommentAction` from Cmd+K) has the same structural issue — two sequential `evaluateJavaScript` calls where the selection could theoretically change between them. Replace with a single atomic call for consistency and robustness.

### 4. Add "Save before closing?" dialog on window close

**File**: [QuickMDApp/ContentView.swift](QuickMDApp/ContentView.swift)

Currently the app checks `isDocumentEdited` only on app quit (`applicationShouldTerminate` in [QuickMDApp.swift:35-68](QuickMDApp/QuickMDApp.swift#L35-L68)). Closing an individual window with unsaved changes silently discards them.

**Approach**: Create a small `WindowCloseDelegate` class conforming to `NSWindowDelegate`, implementing `windowShouldClose(_:)`. If `window.isDocumentEdited` is true, show an alert with Save / Don't Save / Cancel. Install it on the hosting window from the `onAppear` block (line ~1490).

```swift
class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var model: MarkdownDocumentModel?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.isDocumentEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this document?"
        alert.informativeText = "Your changes will be lost if you don't save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don't Save")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            // Save then close
            if let model = model, let url = model.currentURL {
                try? model.rawContent.write(to: url, atomically: true, encoding: .utf8)
                model.markClean()
                sender.isDocumentEdited = false
            }
            return true
        case .alertSecondButtonReturn:
            return true  // close without saving
        default:
            return false // cancel
        }
    }
}
```

In the `onAppear` block, after a short delay (to let the window materialize), find the hosting `NSWindow` and assign the delegate:

```swift
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    if let window = WebViewStore.shared.webView?.window {
        let delegate = WindowCloseDelegate()
        delegate.model = model
        // Store strong ref so it isn't deallocated
        objc_setAssociatedObject(window, "closeDelegate", delegate, .OBJC_ASSOCIATION_RETAIN)
        window.delegate = delegate
    }
}
```

**Note**: SwiftUI `WindowGroup` may set its own window delegate. If that conflicts, we'll use `NotificationCenter` observing `NSWindow.willCloseNotification` with the same save logic as an alternative.

## Files to modify

- [QuickMDApp/ContentView.swift](QuickMDApp/ContentView.swift) — comment bug fixes (steps 1-3) + window close delegate (step 4)

## Verification

1. `make install` to build and install
2. Open a markdown file with multiple paragraphs
3. **Test comment context menu**: Select a word in the renderer → right-click → "Add Comment..." → enter comment text → Save → verify the file is saved with `<!-- COMMENT: ... -->word<!-- /COMMENT -->` wrapping the exact selected word (including first letter)
4. **Test Cmd+K**: Select text in renderer → Cmd+K → enter comment → Save → verify same correct behavior
5. **Test comment edge cases**: Select text at start of line, text inside bold/italic, text in headings, text in list items
6. **Test existing comments**: Click existing comment → Edit/Delete → verify still works
7. **Test save-on-close**: Edit a file → try to close the window → verify "Save/Don't Save/Cancel" dialog appears. Test all three buttons.
8. **Test clean close**: Open a file without editing → close window → verify no dialog appears
9. Run unit + E2E tests: `make test` or the xcodebuild test command from CLAUDE.md
