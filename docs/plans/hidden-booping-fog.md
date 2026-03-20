# Plan: Markdown Comment Annotations

## Context
The user reviews markdown files produced by coding agents and needs to annotate them with inline comments, then feed the files back. Comments must be machine-parseable and visually highlighted in the preview.

## Comment Format
```
<!-- COMMENT: use OAuth instead -->implement the login flow<!-- /COMMENT -->
```
- Agents parse with: `<!-- COMMENT: (.*?) -->(.*?)<!-- /COMMENT -->`
- Wrapping clearly associates comment text with the annotated content
- Works for words, sentences, or multi-line selections

---

## Implementation

### 1. Comment Pre-processing (MarkdownDocumentModel.swift)

Before passing markdown to `HTMLFormatter.format()`, replace comment markers with styled spans:

```swift
static func preprocessComments(_ markdown: String) -> String
```

Transforms `<!-- COMMENT: foo -->text<!-- /COMMENT -->` into:
```html
<mark class="qmd-comment" data-comment="foo">text</mark>
```

Apply in both:
- `htmlBody(for:)` (line 144) — full page render
- `markdownBodyHTML(from:)` (line 1948) — incremental updates

Also add source manipulation helpers:
- `addComment(around:comment:in:) -> String` — wraps selected range with comment markers
- `removeComment(at:in:) -> String` — strips comment markers, keeps the text
- `updateComment(at:newComment:in:) -> String` — changes comment text
- `parseComments(in:) -> [(range, comment, annotatedText)]` — finds all comments

### 2. CSS for Comment Highlighting (MarkdownDocumentModel.swift — wrapHTML)

Add to the `<style>` block:
```css
.qmd-comment {
    background: rgba(255, 213, 79, 0.3);
    border-bottom: 2px solid rgba(255, 179, 0, 0.6);
    cursor: pointer;
}
.qmd-comment:hover { background: rgba(255, 213, 79, 0.5); }

@media (prefers-color-scheme: dark) {
    .qmd-comment { background: rgba(255, 179, 0, 0.2); border-bottom-color: rgba(255, 179, 0, 0.4); }
    .qmd-comment:hover { background: rgba(255, 179, 0, 0.35); }
}
```

### 3. Comment JS Script (MarkdownDocumentModel.swift)

New `static let commentScript: String` — injected via WKUserScript:

- **Hover**: show tooltip with comment text on `.qmd-comment` mouseenter/mouseleave
- **Click**: send `commentAction` message to Swift with `{type: 'click', index, comment, text}`
- **Context menu on selection**: intercept right-click when text is selected, add "Add Comment" option, send `{type: 'add', text: selectedText}` to Swift
- **`__setupComments()`**: re-attach listeners after morphdom update (called from `contentUpdateScript`)
- **`__nextComment()` / `__prevComment()`**: scroll to next/prev comment in preview

### 4. Message Handler (ContentView.swift)

Register new WKUserScript + message handler `commentAction` in `makeNSView`:

```swift
config.userContentController.add(context.coordinator, name: "commentAction")
```

Handle in Coordinator's `userContentController(_:didReceive:)`:
- `type: "click"` → show CommentEditorView in edit mode (positioned near click)
- `type: "add"` → show CommentEditorView in create mode with selected text

On save: find the selected text in `rawContent`, wrap with comment markers, update source via `model.setRawContent()`, which triggers re-render.

### 5. CommentEditorView (ContentView.swift)

SwiftUI view presented in an NSPanel (positioned near mouse):

```
┌─ Add Comment ──────────────┐
│ "selected text preview..."  │
│ ┌────────────────────────┐ │
│ │ Comment text input     │ │
│ │                        │ │
│ └────────────────────────┘ │
│ [Delete]     [Cancel][Save]│
└────────────────────────────┘
```

- Create mode: shows selected text (read-only), empty comment field
- Edit mode: shows annotated text + existing comment, Delete button visible
- Save: wraps/updates comment markers in source
- Delete: removes markers, keeps annotated text

### 6. Editor Context Menu (MarkdownEditorView.swift)

After finding the NSTextView via `findEditorTextViewInView()`, customize its menu:
- If text is selected: add "Add Comment..." menu item → shows CommentEditorView
- If cursor is inside existing comment markers: add "Edit Comment..." and "Remove Comment" items

Use NSNotification to communicate between menu action and ContentView (same pattern as other features).

### 7. Menu & Keyboard Shortcuts (QuickMDApp.swift)

Add to Tools menu:
- **Add Comment...** (⌘⇧K) — triggers comment creation on current editor selection
- **Remove Comment** — removes comment at cursor position
- **Next Comment** (⌘⌥J) — scrolls preview to next comment
- **Previous Comment** (⌘⌥K) — scrolls preview to previous comment

### 8. Morphdom Integration (MarkdownDocumentModel.swift — contentUpdateScript)

In `__updateContent()`, after morphdom completes, call `__setupComments()` to re-attach event listeners on new/changed comment spans. Same pattern as `__setupCheckboxes()`.

### 9. Quick Look Extension (PreviewViewController.swift)

Mirror the `preprocessComments()` call and CSS in the extension's HTML output. No interactivity needed — just visual highlighting of comments.

---

## Files to Modify
1. `QuickMDApp/MarkdownDocumentModel.swift` — preprocessComments, CSS, commentScript, source manipulation helpers, morphdom hook
2. `QuickMDApp/ContentView.swift` — WKUserScript registration, commentAction handler, CommentEditorView + NSPanel
3. `QuickMDApp/MarkdownEditorView.swift` — editor context menu items for Add/Edit/Remove comment
4. `QuickMDApp/QuickMDApp.swift` — Tools menu items + keyboard shortcuts
5. `QuickMDPreviewExtension/PreviewViewController.swift` — preprocessComments + CSS (read-only)

## Verification
1. Open a markdown file, select text in editor, right-click → "Add Comment" → type comment → Save
2. Verify the source contains `<!-- COMMENT: text -->selected<!-- /COMMENT -->`
3. Verify preview highlights the annotated text with yellow background
4. Hover highlighted text → tooltip shows comment
5. Click highlighted text → edit popup appears, can update or delete
6. Select text in preview, right-click → "Add Comment" works
7. Save file, reopen → comments persist and display correctly
8. ⌘⌥J/K navigates between comments
9. Quick Look preview shows highlighted comments (no interaction)
