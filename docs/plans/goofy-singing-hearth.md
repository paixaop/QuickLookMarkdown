# Plan: Integrate morphdom for Incremental DOM Updates

## Context

Currently, live editing replaces the entire `<article>` content on every change, which causes flicker and forces all post-processing scripts (highlight.js, mermaid, checkboxes, TOC, etc.) to re-run on the entire document. By using **morphdom** (~10KB), we can diff the DOM and only update changed nodes — eliminating flicker and making post-processing selective.

Note: All HTML is generated from the user's own markdown via the Swift Markdown library (trusted local content), not from external/untrusted sources.

## Steps

### 1. Add morphdom library
- Download `morphdom-umd.min.js` (~10KB) from unpkg
- Save to `Resources/morphdom-umd.min.js`
- Verify no `</script>` literal (safe for QL extension inlining)

### 2. Load morphdom in app target
- **MarkdownDocumentModel.swift** (~line 337): Add `static let morphdomJS` using `loadResource("morphdom-umd.min", ext: "js", label: "morphdom")`
- **ContentView.swift** (~line 517): Inject as `WKUserScript` before `contentUpdateScript`

### 3. Rewrite `__updateContent()` to use morphdom
- **MarkdownDocumentModel.swift** `contentUpdateScript`: Replace full DOM replacement with `morphdom(article, template, { childrenOnly: false, ... })`
- Use callbacks to track which nodes changed:
  - `onBeforeElUpdated`: Skip code blocks whose `dataset.rawText` matches (already highlighted, no change)
  - `onElUpdated` / `onNodeAdded`: Collect changed code blocks, mermaid blocks, headings
- Run post-processing **selectively**: highlight.js only on changed code blocks, TOC only if headings changed, mermaid only on changed diagrams

### 4. Track raw text on code blocks
- **MarkdownDocumentModel.swift** `highlightRenderScript`: Before `hljs.highlightElement(code)`, store `code.dataset.rawText = code.textContent`
- This lets morphdom skip unchanged code blocks (highlighted HTML differs from raw HTML, but raw text hasn't changed)

### 5. Handle mermaid SVG preservation
- In `__updateContent`, before calling `morphdom()`, transform mermaid `<pre><code>` blocks in the template into `<div class="mermaid" data-source="...">` to match existing DOM structure
- Store `data-source` on rendered mermaid divs (in `mermaidRenderScript`)
- morphdom then skips unchanged diagrams naturally

## Key Files
- `MarkdownDocumentModel.swift` — `contentUpdateScript`, `morphdomJS`, `highlightRenderScript`, `mermaidRenderScript`
- `ContentView.swift` — WKUserScript injection
- `Resources/morphdom-umd.min.js` — new file (~10KB)
- `PreviewViewController.swift` — **no changes** (QL extension is one-shot, no live editing)

## What This Does NOT Change
- The QL extension (no live editing there)
- Full page load on file open (still uses `loadHTMLString`)
- The 0.5s debounce on the Swift side

## Verification
1. Type in editor — preview updates without flicker, scroll stays put
2. Edit a code block — only that block re-highlights
3. Edit text outside a mermaid diagram — SVG preserved, no re-render
4. Add/remove headings — TOC rebuilds; edit body text — TOC untouched
5. Click checkboxes — still toggle correctly after edits
6. Large document (1000+ lines) — responsive typing
7. `make install` succeeds
