import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CodeEditorView

// MARK: - Comment Notification Names

extension Notification.Name {
    static let addCommentAction = Notification.Name("addCommentAction")
    static let removeCommentAction = Notification.Name("removeCommentAction")
}

// MARK: - FocusedValue for active document model

private struct FocusedModelKey: FocusedValueKey {
    typealias Value = MarkdownDocumentModel
}

private struct FocusedShowEditorKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct FocusedShowSearchBarKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct FocusedShowSidebarKey: FocusedValueKey {
    typealias Value = Binding<Bool>
}

private struct FocusedActivePanelKey: FocusedValueKey {
    typealias Value = Binding<SidebarPanel>
}

extension FocusedValues {
    var documentModel: MarkdownDocumentModel? {
        get { self[FocusedModelKey.self] }
        set { self[FocusedModelKey.self] = newValue }
    }
    var showEditor: Binding<Bool>? {
        get { self[FocusedShowEditorKey.self] }
        set { self[FocusedShowEditorKey.self] = newValue }
    }
    var showSearchBar: Binding<Bool>? {
        get { self[FocusedShowSearchBarKey.self] }
        set { self[FocusedShowSearchBarKey.self] = newValue }
    }
    var showSidebar: Binding<Bool>? {
        get { self[FocusedShowSidebarKey.self] }
        set { self[FocusedShowSidebarKey.self] = newValue }
    }
    var activePanel: Binding<SidebarPanel>? {
        get { self[FocusedActivePanelKey.self] }
        set { self[FocusedActivePanelKey.self] = newValue }
    }
}

// MARK: - WebView

/// WKWebView subclass that handles Cmd-+/-/0 zoom via native pageZoom.
class ZoomableWebView: WKWebView {
    private static let zoomStep: CGFloat = 0.1
    private static let minZoom: CGFloat = 0.5
    private static let maxZoom: CGFloat = 3.0

    func zoomIn() {
        pageZoom = min(pageZoom + Self.zoomStep, Self.maxZoom)
    }
    func zoomOut() {
        pageZoom = max(pageZoom - Self.zoomStep, Self.minZoom)
    }
    func zoomReset() {
        pageZoom = 1.0
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.command),
           let chars = event.charactersIgnoringModifiers {
            switch chars {
            case "=", "+": zoomIn(); return true
            case "-": zoomOut(); return true
            case "0": zoomReset(); return true
            default: break
            }
        }
        return super.performKeyEquivalent(with: event)
    }

    /// Reference to the coordinator for comment actions
    weak var commentCoordinator: WebView.Coordinator?

    override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
        // Get mouse position in web view coordinates
        let locationInView = convert(event.locationInWindow, from: nil)
        let jsX = locationInView.x
        let jsY = bounds.height - locationInView.y  // Flip Y for web coordinates

        // Check if there's a comment at the click point
        let group = DispatchGroup()
        var commentAtPoint: [String: Any]? = nil
        var selectedText: String = ""

        group.enter()
        evaluateJavaScript("window.__getCommentAtPoint ? __getCommentAtPoint(\(jsX), \(jsY)) : null") { result, _ in
            if let dict = result as? [String: Any] {
                commentAtPoint = dict
            }
            group.leave()
        }

        group.enter()
        evaluateJavaScript("window.__getSelectionText ? __getSelectionText() : ''") { result, _ in
            selectedText = result as? String ?? ""
            group.leave()
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }

            // Insert at the top of the menu
            var insertIndex = 0

            if let commentInfo = commentAtPoint {
                let editItem = NSMenuItem(title: "Edit Comment\u{2026}", action: #selector(self.editCommentAction(_:)), keyEquivalent: "")
                editItem.target = self
                editItem.representedObject = commentInfo
                menu.insertItem(editItem, at: insertIndex)
                insertIndex += 1

                let deleteItem = NSMenuItem(title: "Delete Comment", action: #selector(self.deleteCommentAction(_:)), keyEquivalent: "")
                deleteItem.target = self
                deleteItem.representedObject = commentInfo
                menu.insertItem(deleteItem, at: insertIndex)
                insertIndex += 1

                menu.insertItem(NSMenuItem.separator(), at: insertIndex)
            } else if !selectedText.isEmpty {
                let addItem = NSMenuItem(title: "Add Comment\u{2026}", action: #selector(self.addCommentAction(_:)), keyEquivalent: "")
                addItem.target = self
                addItem.representedObject = selectedText
                menu.insertItem(addItem, at: insertIndex)
                insertIndex += 1

                menu.insertItem(NSMenuItem.separator(), at: insertIndex)
            }
        }

        super.willOpenMenu(menu, with: event)
    }

    @objc private func addCommentAction(_ sender: NSMenuItem) {
        guard let text = sender.representedObject as? String else { return }
        // Try to get source line info for precise comment placement
        evaluateJavaScript("window.__getSelectionSourceInfo ? __getSelectionSourceInfo() : null") { [weak self] result, _ in
            var sourceLine = -1
            var offsetInBlock = -1
            if let info = result as? [String: Any] {
                sourceLine = info["sourceLine"] as? Int ?? -1
                offsetInBlock = info["offsetInBlock"] as? Int ?? -1
            }
            self?.commentCoordinator?.showCommentEditor(index: -1, comment: "", annotatedText: text, isNew: true, sourceLine: sourceLine, offsetInBlock: offsetInBlock)
        }
    }

    @objc private func editCommentAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any] else { return }
        let index = info["index"] as? Int ?? 0
        let comment = info["comment"] as? String ?? ""
        let text = info["text"] as? String ?? ""
        commentCoordinator?.showCommentEditor(index: index, comment: comment, annotatedText: text, isNew: false)
    }

    @objc private func deleteCommentAction(_ sender: NSMenuItem) {
        guard let info = sender.representedObject as? [String: Any] else { return }
        let index = info["index"] as? Int ?? 0
        guard let model = AppDelegate.activeModel else { return }
        let updated = MarkdownDocumentModel.removeComment(at: index, in: model.rawContent)
        model.setContent(updated, actionName: "Remove Comment")
    }
}

class WebViewStore: ObservableObject {
    static let shared = WebViewStore()
    weak var webView: ZoomableWebView?
    /// Set to true to suppress editor→renderer scroll sync (when renderer is driving)
    var suppressEditorToRenderer = false
    /// Last known editor scroll fraction (0…1), updated on every editor scroll (deprecated, kept for reload)
    var lastEditorFraction: CGFloat = 0
    /// Last known editor top line, updated on every editor scroll
    var lastEditorLine: Int = 1
    /// True when an HTML reload is triggered by editor typing (not navigation)
    var isEditReload = false
    /// True when an HTML reload is triggered by the file watcher
    var isFileWatcherReload = false
    /// Scroll fraction captured before a file watcher reload
    var preReloadScrollFraction: Double = 0
    /// Callback to show the editor panel (set by ContentView)
    var showEditorCallback: (() -> Void)?
    /// URL of the link currently hovered in the renderer (empty string = none)
    @Published var hoveredLinkURL: String = ""
    /// True when a comment editor panel is already open (prevents duplicates)
    var commentPanelOpen = false

