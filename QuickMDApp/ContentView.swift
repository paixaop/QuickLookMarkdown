import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CodeEditorView

// MARK: - Comment Notification Names

extension Notification.Name {
    static let addCommentAction = Notification.Name("addCommentAction")
    static let removeCommentAction = Notification.Name("removeCommentAction")
    static let openFileRequest = Notification.Name("openFileRequest")
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

        // Check if there's a comment at the click point, and capture
        // selection text + source info atomically (before menu interaction
        // can collapse or shift the WebView selection).
        let group = DispatchGroup()
        var commentAtPoint: [String: Any]? = nil
        var selectedText: String = ""
        var selectionSourceInfo: [String: Any]? = nil

        group.enter()
        evaluateJavaScript("window.__getCommentAtPoint ? __getCommentAtPoint(\(jsX), \(jsY)) : null") { result, _ in
            if let dict = result as? [String: Any] {
                commentAtPoint = dict
            }
            group.leave()
        }

        group.enter()
        evaluateJavaScript("""
            (function() {
                var text = window.__getSelectionText ? __getSelectionText() : '';
                var info = window.__getSelectionSourceInfo ? __getSelectionSourceInfo() : null;
                return { text: text, info: info };
            })()
            """) { result, _ in
            if let dict = result as? [String: Any] {
                selectedText = dict["text"] as? String ?? ""
                selectionSourceInfo = dict["info"] as? [String: Any]
            }
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
                // Pass both text and source info so addCommentAction doesn't need to re-query JS
                addItem.representedObject = [
                    "text": selectedText,
                    "sourceLine": selectionSourceInfo?["sourceLine"] ?? -1,
                    "offsetInBlock": selectionSourceInfo?["offsetInBlock"] ?? -1,
                    "endOffsetInBlock": selectionSourceInfo?["endOffsetInBlock"] ?? -1
                ] as [String: Any]
                menu.insertItem(addItem, at: insertIndex)
                insertIndex += 1

                menu.insertItem(NSMenuItem.separator(), at: insertIndex)
            }
        }

        super.willOpenMenu(menu, with: event)
    }

    @objc private func addCommentAction(_ sender: NSMenuItem) {
        // Source info was pre-captured in willOpenMenu to avoid stale/collapsed selection
        guard let info = sender.representedObject as? [String: Any],
              let text = info["text"] as? String else { return }
        let sourceLine = info["sourceLine"] as? Int ?? -1
        let offsetInBlock = info["offsetInBlock"] as? Int ?? -1
        let endOffsetInBlock = info["endOffsetInBlock"] as? Int ?? -1
        commentCoordinator?.showCommentEditor(index: -1, comment: "", annotatedText: text, isNew: true, sourceLine: sourceLine, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock)
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
        guard let model = commentCoordinator?.model else { return }
        let updated = MarkdownDocumentModel.removeComment(at: index, in: model.rawContent)
        model.setContent(updated, actionName: "Remove Comment")
        ContentView.pushIncrementalUpdate(model: model)
    }
}

