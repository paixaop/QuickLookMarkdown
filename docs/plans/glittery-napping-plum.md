# Production Readiness — App Store Polish

## Context

QuickMD has strong fundamentals (comprehensive rendering, dark mode, file associations, keyboard shortcuts, help system) but needs polish to meet App Store expectations for a developer-oriented markdown viewer/editor. Target audience: developers and AI power users who generate lots of markdown (agent skills, specs, documentation).

## Priority Tiers

### P0 — Blocks App Store Submission

#### 1. Accessibility Labels
**Status**: Zero accessibility labels in the entire codebase. VoiceOver users cannot interact with the app.

**Work**:
- Add `.accessibilityLabel()` to all toolbar buttons in `MarkdownFormattingToolbar` (~20 buttons)
- Add labels to back/forward navigation buttons, sidebar icons, search bar, status bar
- Add `.accessibilityHint()` for non-obvious controls
- Add `.accessibilityValue()` for toggle states (line numbers, word wrap, spell check)
- WebView: add `aria-label` attributes to sidebar icons, comment items, TOC items in the HTML/CSS
- Test with VoiceOver (Cmd+F5)

**Files**: ContentView.swift, MarkdownEditorView.swift, QuickMDApp.swift, MarkdownDocumentModel.swift (HTML/CSS)

#### 2. Unsaved Changes Detection
**Status**: No dirty-bit tracking. Users can lose work by quitting without saving.

**Work**:
- Add `@Published var isDirty = false` to `MarkdownDocumentModel`
- Set `isDirty = true` when `rawContent` changes from editor typing (`.onChange` of rawContent)
- Set `isDirty = false` after file save
- Show dot indicator in window title or tab when dirty (use `window.isDocumentEdited = true`)
- Add `applicationShouldTerminate` check — if any model has `isDirty`, show "Save/Don't Save/Cancel" alert
- Add `windowShouldClose` delegate — same alert for individual tabs
- Auto-save option in Settings (write to disk on every edit, with debounce)

**Files**: MarkdownDocumentModel.swift, QuickMDApp.swift (AppDelegate), ContentView.swift

#### 3. About Window
**Status**: No About window, no version display, no copyright.

**Work**:
- Add `NSHumanReadableCopyright` to Info.plist
- The standard About panel (`NSApp.orderFrontStandardAboutPanel`) reads from Info.plist automatically — just needs to be triggered
- Add "About QuickMD" to the app menu (it may already exist via SwiftUI defaults; verify)
- Ensure `Credits.rtf` or `Credits.html` file exists in the bundle for the About panel

**Files**: Info.plist, QuickMDApp.swift

### P1 — Expected by Users

#### 4. Empty State / Welcome Screen
**Status**: App opens to a blank editor with no guidance.

**Work**:
- When `model.html == nil` (no file loaded), show a welcome view instead of blank space
- Welcome view: app icon, "Open a file to get started" with Cmd+O hint, drag-and-drop zone, recent files list (from `NSDocumentController`), link to Help
- Use `.onDrop` on the welcome view as well
- Show Quick Look extension setup instructions for first-time users

**Files**: ContentView.swift (new `WelcomeView` struct)

#### 5. File Size Guard
**Status**: No size check. Loading a 100MB file will hang the app.

**Work**:
- Before loading, check `FileManager.default.attributesOfItem(atPath:)[.size]`
- Warn if > 5MB ("This file is large and may be slow to render")
- Refuse if > 50MB ("File too large to open")
- Show file size in the warning alert
- Add async loading with progress indicator for files > 1MB

**Files**: MarkdownDocumentModel.swift (`load(from:)`, `readFileContent(from:)`)

#### 6. Deleted/Moved File Handling
**Status**: If a file is deleted while open, the file watcher crashes or silently fails.

**Work**:
- In the file watcher callback, check if file still exists before reloading
- If file was deleted: show a "File was deleted" banner in the editor, disable auto-save, keep content in memory
- If file was moved/renamed: detect via `FileManager.default.fileExists` failure, offer "Save As"

