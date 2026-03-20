# Plan: Extract Inline JavaScript into Separate Files

## Context

`MarkdownDocumentModel.swift` (3,510 lines) contains **30 inline JavaScript strings** totaling ~1,600 lines of JS embedded as Swift multiline string literals. `PreviewViewController.swift` (1,255 lines) duplicates **~12 of these scripts** as inline blocks in its `wrapHTML()` method, plus has 4 named duplicate `static let` scripts. This makes both files bloated and hard to maintain. The project already loads 9 external JS/CSS files from `Resources/` via `Bundle.main`, so the pattern is established.

## Approach

Extract all 30 inline JS scripts from `MarkdownDocumentModel.swift` into individual `.js` files in `Resources/scripts/`. Replace the inline `static let` string literals with `loadResource()` calls. Update `PreviewViewController.swift` to load from the same shared files, eliminating all duplication.

## Files to Create

Create `Resources/scripts/` directory with 30 `.js` files:

| File | Swift Property | ~Lines |
|------|---------------|--------|
| `theme.js` | `themeScript` | 10 |
| `mermaid-render.js` | `mermaidRenderScript` | 25 |
| `zoom-overlay.js` | `zoomOverlayScript` | 131 |
| `highlight-render.js` | `highlightRenderScript` | 26 |
| `copy-button.js` | `copyButtonScript` | 41 |
| `katex-render.js` | `katexRenderScript` | 17 |
| `reading-stats.js` | `readingStatsScript` | 14 |
| `font-size.js` | (new - from extension's `fontSizeBlock`) | 15 |
| `line-numbers.js` | `lineNumbersScript` | 27 |
| `jump-to-line.js` | `jumpToLineScript` | 36 |
| `find.js` | `findScript` | 103 |
| `graphviz-render.js` | `graphvizRenderScript` | 26 |
| `speak.js` | `speakScript` | 46 |
| `heading-data.js` | `headingDataScript` | 61 |
| `toc.js` | `tocScript` | 174 |
| `word-wrap.js` | `wordWrapScript` | 13 |
| `anchor-links.js` | `anchorLinksScript` | 19 |
| `emoji.js` | `emojiScript` | 126 |
| `footnotes.js` | `footnotesScript` | 86 |
| `frontmatter.js` | `frontmatterScript` | 52 |
| `presentation.js` | `presentationScript` | 66 |
| `link-click.js` | `linkClickScript` | 33 |
| `link-hover.js` | `linkHoverScript` | 16 |
| `checkbox-toggle.js` | `checkboxToggleScript` | 18 |
| `editor-sync.js` | `editorSyncScript` | 117 |
| `comment.js` | `commentScript` | 141 |
| `comments-sidebar.js` | `commentsSidebarScript` | 115 |
| `files-browser.js` | `filesBrowserScript` | 95 |
| `sidebar-arrange.js` | `sidebarArrangeScript` | 74 |
| `content-update.js` | `contentUpdateScript` | 225 |

## Files to Modify

### 1. `QuickMDApp/MarkdownDocumentModel.swift`

**Update `loadResource` to support subdirectories:**
```swift
private static func loadResource(_ name: String, ext: String, subdirectory: String? = nil, label: String) -> String {
    let subdir = subdirectory.map { "Resources/\($0)" } ?? "Resources"
    ...
}
```

**Add script loader helper:**
```swift
private static func loadScript(_ name: String) -> String {
    loadResource(name, ext: "js", subdirectory: "scripts", label: name)
}
```

**Replace each `static let xxxScript = """..."""` with:**
```swift
static let themeScript: String = loadScript("theme")
static let mermaidRenderScript: String = loadScript("mermaid-render")
// ... etc for all 29 scripts
```

Keep `fontSizeScript` pointing to the new `font-size.js` (previously empty in model, now has the extension's implementation).

### 2. `QuickMDPreviewExtension/PreviewViewController.swift`

**Remove the 4 duplicate `static let` scripts** (lines 165-367): `emojiScript`, `footnotesScript`, `frontmatterScript`, `anchorLinksScript`.

**Add shared script loader + static properties:**
```swift
private static func loadScript(_ name: String) -> String {
    guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Resources/scripts"),
          let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
    return content
}

private static let emojiScript = loadScript("emoji")
private static let footnotesScript = loadScript("footnotes")
private static let frontmatterScript = loadScript("frontmatter")
private static let anchorLinksScript = loadScript("anchor-links")
private static let zoomOverlayScript = loadScript("zoom-overlay")
private static let readingStatsScript = loadScript("reading-stats")
private static let fontSizeScript = loadScript("font-size")
private static let jumpToLineScript = loadScript("jump-to-line")
private static let findScript = loadScript("find")
private static let lineNumbersScript = loadScript("line-numbers")
private static let copyButtonScript = loadScript("copy-button")
```

**Replace inline `wrapHTML` blocks** — change each inline `let xxxBlock = """<script>...</script>"""` to use the loaded static property:
```swift
let zoomOverlayBlock = "<script>\(Self.zoomOverlayScript)</script>"
let readingStatsBlock = "<script>\(Self.readingStatsScript)</script>"
// ... etc
```

### 3. `QuickMDApp/ContentView.swift` — No changes needed
Scripts are referenced as `MarkdownDocumentModel.themeScript` etc. The API is unchanged.

### 4. `project.yml` — No changes needed
`Resources/` is `type: folder`, so subdirectories are automatically preserved in the bundle.

## String Escaping Notes

When extracting JS from Swift multiline string literals to `.js` files:
- Swift `\\u00D7` → JS `\u00D7` (remove one backslash)
- Swift `\\uD83D` → JS `\uD83D` (remove one backslash)
- Swift `\\n` (literal) → JS `\n`
- Swift `\\(` → JS `\(` (but verify none exist — these are static strings with no interpolation)
- No `\\/` escaping needed in multiline strings (Swift doesn't require it)

## Execution Order

1. Create `Resources/scripts/` directory
2. Extract all 30 JS files (careful with escaping)
3. Update `MarkdownDocumentModel.swift` — replace inline strings with `loadScript()` calls
4. Update `PreviewViewController.swift` — remove duplicates, add `loadScript()`, simplify `wrapHTML` blocks
5. Run `xcodegen generate`
6. Build and run tests

## Verification

1. `xcodegen generate && make install` — build succeeds
2. `xcodebuild test -scheme QuickMDApp -only-testing QuickMDTests` — all tests pass
3. Open a markdown file in the app — verify rendering (mermaid, code highlighting, emoji, footnotes, TOC, etc.)
4. Press Space on a `.md` file in Finder — verify Quick Look extension works
5. Test interactive features: search (Cmd+F), line numbers (Cmd+L), zoom overlay on images/mermaid, checkbox toggle

## Expected Impact

- **MarkdownDocumentModel.swift**: ~3,510 → ~1,900 lines (remove ~1,600 lines of inline JS)
- **PreviewViewController.swift**: ~1,255 → ~850 lines (remove ~400 lines of duplicate JS)
- **Net**: ~2,000 fewer lines of Swift, 30 well-organized `.js` files
- Both targets share the same JS files — no more duplication drift
