# QuickMD Feature Batch Design

## Phase 1: Quick Wins

### 1. Auto-show editor on double-click
- In the `dblclick` handler in ContentView.swift, if editor is hidden, set `showEditor = true`
- Small delay before calling `jumpEditorToWord` to let the text view appear

### 2. Empty tabs on launch cleanup
- Refine `applicationDidFinishLaunching` to detect and close blank/empty windows
- Only keep one window; close empty untitled windows when opening a file

### 3. Spell check toggle
- `@AppStorage("spellCheck")` boolean (default: true)
- Toggle in Tools menu with checkmark
- Apply via `textView.isContinuousSpellCheckingEnabled`

### 4. Auto-pair markdown syntax
- Intercept key events on editor NSTextView
- Pairs: `**`/`**`, `*`/`*`, `` ` ``/`` ` ``, `~~`/`~~`, `(`/`)`, `[`/`]`, `{`/`}`
- Code fence: ` ``` ` + Enter inserts closing ` ``` `
- Wrap selection when selection exists
- Skip closing char if already present
- Toggleable via `@AppStorage("autoPair")` (default: true) in Tools menu

### 5. Word count status bar
- `EditorStatusBar` view below CodeEditor in MarkdownEditorView
- Shows: `Ln X, Col Y | Words: N | Chars: N | ~N min read`
- Line/column from CodeEditor.Position binding
- Word count from `text.split(separator:)`, debounced
- Reading time: words / 200
- Only visible when editor is shown

## Phase 2: Medium Features

### 6. Custom CSS Themes menu
- Bundle 6 built-in themes as CSS strings: GitHub (default), Dracula, Solarized Light, Solarized Dark, Nord, Sepia
- Override `.markdown-body` colors, `pre`/`code` backgrounds, link colors, heading colors, highlight.js theme
- Theme menu: list built-in with checkmark, divider, "Custom CSS..." to pick a `.css` file
- Custom CSS path in `@AppStorage("customCSSPath")`, appended after built-in theme CSS
- Extend `@AppStorage("theme")` to include theme names
- Both app and extension get theme support; extension uses stored preference

### 7. Export to HTML
- Menu item "Export as HTML..." (Cmd+Shift+H) next to PDF export
- Export full self-contained HTML (CSS + JS inlined) so diagrams and highlighting work in browser
- Write to user-chosen file via NSSavePanel

### 8. Search across preview and editor
- `SearchBar` view at top of window (Cmd+F), spanning both panes
- Text field + match count + prev/next + close (Esc)
- Editor: highlight matches with temporary attributes, scroll to current match
- Preview: JS function wraps matches in `<mark>` tags
- Navigate in editor (primary), preview highlights are visual feedback
- Highlights update in both panes simultaneously

## Phase 3: Larger Features

### 9. Live preview - preserve scroll position on auto-reload
- Before re-rendering on external file change, capture scroll fraction from preview via JS
- After new HTML loads, restore scroll fraction
- Similar to existing edit-reload flow with `isEditReload`
- Keep Auto-Reload toggle in Tools menu

### 10. Image paste/drag-drop
- Intercept Cmd+V on editor NSTextView; check NSPasteboard for image types
- Intercept drag-drop of image files onto editor
- On image: generate `image-YYYYMMDD-HHmmss.png`, create `images/` subdir next to .md file, write PNG, insert `![](images/<filename>)` at cursor
- Uses existing sandbox directory bookmarks for write access
- If untitled document, show save panel first to establish location
