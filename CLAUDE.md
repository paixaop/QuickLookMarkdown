# QuickMD - Project Notes

## GitHub

- **Always use the `paixaop` GitHub account** for this repo (not `darksectorai`). Run `gh auth switch --user paixaop` before any `gh` commands if needed.
- Remote: `https://github.com/paixaop/QuickLookMarkdown.git`

## Build & Install

- Uses XcodeGen: `xcodegen generate` then `xcodebuild`
- App product name is `QuickMD` (bundle ID: `com.pedro.QuickMDApp`)
- No paid developer certificate — build with ad-hoc signing: `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`
- **Always run `make install` after building** to copy the app to /Applications and re-register the Quick Look extension. The app must be installed to test properly.

## Quick Look Extension — How to Override the System Markdown Previewer

macOS 13+ has a built-in markdown Quick Look previewer that takes priority over third-party extensions by default. Here's what was required to make our extension win:

### 1. Info.plist Structure (Critical)

The `QLSupportedContentTypes` must be nested inside `NSExtensionAttributes`, NOT directly under `NSExtension`. Also requires `QLIsDataBasedPreview: true`:

```yaml
NSExtension:
  NSExtensionPointIdentifier: com.apple.quicklook.preview
  NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).PreviewViewController
  NSExtensionAttributes:
    QLIsDataBasedPreview: true
    QLSupportedContentTypes:
      - net.daringfireball.markdown
      - public.markdown
      - org.commonmark.markdown
      - com.unknown.md
      - dyn.ah62d4rv4ge81e5pe
      - dyn.ah62d4rv4ge8043a
      - dyn.ah62d4rv4ge81c5pe
      - dyn.ah62d4rv4ge8043d2
      - dyn.ah62d4rv4ge8043dd
      - dyn.ah62d4rv4ge80c6dmqk
    QLSupportsSearchableItems: false
```

### 2. Dynamic UTIs

The `dyn.ah62d...` entries catch .md files that don't have a proper UTI assigned. These are borrowed from the QLMarkdown project (github.com/sbarex/QLMarkdown) which solved the same problem.

### 3. Data-Based Preview API

Use `QLPreviewReply` with `UTType.html` in `providePreview(for:)` instead of WKWebView-based rendering. The extension returns HTML data that macOS renders in its own WebView:

```swift
func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
    let data = Data(html.utf8)
    return QLPreviewReply(dataOfContentType: UTType.html, contentSize: CGSize(width: 900, height: 800)) { _ in data }
}
```

### 4. Registration Commands (Run After Every Install)

```bash
# Install to /Applications
cp -R DerivedData/.../QuickMD.app /Applications/QuickMD.app

# Register with LaunchServices (-trusted flag is critical for ad-hoc signed apps)
lsregister -f -R -trusted /Applications/QuickMD.app

# Enable the extension via pluginkit
pluginkit -e use -i com.pedro.QuickMDApp.QuickMDPreviewExtension

# Set as default handler for markdown files
swift -e 'import Foundation; import CoreServices; LSSetDefaultRoleHandlerForContentType("net.daringfireball.markdown" as CFString, LSRolesMask.all, "com.pedro.QuickMDApp" as CFString)'

# Reset Quick Look cache and restart Finder
qlmanage -r && qlmanage -r cache && killall Finder
```

### 5. Key Gotchas

- `lsregister -trusted` is required for ad-hoc signed apps, otherwise pluginkit won't register the extension
- WKWebView in sandboxed apps requires `com.apple.security.network.client` entitlement even for `loadHTMLString`
- The app (not just the extension) must declare `UTImportedTypeDeclarations` for `net.daringfireball.markdown` in its Info.plist
- The app must declare `LSHandlerRank: Owner` for markdown document types
- Mermaid JS can be inlined in HTML (no `</script>` in mermaid.min.js) for the data-based QL extension, but use `WKUserScript` injection for the app's WKWebView

## Syntax Highlighting & Code Rendering

### Libraries

- **highlight.js** v11.11.1 (~127KB) — syntax highlighting for 190+ languages
- **highlight-github.css / highlight-github-dark.css** — GitHub light/dark theme, switching via `@media (prefers-color-scheme: dark)`
- **js-yaml** v4.1.0 (~39KB) — full YAML parser for pretty-printing

All JS/CSS are bundled in `Resources/` alongside `mermaid.min.js`. None contain `</script>` so they're safe to inline in HTML.

