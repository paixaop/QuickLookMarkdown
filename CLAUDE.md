# QuickMD - Project Notes

## Build & Install

- Uses XcodeGen: `xcodegen generate` then `xcodebuild`
- App product name is `QuickMD` (bundle ID: `com.pedro.QuickMDApp`)
- No paid developer certificate — build with ad-hoc signing: `CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM=""`

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

## Architecture

- **App target**: SwiftUI + WKWebView + Down (markdown→HTML) + highlight.js/js-yaml/mermaid via WKUserScript
- **Extension target**: QLPreviewingController + QLPreviewReply (data-based HTML) + Down + highlight.js/js-yaml/mermaid inlined in HTML
- **Shared**: `Resources/` folder bundled in both targets:
  - `mermaid.min.js` (~2.9MB) — Mermaid diagram rendering
  - `highlight.min.js` (~127KB) — Syntax highlighting
  - `highlight-github.css` / `highlight-github-dark.css` (~1.3KB each) — GitHub theme
  - `js-yaml.min.js` (~39KB) — YAML parsing