**Files**: MarkdownDocumentModel.swift (file watcher section)

#### 7. Print Support
**Status**: No File > Print, no Cmd+P.

**Work**:
- Add "Print…" (Cmd+P) to File menu
- Implementation: use `WKWebView.printOperation()` which prints the rendered preview
- The print CSS already exists (`@media print { ... }`) and hides sidebar, TOC, buttons

**Files**: QuickMDApp.swift (menu), ContentView.swift (webView print action)

#### 8. Settings Completeness
**Status**: Spell check and auto-pair toggles exist in menus but not in Settings.

**Work**:
- Add to SettingsView: Spell Check toggle, Auto-Pair Brackets toggle, Auto-Save toggle
- Show current editor font name + size in Settings (read-only display)
- Group settings: General, Editor, Appearance, Advanced

**Files**: QuickMDApp.swift (SettingsView)

### P2 — Professional Polish

#### 9. Localization Preparation
**Status**: All text hardcoded in English. Full localization is a large effort.

**Work** (minimal viable):
- Wrap all user-visible strings in `NSLocalizedString()` or `String(localized:)`
- Generate `Localizable.strings` for English (base)
- Don't translate yet — just make it localizable for future contributors
- This is hundreds of strings across all files; can be done incrementally

**Files**: All Swift files with user-facing text

#### 10. Keyboard Shortcut Audit
**Status**: Some potential conflicts (Cmd+[ and Cmd+] for back/forward may interfere with bracket insertion in editor).

**Work**:
- Audit all shortcuts against macOS system defaults
- Ensure Cmd+[ and Cmd+] don't fire when editor is focused and user types brackets
- Consider using Cmd+Option+Left/Right for navigation instead (matches Xcode)
- Document all shortcuts in a single place

**Files**: QuickMDApp.swift

#### 11. Version Bump & Build Metadata
**Status**: Version 1.0, build 1.

**Work**:
- Set proper version numbering (e.g., 1.0.0)
- Add build number auto-increment (or use git commit count)
- Fix deployment target inconsistency (project.yml says 14.0, Info.plist says 13.0 — pick one)

**Files**: project.yml, Info.plist

#### 12. App Icon Polish
**Status**: AppIcon asset catalog exists but quality unknown.

**Work**:
- Verify icon exists at all required sizes (16, 32, 128, 256, 512, 1024)
- Ensure icon follows macOS design guidelines (rounded rectangle, no transparency issues)
- Add `CFBundleIconName: AppIcon` to Info.plist if missing

**Files**: Assets.xcassets, Info.plist

## Implementation Order

1. About Window (P0, smallest — 30 min)
2. Unsaved Changes Detection (P0, medium — 2 hours)
3. Accessibility Labels (P0, large — 3 hours)
4. Empty State / Welcome Screen (P1 — 1 hour)
5. Print Support (P1 — 30 min)
6. File Size Guard (P1 — 30 min)
7. Deleted File Handling (P1 — 1 hour)
8. Settings Completeness (P1 — 1 hour)
9. Version/Build Metadata (P2 — 15 min)
10. Keyboard Shortcut Audit (P2 — 1 hour)
11. Localization Prep (P2 — ongoing)
12. App Icon (P2 — verify only)

## Verification

1. `make install` after each change
2. Test VoiceOver (Cmd+F5) — navigate all controls with keyboard only
3. Test dirty indicator — edit file, verify dot in tab, verify alert on Cmd+Q
4. Test empty state — launch with no file, verify welcome screen
5. Test Cmd+P — verify print dialog opens with correct content
6. Test large file — try opening a 10MB markdown file, verify warning
7. Test file deletion — open a file, delete it in Finder, verify graceful handling
8. Run full test suite: `xcodebuild test -scheme QuickMDApp -only-testing QuickMDTests ...`