### How It Works

1. **File type detection**: `htmlBody(for:)` checks the file extension — markdown files go through Down, everything else is HTML-escaped and wrapped in `<pre><code class="language-X">`
2. **JSON pretty-print**: `JSON.parse()` + `JSON.stringify(null, 2)` runs before highlighting
3. **YAML pretty-print**: `jsyaml.load()` + `jsyaml.dump()` runs before highlighting
4. **highlight.js**: `hljs.highlightElement()` runs on all `<pre><code>` blocks (skipping mermaid)
5. **Mermaid**: Runs last, replacing `language-mermaid` blocks with rendered SVG

### Integration Pattern (Same as Mermaid)

- **App target**: Libraries injected via `WKUserScript` at document end (ContentView.swift)
- **QL extension**: Libraries inlined in `<script>` tags in HTML output (PreviewViewController.swift)

### CSS Layering

The highlight.js theme CSS loads first, then our custom `<style>` block overrides `pre code.hljs` background/padding to `transparent`/`0` so our existing `pre` styling (background, border-radius, padding) takes precedence.

### Supported File Types

The app registers as default handler (`LSHandlerRank: Owner`) for markdown, JSON, and YAML. For source code files it registers as `Alternate` (won't steal default from Xcode/editors). The extension's `QLSupportedContentTypes` includes all the same types for Quick Look previews.

The `extensionToLanguage` dictionary in both `MarkdownDocumentModel.swift` and `PreviewViewController.swift` maps file extensions to highlight.js language names. Add new languages by adding entries there and corresponding UTIs to Info.plist + project.yml.

## Testing

### Rules — READ BEFORE WRITING TESTS

1. **Every feature MUST have a WKWebView E2E test.** Unit tests alone are not sufficient. If your code produces HTML or runs JS in the browser, test it in a real `WKWebView`. See `EditorRendererSyncE2ETests.swift` for the pattern.

2. **E2E test pattern:**
   - Create a `WKWebView` in the test
   - Load rendered HTML via `MarkdownDocumentModel` (use `loadHTMLString`)
   - Inject the same scripts as `EditorRendererSyncE2ETests.coreScripts` (theme, highlight, `headingDataScript`, `editorSyncScript`, `commentScript`, `contentUpdateScript`, etc.) — sidebar UI is native SwiftUI, not JS
   - Wait for load (use `expectation` with ~1.5s timeout)
   - Use `evaluateJavaScript` to interact with the DOM (select text, click elements, read attributes)
   - Verify the JS functions return correct values
   - Verify the Swift algorithm produces the correct result from the JS output

3. **Test the full pipeline, not just functions.** A test that calls `SourceMappedHTMLFormatter.format()` and checks the output is a unit test. An E2E test loads that HTML into a WKWebView, selects text with `window.find()`, calls `__getSelectionSourceInfo()`, and verifies the source line mapping is correct end-to-end.

4. **Use `window.find(text, caseSensitive, backwards, wrap)` to select text in the WebView.** This is how you simulate clicking/selecting words. Use the `occurrence` parameter pattern to select the nth occurrence.

5. **Test duplicate/ambiguous cases.** If a word appears multiple times, test that each occurrence maps to the correct source position. This is the most important class of E2E tests.

6. **Test edge cases in the browser, not just in Swift.** Markdown formatting (`**bold**`, `[link](url)`, `# heading`), comment annotations, frontmatter, nested structures — all affect how the DOM looks. The browser may handle these differently than you expect.

7. **Expose testable static functions.** When testing algorithms that live inside UI code (like `jumpEditorToWord` on the Coordinator), extract the core logic into a `static func` so tests can call it without needing a full UI context. Example: `WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine:offsetInBlock:endOffsetInBlock:frontmatterLineCount:source:)`.

### Test Structure

- `QuickMDTests/MarkdownDocumentModelTests.swift` — Unit tests for the model (140+ tests)
- `QuickMDTests/EditorRendererSyncTests.swift` — Unit tests for sync algorithm edge cases (71 tests)
- `QuickMDTests/EditorRendererSyncE2ETests.swift` — **WKWebView E2E tests** for full browser pipeline (25 tests)
- `QuickMDUITests/QuickMDUITests.swift` — XCUITest app-level tests (menus, shortcuts, file opening)
- `QuickMDUITests/Fixtures/` — Test markdown files (basic.md, linked.md, comments.md, headings.md, formatting.md, frontmatter.md, empty.md, large.md)

### Running Tests

```bash
# Unit + E2E tests (both run in-process, E2E uses real WKWebView)
xcodebuild test -scheme QuickMDApp -only-testing QuickMDTests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES SWIFT_VERSION=5.0 \
  SWIFT_ENABLE_EXPLICIT_MODULES=NO ENABLE_TESTABILITY=YES

# UI tests (launches app, requires accessibility permissions)
xcodebuild test -scheme QuickMDApp -only-testing QuickMDUITests \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" \
  CODE_SIGN_ALLOW_ENTITLEMENTS_MODIFICATION=YES SWIFT_VERSION=5.0
```

### When to Write Tests

- **New JS feature** → Write an E2E test that loads HTML into WKWebView and exercises the JS
- **New Swift algorithm** → Extract as static func, write unit test + E2E test
- **Bug fix** → Write a test that reproduces the bug first, then fix it
- **Changed HTML structure** → Update existing tests that check for specific HTML tags (e.g., `<h1>` → `<h1 data-source-line=` after adding source mapping)

## Source Line Mapping — CRITICAL RULE

**Always use `data-source-line` attributes to navigate, position, and calculate document offsets. NEVER use text searches to find document positions.** Files can have the same text strings repeated many times, and text-based searches will end up at the wrong position.

### How it works

Every block-level HTML element rendered from markdown gets a `data-source-line="N"` attribute (1-based line number in the source file). This is the single source of truth for mapping between the rendered preview and the source text.

### JS → Swift mapping (renderer to source)

1. `__getSelectionSourceInfo()` returns `{ sourceLine, offsetInBlock, endOffsetInBlock, text }` where:
   - `sourceLine` — the `data-source-line` value of the nearest ancestor element
   - `offsetInBlock` — character offset of the selection start within the rendered text of that block
   - `endOffsetInBlock` — character offset of the selection end within the rendered text
2. `__findSourceLineAncestor(node)` walks up the DOM to find the nearest element with `data-source-line`
3. `__getOffsetInBlock(blockEl, range)` computes the character offset of a Range within a block element

### Swift: mapping rendered offsets → source positions

`WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine:offsetInBlock:endOffsetInBlock:frontmatterLineCount:source:)` maps rendered text offsets back to source character positions by walking the source line character-by-character, skipping:
- Comment markers (`<!-- COMMENT: ... -->`, `<!-- /COMMENT -->`)
- Inline markdown markers (`**`, `*`, `__`, `_`, `~~`, backticks)

This produces the exact `NSRange` in the source text — no string searching involved.

### When to use what

| Task | Method | Why |
|------|--------|-----|
| Place a comment | `sourceRangeFromRenderedOffsets` | Exact position via line + offsets |
| Double-click jump to editor | `sourceLine` + `offsetInBlock` | Direct line lookup |
| Scroll sync | `__scrollToLine(line, fractionPast)` | Line-based, no text search |
| TOC navigation | `heading.sourceLine` | Each heading stores its source line |
| `findWordRange` (legacy fallback) | Only as last resort | May match wrong occurrence |

### Rules for new code

1. Any new feature that maps between renderer and source MUST use `data-source-line` + character offsets
2. The `findWordRange` text-search function exists only as a legacy fallback — do not use it as the primary method
3. When adding new JS→Swift interactions, always pass `sourceLine` and offset data from `__getSelectionSourceInfo()`
4. Test with documents that have duplicate text — the same word/phrase appearing multiple times on different lines

## Architecture

- **App target**: SwiftUI + WKWebView + swift-markdown (markdown→HTML) + highlight.js/js-yaml/mermaid via WKUserScript
- **Extension target**: QLPreviewingController + QLPreviewReply (data-based HTML) + swift-markdown + highlight.js/js-yaml/mermaid inlined in HTML
- **Shared**: `Resources/` folder bundled in both targets:
  - `mermaid.min.js` (~2.9MB) — Mermaid diagram rendering
  - `highlight.min.js` (~127KB) — Syntax highlighting
  - `highlight-github.css` / `highlight-github-dark.css` (~1.3KB each) — GitHub theme
  - `js-yaml.min.js` (~39KB) — YAML parsing
  - `Resources/scripts/utils.js` — shared JS helpers loaded first (`__postWebkitMessage`, `__findSourceLineAncestor`, `__getOffsetInBlock`, `__getMermaidTheme`)