    // MARK: - Shared tab navigation history (for back/forward across tabs)

    @Published var tabBackStack: [URL] = []
    @Published var tabForwardStack: [URL] = []
    var canGoBackTab: Bool { !tabBackStack.isEmpty }
    var canGoForwardTab: Bool { !tabForwardStack.isEmpty }

    /// Track that a tab is being navigated away from (push current onto back stack, clear forward)
    func pushTabHistory(_ url: URL) {
        tabBackStack.append(url)
        tabForwardStack.removeAll()
    }

    /// Called when a tab becomes active (e.g. user clicks a tab, or tab switch completes).
    /// Ensures the active tab is tracked at the top of the back stack so that
    /// "back" always returns to the last *actually visited* tab.
    func onTabBecameActive(_ url: URL) {
        let standardized = url.standardizedFileURL.path
        // If the active tab is already the top of the back stack, nothing to do
        if let top = tabBackStack.last, top.standardizedFileURL.path == standardized { return }
        // Push to back stack (don't clear forward — this is a tab switch, not a new navigation)
        tabBackStack.append(url)
    }

    /// True while programmatic tab history navigation is in progress (suppresses duplicate stack pushes).
    var isNavigatingHistory = false

    func goBackTab() {
        guard let prev = tabBackStack.popLast() else { return }
        if let current = currentTabURL() {
            // Don't push current if it's the same as where we're going
            if current.standardizedFileURL.path != prev.standardizedFileURL.path {
                tabForwardStack.append(current)
            }
        }
        isNavigatingHistory = true
        switchToTab(prev)
        isNavigatingHistory = false
    }

    func goForwardTab() {
        guard let next = tabForwardStack.popLast() else { return }
        if let current = currentTabURL() {
            if current.standardizedFileURL.path != next.standardizedFileURL.path {
                tabBackStack.append(current)
            }
        }
        isNavigatingHistory = true
        switchToTab(next)
        isNavigatingHistory = false
    }

    private func currentTabURL() -> URL? {
        AppDelegate.activeModel?.currentURL ?? NSApp.keyWindow?.representedURL
    }