/// Intercepts window close to prompt for unsaved changes.
class WindowCloseDelegate: NSObject, NSWindowDelegate {
    weak var model: MarkdownDocumentModel?

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard sender.isDocumentEdited else { return true }
        let alert = NSAlert()
        alert.messageText = "Do you want to save the changes to this document?"
        alert.informativeText = "Your changes will be lost if you don\u{2019}t save them."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Don\u{2019}t Save")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            if let model = model, let url = model.currentURL {
                try? model.rawContent.write(to: url, atomically: true, encoding: .utf8)
                model.markClean()
                sender.isDocumentEdited = false
            }
            return true
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
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

    // Tab history: the back stack's TOP element is always the CURRENT tab.
    // goBackTab pops the current, then switches to the new top (the previous tab).
    @Published var tabBackStack: [URL] = []
    @Published var tabForwardStack: [URL] = []
    var canGoBackTab: Bool { tabBackStack.count >= 2 }
    var canGoForwardTab: Bool { !tabForwardStack.isEmpty }

    /// Track that a tab is being navigated away from (push current onto back stack, clear forward).
    /// Skips if the URL is already at the top (onTabBecameActive may have pushed it already).
    func pushTabHistory(_ url: URL) {
        if tabBackStack.last?.standardizedFileURL.path != url.standardizedFileURL.path {
            tabBackStack.append(url)
        }
        tabForwardStack.removeAll()
    }

    /// Called when a tab becomes active (e.g. user clicks a tab, or tab switch completes).
    /// Ensures the active tab is tracked at the top of the back stack so that
    /// "back" always returns to the last *actually visited* tab.
    func onTabBecameActive(_ url: URL) {
        if tabBackStack.last?.standardizedFileURL.path == url.standardizedFileURL.path { return }
        tabBackStack.append(url)
    }

    /// True while programmatic tab history navigation is in progress (suppresses duplicate stack pushes).
    var isNavigatingHistory = false

    func goBackTab() {
        // Top of stack is the current tab — pop it and push to forward
        guard tabBackStack.count >= 2 else { return }
        let current = tabBackStack.removeLast()
        tabForwardStack.append(current)
        // The new top is the previous tab — switch to it (don't pop, it stays as current)
        let prev = tabBackStack.last!
        isNavigatingHistory = true
        switchToTab(prev)
        isNavigatingHistory = false
    }

    func goForwardTab() {
        guard let next = tabForwardStack.popLast() else { return }
        // Push the next tab onto back stack (it becomes the new current)
        tabBackStack.append(next)
        isNavigatingHistory = true
        switchToTab(next)
        isNavigatingHistory = false
    }

    private func currentTabURL() -> URL? {
        webView?.commentCoordinator?.model?.currentURL ?? NSApp.keyWindow?.representedURL
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
    let model: MarkdownDocumentModel

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var lastTheme: String?
        /// The model for this tab's document — use this instead of AppDelegate.activeModel.
        weak var model: MarkdownDocumentModel?

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
                      let model = self.model else { return }
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
                    DispatchQueue.main.async { [weak self] in
                        self?.model?.tocHeadings = headings
                    }
                } else if let activeID = body["activeHeadingID"] as? String {
                    DispatchQueue.main.async { [weak self] in
                        self?.model?.activeTOCHeadingID = activeID
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
                    let endOffsetInBlock = body["endOffsetInBlock"] as? Int ?? -1

                    // If editor is not visible, show it first, then jump after a delay
                    if findEditorTextView() == nil {
                        WebViewStore.shared.showEditorCallback?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                            self.jumpEditorToWord(word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock)
                        }
                    } else {
                        jumpEditorToWord(word, sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock)
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
                    if let current = self.model?.currentURL {
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
                if let current = self.model?.currentURL {
                    WebViewStore.shared.pushTabHistory(current)
                }
                AppDelegate.pendingDirAccess = dirURL
                AppDelegate.pendingURL = url
                NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            } else {
                if let model = self.model {
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
            guard let model = self.model,
                  let textView = findEditorTextView() else { return }

            WebViewStore.shared.suppressEditorToRenderer = true
            Self.scrollTextView(textView, toSourceLine: line, fractionPast: fractionPast, frontmatterLineCount: model.frontmatterLineCount, rawContent: model.rawContent)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                WebViewStore.shared.suppressEditorToRenderer = false
            }
        }

        // MARK: - Double-click → jump to word in editor

        private func jumpEditorToWord(_ word: String, sourceLine: Int, sourceCol: Int, offsetInBlock: Int, endOffsetInBlock: Int = -1) {
            guard let model = self.model,
                  let textView = findEditorTextView() else { return }
            guard sourceLine > 0, offsetInBlock >= 0, endOffsetInBlock > offsetInBlock else { return }
            if let range = Self.sourceRangeFromRenderedOffsets(
                sourceLine: sourceLine, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock,
                frontmatterLineCount: model.frontmatterLineCount, source: model.rawContent
            ) {
                selectAndReveal(range, in: textView)
            }
        }

        private func selectAndReveal(_ range: NSRange, in textView: NSTextView) {
            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(range)
            textView.scrollRangeToVisible(range)
            textView.showFindIndicator(for: range)
        }

        // MARK: - Comment Editor

        func showCommentEditor(index: Int, comment: String, annotatedText: String, isNew: Bool, sourceLine: Int = -1, offsetInBlock: Int = -1, endOffsetInBlock: Int = -1) {
            guard !WebViewStore.shared.commentPanelOpen else { return }
            WebViewStore.shared.commentPanelOpen = true
            // Capture the model NOW from the tab's own coordinator, not a global.
            // If the user switches tabs before saving, a global would point
            // to the wrong file.
            guard let capturedModel = self.model else { return }
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
                    if isNew {
                        self.addCommentToSource(text: annotatedText, comment: newComment, model: capturedModel, sourceLine: sourceLine, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock)
                    } else {
                        let updated = MarkdownDocumentModel.updateComment(at: index, newComment: newComment, in: capturedModel.rawContent)
                        capturedModel.setContent(updated, actionName: "Update Comment")
                        ContentView.pushIncrementalUpdate(model: capturedModel)
                    }
                },
                onDelete: isNew ? nil : {
                    WebViewStore.shared.commentPanelOpen = false
                    panel.close()
                    let updated = MarkdownDocumentModel.removeComment(at: index, in: capturedModel.rawContent)
                    capturedModel.setContent(updated, actionName: "Remove Comment")
                    ContentView.pushIncrementalUpdate(model: capturedModel)
                },
                onCancel: {
                    WebViewStore.shared.commentPanelOpen = false
                    panel.close()
                }
            )

            panel.contentView = NSHostingView(rootView: view)
            panel.makeKeyAndOrderFront(nil)
        }

        private func addCommentToSource(text: String, comment: String, model: MarkdownDocumentModel, sourceLine: Int = -1, offsetInBlock: Int = -1, endOffsetInBlock: Int = -1) {
            let source = model.rawContent

            // Primary: use source line + rendered offsets to locate text directly
            if sourceLine > 0, offsetInBlock >= 0, endOffsetInBlock > offsetInBlock {
                if let range = Self.sourceRangeFromRenderedOffsets(
                    sourceLine: sourceLine, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock,
                    frontmatterLineCount: model.frontmatterLineCount, source: source
                ) {
                    let updated = MarkdownDocumentModel.addComment(around: range, comment: comment, in: source)
                    model.setContent(updated, actionName: "Add Comment")
                    ContentView.pushIncrementalUpdate(model: model)
                    return
                }
            }

            // Editor selection path (user selected text in the editor, not renderer)
            if let textView = findEditorTextView() {
                let selectedRange = textView.selectedRange()
                if selectedRange.length > 0 {
                    let updated = MarkdownDocumentModel.addComment(around: selectedRange, comment: comment, in: source)
                    model.setContent(updated, actionName: "Add Comment")
                    ContentView.pushIncrementalUpdate(model: model)
                }
            }
        }

        /// Map rendered text offsets (from the DOM) back to source character offsets.
        /// Walks the source line character by character, skipping markdown markers and
        /// comment annotations to build a rendered-offset → source-offset mapping.
        static func sourceRangeFromRenderedOffsets(sourceLine: Int, offsetInBlock: Int, endOffsetInBlock: Int, frontmatterLineCount: Int, source: String) -> NSRange? {
            let lines = source.components(separatedBy: "\n")
            var adjustedLine = sourceLine + frontmatterLineCount - 1
            guard adjustedLine >= 0, adjustedLine < lines.count else { return nil }

            // Detect fenced code blocks: data-source-line points to the opening
            // fence (``` or ~~~) but the rendered text is only the content inside.
            // Skip the fence line and collect content until the closing fence.
            let fenceTrimmed = lines[adjustedLine].trimmingCharacters(in: .whitespaces)
            let isFencedCode = fenceTrimmed.hasPrefix("```") || fenceTrimmed.hasPrefix("~~~")

            // Calculate character offset of the starting line in the source
            var lineCharOffset = 0
            for i in 0..<adjustedLine {
                lineCharOffset += lines[i].count + 1
            }

            var blockText = ""
            if isFencedCode {
                // Skip the opening fence line
                lineCharOffset += lines[adjustedLine].count + 1
                adjustedLine += 1
                // Collect content lines until the closing fence or end of file
                for i in adjustedLine..<lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") { break }
                    if i > adjustedLine { blockText += "\n" }
                    blockText += lines[i]
                }
            } else {
                // Collect lines for this block (until next blank line or heading)
                for i in adjustedLine..<lines.count {
                    let trimmed = lines[i].trimmingCharacters(in: .whitespaces)
                    if i > adjustedLine && (trimmed.isEmpty || trimmed.hasPrefix("#")) { break }
                    if i > adjustedLine { blockText += "\n" }
                    blockText += lines[i]
                }
            }

            // Walk blockText building a mapping: for each rendered character position,
            // track the corresponding source position.
            let nsBlock = blockText as NSString
            var renderedPos = 0
            var sourcePos = 0

            // For non-code blocks: skip block prefixes, inline markup, and comment markers.
            // For code blocks: only skip comment markers (code renders literally, but
            // preprocessComments converts comment markers to <mark> before parsing).
            if !isFencedCode, let prefixLen = skipBlockPrefix(in: blockText) {
                sourcePos = prefixLen
            }
            var startSourcePos = -1
            var endSourcePos = -1

            // Track the source position right after the last rendered character,
            // used when endOffset falls after skipped markup.
            var lastRenderedSourceEnd = 0

            while sourcePos < nsBlock.length {
                // Check for comment markers: <!-- COMMENT: ... --> or <!-- /COMMENT -->
                if let commentRange = skipCommentMarker(in: blockText, at: sourcePos) {
                    if renderedPos == endOffsetInBlock && endSourcePos < 0 { endSourcePos = sourcePos }
                    sourcePos = commentRange.upperBound
                    continue
                }

                // Check for inline markup markers (not applicable inside code blocks)
                if !isFencedCode, let markupLen = skipInlineMarkup(in: blockText, at: sourcePos) {
                    if renderedPos == endOffsetInBlock && endSourcePos < 0 { endSourcePos = sourcePos }
                    sourcePos += markupLen
                    continue
                }

                // This is a rendered character
                if renderedPos == offsetInBlock { startSourcePos = sourcePos }
                renderedPos += 1
                sourcePos += 1
                lastRenderedSourceEnd = sourcePos

                if renderedPos == endOffsetInBlock && endSourcePos < 0 { endSourcePos = lastRenderedSourceEnd }
            }

            // Handle end offset at the very end of the block
            if endSourcePos < 0 && renderedPos == endOffsetInBlock { endSourcePos = lastRenderedSourceEnd }

            guard startSourcePos >= 0, endSourcePos > startSourcePos else { return nil }
            return NSRange(location: lineCharOffset + startSourcePos, length: endSourcePos - startSourcePos)
        }

        /// If blockText at `pos` starts with a comment marker, return the range past it.
        private static func skipCommentMarker(in text: String, at pos: Int) -> Range<Int>? {
            let nsText = text as NSString
            let remaining = nsText.length - pos
            guard remaining >= 7 else { return nil } // minimum: <!---->

            // Check for <!-- at current position
            guard nsText.substring(with: NSRange(location: pos, length: 4)) == "<!--" else { return nil }

            // Find the closing -->
            let searchRange = NSRange(location: pos + 4, length: nsText.length - pos - 4)
            let closeRange = nsText.range(of: "-->", range: searchRange)
            guard closeRange.location != NSNotFound else { return nil }

            let markerText = nsText.substring(with: NSRange(location: pos, length: closeRange.location + 3 - pos))
            // Only skip COMMENT markers, not arbitrary HTML comments
            if markerText.contains("COMMENT") {
                return pos..<(closeRange.location + 3)
            }
            return nil
        }

        /// If blockText at `pos` starts with inline markup (*, **, ***, _, __, ~~, `),
        /// return the length of the markup.
        private static func skipInlineMarkup(in text: String, at pos: Int) -> Int? {
            let nsText = text as NSString
            let remaining = nsText.length - pos
            guard remaining > 0 else { return nil }

            let ch = nsText.character(at: pos)

            // Backtick runs
            if ch == 0x60 { // `
                var len = 1
                while pos + len < nsText.length && nsText.character(at: pos + len) == 0x60 { len += 1 }
                return len
            }

            // Strikethrough ~~
            if ch == 0x7E && remaining >= 2 && nsText.character(at: pos + 1) == 0x7E { // ~
                return 2
            }

            // Bold/italic: *, **, *** or _, __, ___
            if ch == 0x2A || ch == 0x5F { // * or _
                var len = 1
                while pos + len < nsText.length && nsText.character(at: pos + len) == ch && len < 3 { len += 1 }
                return len
            }

            return nil
        }

        /// Skip block-level markdown prefix at the start of a source line.
        /// Handles: `- `, `* `, `+ ` (unordered list), `1. ` (ordered list),
        /// `# `..`###### ` (headings), `> ` (blockquotes), `- [ ] ` / `- [x] ` (task lists).
        private static func skipBlockPrefix(in text: String) -> Int? {
            let nsText = text as NSString
            guard nsText.length > 0 else { return nil }

            // Leading whitespace (indented lists)
            var pos = 0
            while pos < nsText.length && (nsText.character(at: pos) == 0x20 || nsText.character(at: pos) == 0x09) {
                pos += 1
            }
            guard pos < nsText.length else { return nil }
            let afterIndent = pos

            let ch = nsText.character(at: pos)

            // Blockquote: > (possibly nested)
            if ch == 0x3E { // >
                pos += 1
                if pos < nsText.length && nsText.character(at: pos) == 0x20 { pos += 1 }
                return pos
            }

            // Heading: # through ######
            if ch == 0x23 { // #
                while pos < nsText.length && nsText.character(at: pos) == 0x23 && pos - afterIndent < 6 { pos += 1 }
                if pos < nsText.length && nsText.character(at: pos) == 0x20 { pos += 1 }
                return pos
            }

            // Unordered list: - , * , +  (followed by space)
            if (ch == 0x2D || ch == 0x2A || ch == 0x2B) && pos + 1 < nsText.length && nsText.character(at: pos + 1) == 0x20 {
                pos += 2
                // Task list: - [ ] or - [x]
                if pos + 3 <= nsText.length {
                    let taskCheck = nsText.substring(with: NSRange(location: pos, length: min(3, nsText.length - pos)))
                    if taskCheck == "[ ]" || taskCheck == "[x]" {
                        pos += 3
                        if pos < nsText.length && nsText.character(at: pos) == 0x20 { pos += 1 }
                    }
                }
                return pos
            }

            // Ordered list: digits followed by . or ) and space
            if ch >= 0x30 && ch <= 0x39 { // 0-9
                var numEnd = pos + 1
                while numEnd < nsText.length && nsText.character(at: numEnd) >= 0x30 && nsText.character(at: numEnd) <= 0x39 { numEnd += 1 }
                if numEnd < nsText.length {
                    let delim = nsText.character(at: numEnd)
                    if (delim == 0x2E || delim == 0x29) && numEnd + 1 < nsText.length && nsText.character(at: numEnd + 1) == 0x20 {
                        return numEnd + 2
                    }
                }
            }

            return afterIndent > 0 ? afterIndent : nil
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
            if let fragment = self.model?.pendingFragment {
                self.model?.pendingFragment = nil
                scrollToFragment(fragment, in: webView)
            }

            // Refresh native sidebar file tree (skip for edit-driven reloads — file tree doesn't change)
            if !store.isEditReload {
                DispatchQueue.main.async { [weak self] in
                    self?.model?.refreshFileTree()
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

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator()
        coordinator.model = model
        return coordinator
    }

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
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
            TextField("Search\u{2026}", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit { navigateNext() }
                .onChange(of: query) { _ in performSearch() }
                .accessibilityLabel("Search text")
            if matchCount > 0 {
                Text("\(currentIndex + 1)/\(matchCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
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
        .padding(.vertical, 8)
        .background(QuickMDDesignTokens.surfaceContainerLow(for: colorScheme))
        .overlay(
            RoundedRectangle(cornerRadius: QuickMDDesignTokens.cornerRadiusStitch)
                .stroke(
                    isFocused
                        ? QuickMDDesignTokens.primary(for: colorScheme).opacity(0.22)
                        : Color.clear,
                    lineWidth: 1.5
                )
        )
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
    @AppStorage("focusMode") var focusMode = false
    @Environment(\.colorScheme) private var colorScheme
    @State private var showEditor = false
    @State private var activePanel: SidebarPanel = .toc
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorDebounceTask: Task<Void, Never>?
    @State private var showSearchBar = false

    /// Stitch Focus Mode: hide sidebar and in-window search; main column uses full tonal surface.
    private var chromeSidebarVisible: Bool { !focusMode && showSidebar }
    private var chromeSearchVisible: Bool { !focusMode && showSearchBar }

    var body: some View {
        contentLayout
            .navigationTitle(model.windowTitle)
            .tint(QuickMDDesignTokens.primary(for: colorScheme))
            .toolbarBackground(focusMode ? .hidden : .automatic, for: .windowToolbar)
            .animation(QuickMDDesignTokens.contentAnimation(), value: focusMode)
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
            // Install window close delegate to prompt for unsaved changes
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let window = WebViewStore.shared.webView?.window {
                    let closeDelegate = WindowCloseDelegate()
                    closeDelegate.model = model
                    objc_setAssociatedObject(window, "windowCloseDelegate", closeDelegate, .OBJC_ASSOCIATION_RETAIN)
                    window.delegate = closeDelegate
                }
            }
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
            // Mark clean on file load (new file = no unsaved changes)
            model.markClean()
            DispatchQueue.main.async {
                // Set representedURL for tab proxy icon and window identification
                for window in NSApp.windows where window.isVisible && !window.isSheet {
                    if window.representedURL == nil || window.representedURL == model.currentURL {
                        window.representedURL = model.currentURL
                        window.isDocumentEdited = false
                        break
                    }
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

            // Fall through to renderer (WebView) selection — capture text + source info atomically
            guard let webView = WebViewStore.shared.webView else { return }
            webView.evaluateJavaScript("""
                (function() {
                    var text = window.__getSelectionText ? __getSelectionText() : '';
                    var info = window.__getSelectionSourceInfo ? __getSelectionSourceInfo() : null;
                    return { text: text, info: info };
                })()
                """) { result, _ in
                guard let dict = result as? [String: Any],
                      let text = dict["text"] as? String, !text.isEmpty else { return }
                let info = dict["info"] as? [String: Any]
                let sourceLine = info?["sourceLine"] as? Int ?? -1
                let offsetInBlock = info?["offsetInBlock"] as? Int ?? -1
                let endOffsetInBlock = info?["endOffsetInBlock"] as? Int ?? -1
                DispatchQueue.main.async {
                    webView.commentCoordinator?.showCommentEditor(
                        index: -1, comment: "", annotatedText: text,
                        isNew: true, sourceLine: sourceLine, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock
                    )
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
                    ContentView.pushIncrementalUpdate(model: model)
                    break
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .openFileRequest)) { notification in
            // Only the active model or an empty model should respond.
            // Without this guard, ALL tabs would load the file.
            guard AppDelegate.activeModel === model || model.currentURL == nil else { return }
            guard let url = notification.object as? URL else { return }
            model.load(from: url)
            AppDelegate.pendingURL = nil
        }
    }
}

extension ContentView {

    // MARK: - Content Layout

    private var contentLayout: some View {
        VStack(spacing: 0) {
            if chromeSearchVisible {
                SearchBar(isVisible: $showSearchBar)
            }
            ZStack(alignment: .bottomLeading) {
                HStack(spacing: 0) {
                    if sidebarPosition == "leading" && chromeSidebarVisible && model.html != nil {
                        sidebarContent
                            .frame(width: sidebarWidth)
                        SidebarResizeHandle(width: $sidebarWidth, isLeading: true)
                    }
                    Group {
                        if let html = model.html {
                            mainContentArea(html: html)
                        } else {
                            welcomeScreen
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(QuickMDDesignTokens.surface(for: colorScheme))
                    if sidebarPosition == "trailing" && chromeSidebarVisible && model.html != nil {
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
        .background(QuickMDDesignTokens.surface(for: colorScheme))
    }

    private var hoveredLinkIndicator: some View {
        Text(webViewStore.hoveredLinkURL)
            .font(.system(size: 11))
            .foregroundStyle(QuickMDDesignTokens.onSurface(for: colorScheme))
            .lineLimit(1)
            .truncationMode(.middle)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: QuickMDDesignTokens.cornerRadiusStitch))
            .overlay(
                RoundedRectangle(cornerRadius: QuickMDDesignTokens.cornerRadiusStitch)
                    .stroke(QuickMDDesignTokens.outlineVariant(for: colorScheme).opacity(0.15), lineWidth: 1)
            )
            .padding(.leading, 4)
            .padding(.bottom, 4)
            .allowsHitTesting(false)
            .transition(.opacity)
            .animation(QuickMDDesignTokens.contentAnimation(duration: 0.15), value: webViewStore.hoveredLinkURL)
    }

    // MARK: - Welcome Screen

    private var welcomeScreen: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "doc.richtext")
                .font(.system(size: 60))
                .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme).opacity(0.5))
            Text("QuickMD")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(QuickMDDesignTokens.onSurface(for: colorScheme))
            if let errorMessage = model.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            } else {
                Text("Open a markdown file to get started")
                    .font(.title3)
                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
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
            .buttonStyle(.borderedProminent)
            .tint(QuickMDDesignTokens.primary(for: colorScheme))
            .controlSize(.large)

            let recentURLs = NSDocumentController.shared.recentDocumentURLs
            if !recentURLs.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Recent Files")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                        .padding(.top, 8)
                    ForEach(recentURLs.prefix(5), id: \.self) { url in
                        Button(action: { model.load(from: url) }) {
                            HStack {
                                Image(systemName: "doc")
                                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
                                Text(url.lastPathComponent)
                                    .lineLimit(1)
                                    .foregroundStyle(QuickMDDesignTokens.onSurface(for: colorScheme))
                                Spacer()
                                Text(url.deletingLastPathComponent().lastPathComponent)
                                    .font(.caption)
                                    .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme))
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
                .foregroundStyle(QuickMDDesignTokens.onSurfaceVariant(for: colorScheme).opacity(0.7))
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Welcome screen")
    }

    // MARK: - Main Content Area

    @ViewBuilder
    private func mainContentArea(html: String) -> some View {
        HSplitView {
            WebView(html: html, baseURL: model.baseURL, theme: theme, model: model)
                .frame(minWidth: 200)
            if showEditor {
                MarkdownEditorView(text: $model.rawContent, position: $editorPosition, onTopLineChange: { line, fractionPast in
                    WebViewStore.shared.lastEditorLine = line
                    guard !WebViewStore.shared.suppressEditorToRenderer else { return }
                    guard let webView = WebViewStore.shared.webView else { return }
                    // Pause renderer→editor sync to prevent feedback loop
                    webView.evaluateJavaScript("if(window.__editorSyncPause) __editorSyncPause()") { _, _ in }
                    webView.evaluateJavaScript(
                        "if(window.__scrollToLine) __scrollToLine(\(line), \(fractionPast));"
                    ) { _, _ in
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            webView.evaluateJavaScript("if(window.__editorSyncResume) __editorSyncResume()") { _, _ in }
                        }
                    }
                }, currentFileURL: { model.currentURL })
                    .frame(minWidth: 200)
            }
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
    }

    // MARK: - Sidebar Content

    @ViewBuilder
    private var sidebarContent: some View {
        SidebarView(
            model: model,
            activePanel: $activePanel,
            onTOCClick: { heading in
                // Pause sync to prevent feedback loop, then scroll preview to heading
                guard let webView = WebViewStore.shared.webView else { return }
                webView.evaluateJavaScript("if(window.__editorSyncPause) __editorSyncPause()") { _, _ in }
                let safeID = heading.id.replacingOccurrences(of: "'", with: "\\'")
                webView.evaluateJavaScript(
                    "var el = document.getElementById('\(safeID)'); if(el) el.scrollIntoView({behavior:'smooth', block:'start'})"
                ) { _, _ in
                    // Resume sync after scroll animation settles
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        webView.evaluateJavaScript("if(window.__editorSyncResume) __editorSyncResume()") { _, _ in }
                    }
                }
                // Scroll editor to heading's source line
                if showEditor, let textView = findEditableTextView(in: NSApp.keyWindow?.contentView) {
                    WebViewStore.shared.suppressEditorToRenderer = true
                    WebView.Coordinator.scrollTextView(textView, toSourceLine: heading.sourceLine, frontmatterLineCount: model.frontmatterLineCount, rawContent: model.rawContent)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        WebViewStore.shared.suppressEditorToRenderer = false
                    }
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
                ContentView.pushIncrementalUpdate(model: model)
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