    private func switchToTab(_ url: URL) {
        let targetPath = url.standardizedFileURL.path
        for window in NSApp.windows {
            if let represented = window.representedURL, represented.standardizedFileURL.path == targetPath {
                window.makeKeyAndOrderFront(nil)
                if let tabGroup = window.tabGroup {
                    tabGroup.selectedWindow = window
                }
                return
            }
        }
    }
}

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let theme: String

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var lastTheme: String?

        /// Scroll a WKWebView to an element by its ID (fragment/anchor).
        private func scrollToFragment(_ fragment: String, in webView: WKWebView) {
            let safeFragment = fragment.replacingOccurrences(of: "'", with: "\\'")
            let js = "document.getElementById('\(safeFragment)')?.scrollIntoView({behavior:'auto'})"
            webView.evaluateJavaScript(js) { _, _ in }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let body = message.body as? [String: Any] else { return }

            switch message.name {
            case "checkboxToggle":
                guard let index = body["index"] as? Int,
                      let checked = body["checked"] as? Bool,
                      let model = AppDelegate.activeModel else { return }
                let updated = MarkdownDocumentModel.toggleCheckbox(at: index, checked: checked, in: model.rawContent)
                model.rawContent = updated
                if let url = model.currentURL {
                    try? updated.write(to: url, atomically: true, encoding: .utf8)
                }

            case "linkClick":
                guard let urlString = body["url"] as? String,
                      let url = URL(string: urlString) else { return }
                handleLinkClick(url)

            case "linkHover":
                let url = body["url"] as? String ?? ""
                DispatchQueue.main.async {
                    WebViewStore.shared.hoveredLinkURL = url
                }

            case "fileClick":
                guard let path = body["path"] as? String else { return }
                let fileURL = URL(fileURLWithPath: path)
                DispatchQueue.main.async { [weak self] in
                    self?.handleLinkClick(fileURL)
                }

            case "commentAction":
                guard let type = body["type"] as? String else { return }
                if type == "click" {
                    let index = body["index"] as? Int ?? 0
                    let comment = body["comment"] as? String ?? ""
                    let text = body["text"] as? String ?? ""
                    showCommentEditor(index: index, comment: comment, annotatedText: text, isNew: false)
                } else if type == "add" {
                    let text = body["text"] as? String ?? ""
                    showCommentEditor(index: -1, comment: "", annotatedText: text, isNew: true)
                }

            case "tocData":
                if let headingsArray = body["headings"] as? [[String: Any]] {
                    let headings = headingsArray.compactMap { dict -> TOCHeading? in
                        guard let id = dict["id"] as? String,
                              let text = dict["text"] as? String,
                              let level = dict["level"] as? Int else { return nil }
                        let sourceLine = dict["sourceLine"] as? Int ?? 0
                        return TOCHeading(id: id, text: text, level: level, sourceLine: sourceLine)
                    }
                    DispatchQueue.main.async {
                        AppDelegate.activeModel?.tocHeadings = headings
                    }
                } else if let activeID = body["activeHeadingID"] as? String {
                    DispatchQueue.main.async {
                        AppDelegate.activeModel?.activeTOCHeadingID = activeID
                    }
                }

            case "editorSync":
                guard let type = body["type"] as? String else { return }
                if type == "scroll" {
                    // Suppress renderer→editor sync during edit-driven reloads
                    guard !WebViewStore.shared.isEditReload,
                          let line = body["line"] as? Int else { return }
                    let fractionPast = body["fractionPast"] as? Double ?? 0
                    scrollEditorToLine(line, fractionPast: CGFloat(fractionPast))
                } else if type == "dblclick" {
                    guard let word = body["word"] as? String else { return }
                    let sourceLine = body["sourceLine"] as? Int ?? -1
                    let sourceCol = body["sourceCol"] as? Int ?? -1
                    let offsetInBlock = body["offsetInBlock"] as? Int ?? -1

                    // If editor is not visible, show it first, then jump after a delay
                    if findEditorTextView() == nil {
                        WebViewStore.shared.showEditorCallback?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                            self.jumpEditorToWord(word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock)
                        }
                    } else {
                        jumpEditorToWord(word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock)
                    }
                }

            default:
                break
            }
        }

        // MARK: - Link click handling

        private func handleLinkClick(_ url: URL) {
            if url.isFileURL {
                openFileLink(url)
            } else {
                NSWorkspace.shared.open(url)
            }
        }

        func openFileLink(_ url: URL) {
            let standardized = url.standardizedFileURL

            // Check if already open in an existing tab/window
            for window in NSApp.windows {
                if let represented = window.representedURL, represented.standardizedFileURL == standardized {
                    // Track in shared tab history for back/forward
                    if let current = AppDelegate.activeModel?.currentURL {
                        WebViewStore.shared.pushTabHistory(current)
                    }
                    window.makeKeyAndOrderFront(nil)
                    if let tabGroup = window.tabGroup {
                        tabGroup.selectedWindow = window
                    }
                    // Scroll to anchor fragment if present
                    if let fragment = url.fragment, let wk = Self.findWebView(in: window) {
                        scrollToFragment(fragment, in: wk)
                    }
                    return
                }
            }

            // Gain sandbox access via bookmarked parent directory
            let dirURL = MarkdownDocumentModel.accessDirectoryForFile(url)
            let openInNewTab = UserDefaults.standard.bool(forKey: "openLinksInNewTab")

            if openInNewTab {
                // Track in shared tab history for back/forward
                if let current = AppDelegate.activeModel?.currentURL {
                    WebViewStore.shared.pushTabHistory(current)
                }
                AppDelegate.pendingDirAccess = dirURL
                AppDelegate.pendingURL = url
                NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            } else {
                if let model = AppDelegate.activeModel {
                    model.navigateTo(url)
                }
                if let dirURL { dirURL.stopAccessingSecurityScopedResource() }
            }
        }

        // MARK: - Renderer → Editor scroll sync (line-anchored)

        /// Scroll a text view to a given source line. Shared by editor sync and sidebar TOC click.
        static func scrollTextView(_ textView: NSTextView, toSourceLine line: Int, fractionPast: CGFloat = 0, frontmatterLineCount: Int, rawContent: String) {
            guard let scrollView = textView.enclosingScrollView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let adjustedLine = line + frontmatterLineCount - 1 // 0-based
            let lines = rawContent.components(separatedBy: "\n")
            guard adjustedLine >= 0, adjustedLine < lines.count else { return }

            var charOffset = 0
            for i in 0..<adjustedLine {
                charOffset += lines[i].count + 1
            }

            let nsLength = (rawContent as NSString).length
            guard nsLength > 0 else { return }

            let safeOffset = min(charOffset, nsLength - 1)
            let glyphRange = layoutManager.glyphRange(forCharacterRange: NSRange(location: safeOffset, length: 1), actualCharacterRange: nil)
            let lineRect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)

            let targetY = lineRect.origin.y + (fractionPast * lineRect.height) - textView.textContainerInset.height
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: max(0, targetY)))
            scrollView.reflectScrolledClipView(scrollView.contentView)
        }

        private func scrollEditorToLine(_ line: Int, fractionPast: CGFloat = 0) {
            guard let model = AppDelegate.activeModel,
                  let textView = findEditorTextView() else { return }

            WebViewStore.shared.suppressEditorToRenderer = true
            Self.scrollTextView(textView, toSourceLine: line, fractionPast: fractionPast, frontmatterLineCount: model.frontmatterLineCount, rawContent: model.rawContent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WebViewStore.shared.suppressEditorToRenderer = false
            }
        }

        // MARK: - Double-click → jump to word in editor

        private func jumpEditorToWord(_ word: String, sourceLine: Int, sourceCol: Int, offsetInBlock: Int) {
            guard let model = AppDelegate.activeModel,
                  let textView = findEditorTextView() else { return }
            let source = model.rawContent
            if let range = Self.findWordRange(word: word, in: source, sourceLine: sourceLine, offsetInBlock: offsetInBlock, frontmatterLineCount: model.frontmatterLineCount) {
                selectAndReveal(range, in: textView)
            }
        }

        /// Find the NSRange of a word in the source text using source-line mapping.
        /// Extracted as a static method for testability.
        static func findWordRange(word: String, in source: String, sourceLine: Int, offsetInBlock: Int, frontmatterLineCount: Int) -> NSRange? {
            let nsSource = source as NSString

            // Find all occurrences of the word in source
            var occurrences: [NSRange] = []
            var searchStart = 0
            while searchStart < nsSource.length {
                let range = nsSource.range(of: word, options: [.caseInsensitive],
                                           range: NSRange(location: searchStart, length: nsSource.length - searchStart))
                if range.location == NSNotFound { break }
                occurrences.append(range)
                searchStart = range.location + range.length
            }

            guard !occurrences.isEmpty else { return nil }

            // If only one occurrence, use it directly
            if occurrences.count == 1 {
                return occurrences[0]
            }

            // If we have a source line, use it for precise matching
            if sourceLine > 0 {
                let lines = source.components(separatedBy: "\n")
                let adjustedLine = sourceLine + frontmatterLineCount - 1 // 0-based
                guard adjustedLine >= 0 && adjustedLine < lines.count else {
                    // Fallback to closest-to-middle
                    let mid = nsSource.length / 2
                    return occurrences.min(by: { abs($0.location - mid) < abs($1.location - mid) })
                }

                // Calculate character offset of this line
                var lineCharOffset = 0
                for i in 0..<adjustedLine {
                    lineCharOffset += lines[i].count + 1 // +1 for newline
                }

                // Find the block's extent: from this line until the next blank line or heading
                var blockEndOffset = lineCharOffset
                for i in adjustedLine..<lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if i > adjustedLine && (trimmed.isEmpty || trimmed.hasPrefix("#")) { break }
                    blockEndOffset += lines[i].count + 1
                }

                // Filter occurrences to those within this block range (with small margin)
                let blockOccurrences = occurrences.filter {
                    $0.location >= max(0, lineCharOffset - 5) && $0.location < blockEndOffset + 5
                }

                if blockOccurrences.count == 1 {
                    return blockOccurrences[0]
                }

                // Use offsetInBlock to pick the closest occurrence
                let candidates = blockOccurrences.isEmpty ? occurrences : blockOccurrences
                let targetPos = lineCharOffset + max(0, offsetInBlock)
                return candidates.min(by: { abs($0.location - targetPos) < abs($1.location - targetPos) })
            }

            // Final fallback: pick occurrence nearest to document middle fraction
            let mid = nsSource.length / 2
            return occurrences.min(by: { abs($0.location - mid) < abs($1.location - mid) })
        }

        private func selectAndReveal(_ range: NSRange, in textView: NSTextView) {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        // MARK: - Comment Editor

        func showCommentEditor(index: Int, comment: String, annotatedText: String, isNew: Bool, sourceLine: Int = -1, offsetInBlock: Int = -1) {
            guard !WebViewStore.shared.commentPanelOpen else { return }
            WebViewStore.shared.commentPanelOpen = true
            let panel = NSPanel(
                contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered, defer: false
            )
            panel.title = isNew ? "Add Comment" : "Edit Comment"
            panel.isFloatingPanel = true
            panel.becomesKeyOnlyIfNeeded = false
            panel.level = .floating

            // Position near the mouse
            let mouseLocation = NSEvent.mouseLocation
            panel.setFrameOrigin(NSPoint(x: mouseLocation.x - 180, y: mouseLocation.y - 240))

            let view = CommentEditorView(
                annotatedText: annotatedText,
                initialComment: comment,
                isNew: isNew,
                onSave: { newComment in
                    WebViewStore.shared.commentPanelOpen = false
                    panel.close()
                    guard let model = AppDelegate.activeModel else { return }
                    if isNew {
                        self.addCommentToSource(text: annotatedText, comment: newComment, model: model, sourceLine: sourceLine, offsetInBlock: offsetInBlock)
                    } else {
                        let updated = MarkdownDocumentModel.updateComment(at: index, newComment: newComment, in: model.rawContent)
                        model.setContent(updated, actionName: "Update Comment")
                    }
                },
                onDelete: isNew ? nil : {
                    WebViewStore.shared.commentPanelOpen = false
                    panel.close()
                    guard let model = AppDelegate.activeModel else { return }
                    let updated = MarkdownDocumentModel.removeComment(at: index, in: model.rawContent)
                    model.setContent(updated, actionName: "Remove Comment")
                },
                onCancel: {
                    WebViewStore.shared.commentPanelOpen = false
                    panel.close()
                }
            )

            panel.contentView = NSHostingView(rootView: view)
            panel.makeKeyAndOrderFront(nil)
        }

        private func addCommentToSource(text: String, comment: String, model: MarkdownDocumentModel, sourceLine: Int = -1, offsetInBlock: Int = -1) {
            let source = model.rawContent
            // Decode HTML entities that may come from WebView selection
            let trimmedText = text
                .replacingOccurrences(of: "&amp;", with: "&")
                .replacingOccurrences(of: "&lt;", with: "<")
                .replacingOccurrences(of: "&gt;", with: ">")
                .replacingOccurrences(of: "&quot;", with: "\"")
                .replacingOccurrences(of: "&#39;", with: "'")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            // Use the same source-line mapping algorithm as double-click sync
            if let range = Self.findWordRange(word: trimmedText, in: source, sourceLine: sourceLine, offsetInBlock: offsetInBlock, frontmatterLineCount: model.frontmatterLineCount) {
                let updated = MarkdownDocumentModel.addComment(around: range, comment: comment, in: source)
                model.setContent(updated, actionName: "Add Comment")
                return
            }

            // Fallback: try editor selection (user selected text in the editor, not renderer)
            if let textView = findEditorTextView() {
                let selectedRange = textView.selectedRange()
                if selectedRange.length > 0 {
                    let updated = MarkdownDocumentModel.addComment(around: selectedRange, comment: comment, in: source)
                    model.setContent(updated, actionName: "Add Comment")
                }
            }
        }

        private func findEditorTextView() -> NSTextView? {
            // Try key window first, then main window, then all visible windows
            let candidates = [NSApp.keyWindow, NSApp.mainWindow].compactMap { $0 }
                + NSApp.windows.filter { $0.isVisible }
            for window in candidates {
                if let tv = findTextViewIn(window.contentView) {
                    return tv
                }
            }
            return nil
        }

        private func findTextViewIn(_ view: NSView?) -> NSTextView? {
            guard let view = view else { return nil }
            if let tv = view as? NSTextView, tv.isEditable { return tv }
            for sub in view.subviews {
                if let found = findTextViewIn(sub) { return found }
            }
            return nil
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow initial page load and fragment (anchor) navigation
            if navigationAction.navigationType == .other {
                decisionHandler(.allow)
                return
            }

            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            // Allow fragment-only navigation (anchor links within the page)
            if url.fragment != nil && url.path == (webView.url?.path ?? "") {
                decisionHandler(.allow)
                return
            }

            // Handle via shared link click logic (file links open in-app, web links in browser)
            handleLinkClick(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let store = WebViewStore.shared

            if store.isEditReload {
                // Restore scroll position to match the editor after an edit-driven reload
                let line = store.lastEditorLine
                let js = """
                (function() {
                    if (window.__editorSyncPause) __editorSyncPause();
                    if (window.__scrollToLine) __scrollToLine(\(line), 0);
                    setTimeout(function() { if (window.__editorSyncResume) __editorSyncResume(); }, 200);
                })();
                """
                webView.evaluateJavaScript(js) { _, _ in
                    DispatchQueue.main.async { store.isEditReload = false }
                }
            } else if store.isFileWatcherReload {
                // Restore scroll position after file watcher reload
                let fraction = store.preReloadScrollFraction
                let js = """
                (function() {
                    if (window.__editorSyncPause) __editorSyncPause();
                    if (window.__setScrollFraction) __setScrollFraction(\(fraction));
                    setTimeout(function() { if (window.__editorSyncResume) __editorSyncResume(); }, 200);
                })();
                """
                webView.evaluateJavaScript(js) { _, _ in
                    DispatchQueue.main.async { store.isFileWatcherReload = false }
                }
            }

            // Scroll to anchor fragment if navigating to a URL with #fragment
            if let fragment = AppDelegate.activeModel?.pendingFragment {
                AppDelegate.activeModel?.pendingFragment = nil
                scrollToFragment(fragment, in: webView)
            }

            // Refresh native sidebar file tree (skip for edit-driven reloads — file tree doesn't change)
            if !store.isEditReload {
                DispatchQueue.main.async {
                    AppDelegate.activeModel?.refreshFileTree()
                }
            }
        }

        /// Recursively find the first WKWebView in a window's view hierarchy.
        static func findWebView(in window: NSWindow) -> WKWebView? {
            func search(_ view: NSView) -> WKWebView? {
                if let wk = view as? WKWebView { return wk }
                for sub in view.subviews {
                    if let found = search(sub) { return found }
                }
                return nil
            }
            guard let contentView = window.contentView else { return nil }
            return search(contentView)
        }

        // injectFileTree removed — file tree is now native SwiftUI via model.refreshFileTree()
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomableWebView {
        MarkdownDocumentModel.log("WebView.makeNSView called, html length=\(html.count)")
        let config = WKWebViewConfiguration()

        // 0. Utils script (first, so shared helpers are available to all scripts)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.utilsScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 1. Theme script (so __setTheme is available)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.themeScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 2. Inject highlight.js + js-yaml (before render scripts)
        let highlightJS = MarkdownDocumentModel.highlightJS
        if !highlightJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: highlightJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }
        let jsYamlJS = MarkdownDocumentModel.jsYamlJS
        if !jsYamlJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: jsYamlJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }
        // 3. Highlight + format render script
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.highlightRenderScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 4. Line numbers (after highlight, before copy button)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.lineNumbersScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 5. Copy button on code blocks
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.copyButtonScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 6. KaTeX math rendering
        let katexJS = MarkdownDocumentModel.katexJS
        if !katexJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: katexJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
            let autoRenderJS = MarkdownDocumentModel.autoRenderJS
            if !autoRenderJS.isEmpty {
                config.userContentController.addUserScript(WKUserScript(
                    source: autoRenderJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
                ))
            }
            config.userContentController.addUserScript(WKUserScript(
                source: MarkdownDocumentModel.katexRenderScript,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }

        // 7. Inject mermaid.js
        let mermaidJS = MarkdownDocumentModel.mermaidJS
        MarkdownDocumentModel.log("Mermaid JS length for WKUserScript: \(mermaidJS.count)")
        if !mermaidJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: mermaidJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
            config.userContentController.addUserScript(WKUserScript(
                source: MarkdownDocumentModel.mermaidRenderScript,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }

        // 8. Graphviz rendering
        let graphvizJS = MarkdownDocumentModel.graphvizJS
        if !graphvizJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: graphvizJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
            config.userContentController.addUserScript(WKUserScript(
                source: MarkdownDocumentModel.graphvizRenderScript,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }

        // 9. Zoom overlay (mermaid diagrams + images + graphviz)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.zoomOverlayScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 10. Reading stats
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.readingStatsScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 11. TOC sidebar script — removed, replaced by headingDataScript (registered below)

        // 12. Font size controls
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.fontSizeScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 13. Jump to line
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.jumpToLineScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 14. Find in document
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.findScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 15. Speak (app only)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.speakScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 16. Emoji shortcodes (before highlight)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.emojiScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 17. Footnotes
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.footnotesScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 18. Frontmatter
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.frontmatterScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 19. Word wrap toggle
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.wordWrapScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 20. Anchor links (after heading-data assigns IDs)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.anchorLinksScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 21. Presentation mode
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.presentationScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 22. Link click interceptor (file:// links may be silently blocked by WKWebView)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.linkClickScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        config.userContentController.add(context.coordinator, name: "linkClick")

        // 22b. Link hover (show URL in status bar)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.linkHoverScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        config.userContentController.add(context.coordinator, name: "linkHover")

        // 23. Checkbox toggle (enables clicking checkboxes to modify source)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.checkboxToggleScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        config.userContentController.add(context.coordinator, name: "checkboxToggle")

        // 23. Editor sync (scroll + double-click to jump)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.editorSyncScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        config.userContentController.add(context.coordinator, name: "editorSync")

        // 24. Comment annotations (hover tooltips, click-to-edit, context menu)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.commentScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))
        config.userContentController.add(context.coordinator, name: "commentAction")

        // 24b-d. Sidebar scripts removed — sidebars are now native SwiftUI
        config.userContentController.add(context.coordinator, name: "fileClick")

        // TOC data bridge (heading list + active heading)
        config.userContentController.add(context.coordinator, name: "tocData")

        // Heading data script (assigns IDs, sends TOC to Swift, tracks active heading)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.headingDataScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 25. morphdom (incremental DOM diffing library)
        let morphdomJS = MarkdownDocumentModel.morphdomJS
        if !morphdomJS.isEmpty {
            config.userContentController.addUserScript(WKUserScript(
                source: morphdomJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }

        // 25. Incremental content update (uses morphdom for selective DOM updates)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.contentUpdateScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        let view = ZoomableWebView(frame: .zero, configuration: config)
        view.commentCoordinator = context.coordinator
        view.navigationDelegate = context.coordinator
        context.coordinator.lastHTML = html
        context.coordinator.lastTheme = theme
        view.loadHTMLString(html, baseURL: baseURL)
        MarkdownDocumentModel.log("WebView.loadHTMLString called, baseURL=\(baseURL?.path ?? "nil")")

        // Store reference for menu bar JS evaluation
        WebViewStore.shared.webView = view

        // Apply initial theme after page load
        if theme != "system" {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                view.evaluateJavaScript("if(window.__setTheme) __setTheme('\(theme)')") { _, _ in }
                Self.applyWindowAppearance(view: view, theme: theme)
            }
        }

        return view
    }

    func updateNSView(_ view: ZoomableWebView, context: Context) {
        // Store reference on every update
        WebViewStore.shared.webView = view

        if html != context.coordinator.lastHTML {
            MarkdownDocumentModel.log("WebView.updateNSView reloading, html length=\(html.count)")
            context.coordinator.lastHTML = html
            context.coordinator.lastTheme = theme
            view.loadHTMLString(html, baseURL: baseURL)
            // Apply theme after reload
            if theme != "system" {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    view.evaluateJavaScript("if(window.__setTheme) __setTheme('\(theme)')") { _, _ in }
                }
            }
            Self.applyWindowAppearance(view: view, theme: theme)
        } else if theme != context.coordinator.lastTheme {
            context.coordinator.lastTheme = theme
            view.evaluateJavaScript("if(window.__setTheme) __setTheme('\(theme)')") { _, _ in }
            Self.applyWindowAppearance(view: view, theme: theme)
        }
    }

    private static func applyWindowAppearance(view: NSView, theme: String) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            switch theme {
            case "dark": window.appearance = NSAppearance(named: .darkAqua)
            case "light": window.appearance = NSAppearance(named: .aqua)
            default: window.appearance = nil
            }
        }
    }
}

// MARK: - Comment Editor View

struct CommentEditorView: View {
    let annotatedText: String
    @State var commentText: String
    let isNew: Bool
    var onSave: (String) -> Void
    var onDelete: (() -> Void)?
    var onCancel: () -> Void
    @FocusState private var isTextFocused: Bool

    init(annotatedText: String, initialComment: String, isNew: Bool, onSave: @escaping (String) -> Void, onDelete: (() -> Void)?, onCancel: @escaping () -> Void) {
        self.annotatedText = annotatedText
        self._commentText = State(initialValue: initialComment)
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(isNew ? "Add Comment" : "Edit Comment")
                .font(.headline)

            // Show the annotated text for context
            GroupBox {
                Text(annotatedText)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            AutoFocusTextView(text: $commentText)
                .font(.system(size: 13))
                .frame(minHeight: 60, maxHeight: 120)
                .border(Color(nsColor: .separatorColor))

            HStack {
                if let onDelete {
                    Button("Delete", role: .destructive) { onDelete() }
                }
                Spacer()
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("Save \u{2318}\u{21A9}") { onSave(commentText) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 340)
    }
}

/// NSTextView wrapper that auto-focuses and places cursor at the end of text.
struct AutoFocusTextView: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        let textView = scrollView.documentView as! NSTextView
        textView.font = .systemFont(ofSize: 13)
        textView.isRichText = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.delegate = context.coordinator
        textView.string = text
        // Place cursor at end
        textView.setSelectedRange(NSRange(location: (text as NSString).length, length: 0))
        // Auto-focus after a short delay (panel needs time to become key)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            textView.window?.makeFirstResponder(textView)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        let textView = scrollView.documentView as! NSTextView
        if textView.string != text {
            let cursorPos = textView.selectedRange().location
            textView.string = text
            textView.setSelectedRange(NSRange(location: min(cursorPos, (text as NSString).length), length: 0))
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoFocusTextView
        init(_ parent: AutoFocusTextView) { self.parent = parent }
        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var isVisible: Bool
    @State private var query = ""
    @State private var matchCount = 0
    @State private var currentIndex = -1
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Search\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { navigateNext() }
                .onChange(of: query) { _ in performSearch() }
                .accessibilityLabel("Search text")
            if matchCount > 0 {
                Text("\(currentIndex + 1)/\(matchCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Match \(currentIndex + 1) of \(matchCount)")
            }
            Button(action: navigatePrev) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .accessibilityLabel("Previous match")
            Button(action: navigateNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            .accessibilityLabel("Next match")
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Close search")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(nsColor: .controlBackgroundColor))
        .onAppear { isFocused = true }
    }

    private func performSearch() {
        let escaped = query.replacingOccurrences(of: "'", with: "\\'")
        evalJSSearch("window.__searchHighlight ? __searchHighlight('\(escaped)') : 0") { count in
            matchCount = count
            currentIndex = count > 0 ? 0 : -1
        }
        highlightInEditor(query)
    }

    private func navigateNext() {
        evalJSSearch("window.__searchNext ? __searchNext() : -1") { idx in
            currentIndex = idx
        }
    }

    private func navigatePrev() {
        evalJSSearch("window.__searchPrev ? __searchPrev() : -1") { idx in
            currentIndex = idx
        }
    }

    private func close() {
        WebViewStore.shared.webView?.evaluateJavaScript("if(window.__searchClear) __searchClear()") { _, _ in }
        clearEditorHighlights()
        isVisible = false
    }

    private func evalJSSearch(_ js: String, completion: @escaping (Int) -> Void) {
        WebViewStore.shared.webView?.evaluateJavaScript(js) { result, _ in
            DispatchQueue.main.async {
                completion(result as? Int ?? 0)
            }
        }
    }

    private func highlightInEditor(_ query: String) {
        guard !query.isEmpty,
              let window = NSApp.keyWindow,
              let tv = findEditorTextView(in: window.contentView),
              let storage = tv.textStorage else {
            clearEditorHighlights()
            return
        }
        // Clear previous highlights
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
        let nsString = storage.string as NSString
        let lowerQuery = query.lowercased()
        var searchStart = 0
        while searchStart < nsString.length {
            let range = nsString.range(of: lowerQuery, options: [.caseInsensitive],
                                        range: NSRange(location: searchStart, length: nsString.length - searchStart))
            if range.location == NSNotFound { break }
            storage.addAttribute(.backgroundColor, value: NSColor.yellow.withAlphaComponent(0.3), range: range)
            searchStart = range.location + range.length
        }
    }

    private func clearEditorHighlights() {
        guard let window = NSApp.keyWindow,
              let tv = findEditorTextView(in: window.contentView),
              let storage = tv.textStorage else { return }
        storage.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: storage.length))
    }

    private func findEditorTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable { return tv }
        for sub in view.subviews {
            if let found = findEditorTextView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - ContentView helpers

fileprivate func findEditableTextView(in view: NSView?) -> NSTextView? {
    guard let view = view else { return nil }
    if let tv = view as? NSTextView, tv.isEditable { return tv }
    for sub in view.subviews {
        if let found = findEditableTextView(in: sub) { return found }
    }
    return nil
}

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = MarkdownDocumentModel()
    @ObservedObject private var webViewStore = WebViewStore.shared
    @AppStorage("theme") var theme = "system"
    @AppStorage("showSidebar") var showSidebar = true
    @AppStorage("sidebarPosition") var sidebarPosition = "leading"
    @AppStorage("sidebarWidth") var sidebarWidth: Double = 220
    @State private var showEditor = false
    @State private var activePanel: SidebarPanel = .toc
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorDebounceTask: Task<Void, Never>?
    @State private var scrollSyncTask: Task<Void, Never>?
    @State private var showSearchBar = false

    var body: some View {
        contentLayout
            .modifier(ContentViewToolbar(model: model, webViewStore: webViewStore, showEditor: $showEditor, showSearchBar: $showSearchBar, showSidebar: $showSidebar, activePanel: $activePanel))
            .modifier(ContentViewLifecycle(model: model, showEditor: $showEditor))
    }
}

// MARK: - ContentView Toolbar Modifier
private struct ContentViewToolbar: ViewModifier {
    @ObservedObject var model: MarkdownDocumentModel
    @ObservedObject var webViewStore: WebViewStore
    @Binding var showEditor: Bool
    @Binding var showSearchBar: Bool
    @Binding var showSidebar: Bool
    @Binding var activePanel: SidebarPanel

    func body(content: Content) -> some View {
        content
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                let openInNewTab = UserDefaults.standard.bool(forKey: "openLinksInNewTab")
                Button(action: {
                    if openInNewTab { webViewStore.goBackTab() } else { model.goBack() }
                }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(openInNewTab ? !webViewStore.canGoBackTab : !model.canGoBack)
                .help("Back (\u{2318}[)")
                .accessibilityLabel("Go back")

                Button(action: {
                    if openInNewTab { webViewStore.goForwardTab() } else { model.goForward() }
                }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(openInNewTab ? !webViewStore.canGoForwardTab : !model.canGoForward)
                .help("Forward (\u{2318}])")
                .accessibilityLabel("Go forward")
            }
        }
        .focusedValue(\.documentModel, model)
        .focusedSceneValue(\.showEditor, $showEditor)
        .focusedSceneValue(\.showSearchBar, $showSearchBar)
        .focusedSceneValue(\.showSidebar, $showSidebar)
        .focusedSceneValue(\.activePanel, $activePanel)
    }
}

// MARK: - ContentView Lifecycle Modifier
private struct ContentViewLifecycle: ViewModifier {
    @ObservedObject var model: MarkdownDocumentModel
    @Binding var showEditor: Bool

    func body(content: Content) -> some View {
        content
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                guard let data = data as? Data,
                      let path = String(data: data, encoding: .utf8),
                      let url = URL(string: path) else { return }
                DispatchQueue.main.async { model.load(from: url) }
            }
            return true
        }
        .onOpenURL { url in
            MarkdownDocumentModel.log("ContentView.onOpenURL: \(url.path)")
            // Always store as backup — on cold start the view receiving
            // onOpenURL may be replaced by SwiftUI before load completes.
            AppDelegate.pendingURL = url
            model.load(from: url)
        }
        .onAppear {
            AppDelegate.activeModel = model
            WebViewStore.shared.showEditorCallback = {
                showEditor = true
            }
            model.refreshParsedComments()
            model.refreshFileTree()
            // Track tab activation for back/forward history
            NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { notification in
                guard let window = notification.object as? NSWindow,
                      window.representedURL == model.currentURL,
                      let url = model.currentURL,
                      !WebViewStore.shared.isNavigatingHistory else { return }
                AppDelegate.activeModel = model
                WebViewStore.shared.onTabBecameActive(url)
            }
            if let url = AppDelegate.pendingURL {
                MarkdownDocumentModel.log("onAppear: loading pendingURL \(url.path)")
                model.pendingFragment = url.fragment
                model.load(from: url)
                AppDelegate.pendingURL = nil
                // Release directory security scope after load completes
                if let dirURL = AppDelegate.pendingDirAccess {
                    dirURL.stopAccessingSecurityScopedResource()
                    AppDelegate.pendingDirAccess = nil
                }
            } else {
                // Close this empty window/tab if another window already has content
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    guard model.html == nil else { return }
                    let visibleWindows = NSApp.windows.filter { $0.isVisible && !$0.isSheet }
                    let hasContentWindow = visibleWindows.contains { $0.representedURL != nil }
                    guard hasContentWindow else { return }
                    // Find and close blank windows (no representedURL, no content loaded)
                    if let blankWindow = visibleWindows.first(where: { $0.representedURL == nil && $0 != NSApp.mainWindow }) {
                        blankWindow.close()
                    }
                }
            }
        }
        .task {
            // Cold-start safety net: onOpenURL may fire before the view
            // is fully ready, so retry loading the pending URL.
            for delay in [0.1, 0.3, 0.5, 1.0, 2.0] {
                if model.html != nil { break }
                try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                if model.html == nil, let url = AppDelegate.pendingURL {
                    MarkdownDocumentModel.log("cold-start retry after \(delay)s: \(url.path)")
                    model.load(from: url)
                    AppDelegate.pendingURL = nil
                    if let dirURL = AppDelegate.pendingDirAccess {
                        dirURL.stopAccessingSecurityScopedResource()
                        AppDelegate.pendingDirAccess = nil
                    }
                }
            }
        }
        .onChange(of: model.fileName) { _ in
            model.refreshParsedComments()
            model.refreshFileTree()
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    if let url = model.currentURL {
                        let pathComponents = url.pathComponents
                        let count = pathComponents.count
                        if count >= 3 {
                            window.title = pathComponents[(count - 2)...].joined(separator: "/")
                        } else {
                            window.title = model.fileName ?? "QuickMD"
                        }
                    } else {
                        window.title = model.fileName ?? "QuickMD"
                    }
                    window.representedURL = model.currentURL
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .init("saveDocument"))) { _ in
            if let url = model.currentURL {
                try? model.rawContent.write(to: url, atomically: true, encoding: .utf8)
                model.markClean()
                if let window = WebViewStore.shared.webView?.window {
                    window.isDocumentEdited = false
                }
                ContentView.pushIncrementalUpdate(model: model)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .addCommentAction)) { _ in
            // Only the active model should respond; prevent duplicate panels
            guard AppDelegate.activeModel === model else { return }
            guard !WebViewStore.shared.commentPanelOpen else { return }
            // Try editor selection first
            if let window = NSApp.keyWindow,
               let textView = findEditableTextView(in: window.contentView),
               textView.selectedRange().length > 0,
               let selectedText = (textView.string as NSString?)?.substring(with: textView.selectedRange()) {
                let selectedRange = textView.selectedRange()
                WebViewStore.shared.commentPanelOpen = true
                let panel = NSPanel(
                    contentRect: NSRect(x: 0, y: 0, width: 360, height: 220),
                    styleMask: [.titled, .closable, .resizable],
                    backing: .buffered, defer: false
                )
                panel.title = "Add Comment"
                panel.isFloatingPanel = true
                panel.becomesKeyOnlyIfNeeded = false
                panel.level = .floating
                let mouseLocation = NSEvent.mouseLocation
                panel.setFrameOrigin(NSPoint(x: mouseLocation.x - 180, y: mouseLocation.y - 240))
                let view = CommentEditorView(
                    annotatedText: selectedText,
                    initialComment: "",
                    isNew: true,
                    onSave: { comment in
                        WebViewStore.shared.commentPanelOpen = false
                        panel.close()
                        let prefix = "<!-- COMMENT: \(comment) -->"
                        let suffix = "<!-- /COMMENT -->"
                        let wrapped = "\(prefix)\(selectedText)\(suffix)"
                        textView.insertText(wrapped, replacementRange: selectedRange)
                    },
                    onDelete: nil,
                    onCancel: {
                        WebViewStore.shared.commentPanelOpen = false
                        panel.close()
                    }
                )
                panel.contentView = NSHostingView(rootView: view)
                panel.makeKeyAndOrderFront(nil)
                return
            }

            // Fall through to renderer (WebView) selection
            guard let webView = WebViewStore.shared.webView else { return }
            webView.evaluateJavaScript("window.__getSelectionText ? __getSelectionText() : ''") { result, _ in
                guard let text = result as? String, !text.isEmpty else { return }
                webView.evaluateJavaScript("window.__getSelectionSourceInfo ? __getSelectionSourceInfo() : null") { infoResult, _ in
                    var sourceLine = -1
                    var offsetInBlock = -1
                    if let info = infoResult as? [String: Any] {
                        sourceLine = info["sourceLine"] as? Int ?? -1
                        offsetInBlock = info["offsetInBlock"] as? Int ?? -1
                    }
                    DispatchQueue.main.async {
                        webView.commentCoordinator?.showCommentEditor(
                            index: -1, comment: "", annotatedText: text,
                            isNew: true, sourceLine: sourceLine, offsetInBlock: offsetInBlock
                        )
                    }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeCommentAction)) { _ in
            guard AppDelegate.activeModel === model else { return }
            // Remove the comment at the cursor position in the editor
            guard let window = NSApp.keyWindow,
                  let textView = findEditableTextView(in: window.contentView) else { return }
            let cursorLocation = textView.selectedRange().location
            let comments = MarkdownDocumentModel.parseComments(in: model.rawContent)
            // Find the comment whose range contains the cursor
            for (i, c) in comments.enumerated() {
                if cursorLocation >= c.range.location && cursorLocation < c.range.location + c.range.length {
                    let updated = MarkdownDocumentModel.removeComment(at: i, in: model.rawContent)
                    model.setContent(updated, actionName: "Remove Comment")
                    break
                }
            }
        }
    }
}

extension ContentView {

    // MARK: - Content Layout

    private var contentLayout: some View {
        VStack(spacing: 0) {
            if showSearchBar {
                SearchBar(isVisible: $showSearchBar)
            }
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    if sidebarPosition == "leading" && showSidebar && model.html != nil {
                        sidebarContent
                            .frame(width: sidebarWidth)
                        SidebarResizeHandle(width: $sidebarWidth, isLeading: true)
                        Divider()
                    }
                    if let html = model.html {
                        mainContentArea(html: html)
                    } else {
                        welcomeScreen
                    }
                    if sidebarPosition == "trailing" && showSidebar && model.html != nil {
                        Divider()
                        SidebarResizeHandle(width: $sidebarWidth, isLeading: false)
                        sidebarContent
                            .frame(width: sidebarWidth)
                    }
                }
                if !webViewStore.hoveredLinkURL.isEmpty {
                    hoveredLinkIndicator
                }
            }
        }
    }

    private var hoveredLinkIndicator: some View {
        Text(webViewStore.hoveredLinkURL)
            .font(.system(size: 11))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 4))
            .padding(.leading, 4)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: webViewStore.hoveredLinkURL)
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 60))
                .foregroundStyle(.tertiary)
            Text("QuickMD")
                .font(.largeTitle)
                .fontWeight(.bold)
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("Open a markdown file to get started")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            Button("Open File\u{2026}") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.plainText, .sourceCode, .data]
                if panel.runModal() == .OK, let url = panel.url {
                    model.load(from: url)
                }
            }
            .controlSize(.large)

            let recentURLs = NSDocumentController.shared.recentDocumentURLs
            if !recentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Files")
                        .font(.headline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    ForEach(recentURLs.prefix(5), id: \.self) { url in
                        Button(action: { model.load(from: url) }) {
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                Spacer()
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: 350)
            }

            Spacer()
            Text("You can also drag files onto this window")
                .font(.caption)
                .foregroundStyle(.quaternary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome screen")
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private func mainContentArea(html: String) -> some View {
        if showEditor {
            HSplitView {
                WebView(html: html, baseURL: model.baseURL, theme: theme)
                    .frame(minWidth: 200)
                MarkdownEditorView(text: $model.rawContent, position: $editorPosition, onTopLineChange: { line, fractionPast in
                    WebViewStore.shared.lastEditorLine = line
                    guard !WebViewStore.shared.suppressEditorToRenderer else { return }
                    scrollSyncTask?.cancel()
                    scrollSyncTask = Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 50_000_000)
                        guard !Task.isCancelled else { return }
                        guard let webView = WebViewStore.shared.webView else { return }
                        webView.evaluateJavaScript("if(window.__editorSyncPause) __editorSyncPause()") { _, _ in }
                        webView.evaluateJavaScript(
                            "if(window.__scrollToLine) __scrollToLine(\(line), \(fractionPast));"
                        ) { _, _ in
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                webView.evaluateJavaScript("if(window.__editorSyncResume) __editorSyncResume()") { _, _ in }
                            }
                        }
                    }
                }, currentFileURL: { model.currentURL })
                    .frame(minWidth: 200)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: model.rawContent) { _, _ in
                if let window = WebViewStore.shared.webView?.window {
                    window.isDocumentEdited = true
                }
                model.isDirty = true
                editorDebounceTask?.cancel()
                editorDebounceTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 500_000_000)
                    guard !Task.isCancelled else { return }
                    model.refreshParsedComments()
                    ContentView.pushIncrementalUpdate(model: model)
                }
            }
        } else {
            WebView(html: html, baseURL: model.baseURL, theme: theme)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        SidebarView(
            model: model,
            activePanel: $activePanel,
            onTOCClick: { heading in
                // Scroll preview to heading element
                let safeID = heading.id.replacingOccurrences(of: "'", with: "\\'")
                WebViewStore.shared.webView?.evaluateJavaScript(
                    "document.getElementById('\(safeID)')?.scrollIntoView({behavior:'smooth'})"
                ) { _, _ in }
                // Scroll editor to heading's source line
                if let textView = findEditableTextView(in: NSApp.keyWindow?.contentView) {
                    WebView.Coordinator.scrollTextView(textView, toSourceLine: heading.sourceLine, frontmatterLineCount: model.frontmatterLineCount, rawContent: model.rawContent)
                }
            },
            onCommentClick: { comment in
                if let textView = findEditableTextView(in: NSApp.keyWindow?.contentView) {
                    if !showEditor { showEditor = true }
                    DispatchQueue.main.asyncAfter(deadline: .now() + (showEditor ? 0 : 0.3)) {
                        textView.setSelectedRange(comment.range)
                        textView.scrollRangeToVisible(comment.range)
                    }
                }
                // Also scroll preview to the comment
                WebViewStore.shared.webView?.evaluateJavaScript(
                    "document.querySelectorAll('.qmd-comment')[\(comment.id)]?.scrollIntoView({behavior:'smooth'})"
                ) { _, _ in }
            },
            onCommentEdit: { comment in
                // Reuse existing comment editor via the coordinator
                WebViewStore.shared.webView?.commentCoordinator?.showCommentEditor(
                    index: comment.id, comment: comment.comment, annotatedText: comment.annotatedText, isNew: false
                )
            },
            onCommentDelete: { comment in
                let updated = MarkdownDocumentModel.removeComment(at: comment.id, in: model.rawContent)
                model.setContent(updated, actionName: "Remove Comment")
                model.refreshParsedComments()
            },
            onFileClick: { path in
                let url = URL(fileURLWithPath: path)
                WebViewStore.shared.webView?.commentCoordinator?.openFileLink(url)
            }
        )
    }

    /// Push an incremental DOM update to the renderer WebView from the current model content.
    /// Falls back to a full re-render if the JS update fails.
    static func pushIncrementalUpdate(model: MarkdownDocumentModel) {
        guard let url = model.currentURL else { return }
        let ext = url.pathExtension.lowercased()
        guard MarkdownDocumentModel.isMarkdownExtension(ext) else { return }

        let bodyHTML = MarkdownDocumentModel.markdownBodyHTML(from: model.rawContent)
        guard let webView = WebViewStore.shared.webView else {
            model.rerender()
            return
        }
        let escaped = bodyHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        webView.evaluateJavaScript("if(window.__updateContent) { __updateContent(`\(escaped)`); true } else { false }") { result, error in
            if error != nil || result as? Bool != true {
                DispatchQueue.main.async { model.rerender() }
            }
        }
    }
}
