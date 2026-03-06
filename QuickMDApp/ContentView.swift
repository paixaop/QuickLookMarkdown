import SwiftUI
import UniformTypeIdentifiers
import WebKit
import CodeEditorView

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
}

class WebViewStore: ObservableObject {
    static let shared = WebViewStore()
    weak var webView: ZoomableWebView?
    /// Set to true to suppress editor→renderer scroll sync (when renderer is driving)
    var suppressEditorToRenderer = false
    /// Last known editor scroll fraction (0…1), updated on every editor scroll
    var lastEditorFraction: CGFloat = 0
    /// True when an HTML reload is triggered by editor typing (not navigation)
    var isEditReload = false
    /// Callback to show the editor panel (set by ContentView)
    var showEditorCallback: (() -> Void)?
}

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let theme: String

    class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        var lastHTML: String?
        var lastTheme: String?

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

            case "editorSync":
                guard let type = body["type"] as? String else { return }
                if type == "scroll" {
                    // Suppress renderer→editor sync during edit-driven reloads
                    guard !WebViewStore.shared.isEditReload,
                          let fraction = body["fraction"] as? Double else { return }
                    scrollEditorToFraction(CGFloat(fraction))
                } else if type == "dblclick" {
                    guard let word = body["word"] as? String else { return }
                    let before = body["before"] as? String ?? ""
                    let after = body["after"] as? String ?? ""
                    let fraction = body["fraction"] as? Double ?? 0

                    // If editor is not visible, show it first, then jump after a delay
                    if findEditorTextView() == nil {
                        WebViewStore.shared.showEditorCallback?()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [self] in
                            self.jumpEditorToWord(word, before: before, after: after, fraction: fraction)
                        }
                    } else {
                        jumpEditorToWord(word, before: before, after: after, fraction: fraction)
                    }
                }

            default:
                break
            }
        }

        // MARK: - Renderer → Editor scroll sync

        private func scrollEditorToFraction(_ fraction: CGFloat) {
            guard let textView = findEditorTextView(),
                  let scrollView = textView.enclosingScrollView else { return }
            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let maxScroll = contentHeight - viewportHeight
            guard maxScroll > 0 else { return }
            // Suppress editor→renderer sync while we're driving from renderer
            WebViewStore.shared.suppressEditorToRenderer = true
            let targetY = fraction * maxScroll
            scrollView.contentView.scroll(to: NSPoint(x: 0, y: targetY))
            scrollView.reflectScrolledClipView(scrollView.contentView)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                WebViewStore.shared.suppressEditorToRenderer = false
            }
        }

        // MARK: - Double-click → jump to word in editor

        private func jumpEditorToWord(_ word: String, before: String, after: String, fraction: Double) {
            guard let model = AppDelegate.activeModel,
                  let textView = findEditorTextView() else { return }
            let source = model.rawContent
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

            guard !occurrences.isEmpty else { return }

            // Use document position fraction as primary locator:
            // estimate where in the source this word should be
            let targetPos = fraction * Double(max(1, nsSource.length))

            // Find the occurrence closest to the estimated source position
            var bestRange = occurrences[0]
            var bestDistance = abs(Double(bestRange.location) - targetPos)

            if occurrences.count > 1 {
                let beforeWords = before.split(separator: " ").map { $0.lowercased() }
                let afterWords = after.split(separator: " ").map { $0.lowercased() }

                for occ in occurrences {
                    let distance = abs(Double(occ.location) - targetPos)

                    if distance < bestDistance - Double(nsSource.length) * 0.02 {
                        // Clearly closer — use it
                        bestDistance = distance
                        bestRange = occ
                    } else if abs(distance - bestDistance) <= Double(nsSource.length) * 0.02 {
                        // Similar distance — use context words as tiebreaker
                        let occScore = contextScore(for: occ, in: nsSource, beforeWords: beforeWords, afterWords: afterWords)
                        let bestScore = contextScore(for: bestRange, in: nsSource, beforeWords: beforeWords, afterWords: afterWords)
                        if occScore > bestScore || (occScore == bestScore && distance < bestDistance) {
                            bestDistance = distance
                            bestRange = occ
                        }
                    }
                }
            }

            textView.window?.makeFirstResponder(textView)
            textView.setSelectedRange(bestRange)
            textView.scrollRangeToVisible(bestRange)
            textView.showFindIndicator(for: bestRange)
        }

        private func contextScore(for range: NSRange, in source: NSString, beforeWords: [String], afterWords: [String]) -> Int {
            let ctxStart = max(0, range.location - 200)
            let ctxEnd = min(source.length, range.location + range.length + 200)
            let ctx = source.substring(with: NSRange(location: ctxStart, length: ctxEnd - ctxStart)).lowercased()
            var score = 0
            for w in beforeWords where ctx.contains(w) { score += 1 }
            for w in afterWords where ctx.contains(w) { score += 1 }
            return score
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

            // For file URLs, open within the app
            if url.isFileURL {
                let standardized = url.standardizedFileURL

                // Check if already open in an existing tab/window
                for window in NSApp.windows {
                    if let represented = window.representedURL, represented.standardizedFileURL == standardized {
                        window.makeKeyAndOrderFront(nil)
                        if let tabGroup = window.tabGroup {
                            tabGroup.selectedWindow = window
                        }
                        decisionHandler(.cancel)
                        return
                    }
                }

                // Gain sandbox access via bookmarked parent directory
                let dirURL = MarkdownDocumentModel.accessDirectoryForFile(url)
                let openInNewTab = UserDefaults.standard.bool(forKey: "openLinksInNewTab")

                if openInNewTab {
                    // Keep directory scope alive until the new tab loads
                    AppDelegate.pendingDirAccess = dirURL
                    AppDelegate.pendingURL = url
                    NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
                } else {
                    if let model = AppDelegate.activeModel {
                        model.navigateTo(url)
                    }
                    if let dirURL { dirURL.stopAccessingSecurityScopedResource() }
                }

                decisionHandler(.cancel)
                return
            }

            // Open web URLs in the default browser
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard WebViewStore.shared.isEditReload else { return }
            // Restore scroll position to match the editor after an edit-driven reload
            let fraction = WebViewStore.shared.lastEditorFraction
            let js = """
            (function() {
                if (window.__editorSyncPause) __editorSyncPause();
                if (window.__setScrollFraction) __setScrollFraction(\(fraction));
                setTimeout(function() { if (window.__editorSyncResume) __editorSyncResume(); }, 200);
            })();
            """
            webView.evaluateJavaScript(js) { _, _ in
                DispatchQueue.main.async {
                    WebViewStore.shared.isEditReload = false
                }
            }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ZoomableWebView {
        MarkdownDocumentModel.log("WebView.makeNSView called, html length=\(html.count)")
        let config = WKWebViewConfiguration()

        // 1. Theme script (first, so __setTheme is available)
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

        // 11. TOC sidebar script
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.tocScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

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

        // 20. Anchor links (after TOC assigns IDs)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.anchorLinksScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 21. Presentation mode
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.presentationScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // 22. Checkbox toggle (enables clicking checkboxes to modify source)
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

        let view = ZoomableWebView(frame: .zero, configuration: config)
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
            if matchCount > 0 {
                Text("\(currentIndex + 1)/\(matchCount)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Button(action: navigatePrev) {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            Button(action: navigateNext) {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(matchCount == 0)
            Button(action: close) {
                Image(systemName: "xmark")
            }
            .buttonStyle(.borderless)
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

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = MarkdownDocumentModel()
    @AppStorage("theme") var theme = "system"
    @State private var showEditor = false
    @State private var editorPosition = CodeEditor.Position()
    @State private var editorDebounceTask: Task<Void, Never>?
    @State private var scrollSyncTask: Task<Void, Never>?
    @State private var showSearchBar = false

    var body: some View {
        VStack(spacing: 0) {
            if showSearchBar {
                SearchBar(isVisible: $showSearchBar)
            }
            Group {
            if let html = model.html {
                if showEditor {
                    HSplitView {
                        WebView(html: html, baseURL: model.baseURL, theme: theme)
                            .frame(minWidth: 200)
                        MarkdownEditorView(text: $model.rawContent, position: $editorPosition, onScrollFractionChange: { fraction in
                            // Always track the editor's scroll position
                            WebViewStore.shared.lastEditorFraction = fraction
                            // Skip if renderer is driving the scroll
                            guard !WebViewStore.shared.suppressEditorToRenderer else { return }
                            scrollSyncTask?.cancel()
                            scrollSyncTask = Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 50_000_000) // 50ms debounce
                                guard !Task.isCancelled else { return }
                                guard let webView = WebViewStore.shared.webView else { return }
                                // Pause renderer→editor sync to prevent feedback loop
                                webView.evaluateJavaScript("if(window.__editorSyncPause) __editorSyncPause()") { _, _ in }
                                webView.evaluateJavaScript(
                                    "if(window.__setScrollFraction) __setScrollFraction(\(fraction));"
                                ) { _, _ in
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        webView.evaluateJavaScript("if(window.__editorSyncResume) __editorSyncResume()") { _, _ in }
                                    }
                                }
                            }
                        })
                            .frame(minWidth: 200)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .onChange(of: model.rawContent) { newValue in
                        // Debounce re-render since CodeEditorView fires on every keystroke
                        editorDebounceTask?.cancel()
                        editorDebounceTask = Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3s
                            guard !Task.isCancelled else { return }
                            if let url = model.currentURL {
                                let ext = url.pathExtension.lowercased()
                                if ["md", "markdown", "mdown", "mkd"].contains(ext) {
                                    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
                                    try? newValue.write(to: tempURL, atomically: true, encoding: .utf8)
                                    let result = try? MarkdownDocumentModel.htmlBodyPublic(for: tempURL)
                                    if let r = result {
                                        // Flag as edit-driven so didFinish restores scroll position
                                        WebViewStore.shared.isEditReload = true
                                        model.html = MarkdownDocumentModel.wrapHTMLPublic(r.html, isMarkdown: r.isMarkdown)
                                    }
                                    try? FileManager.default.removeItem(at: tempURL)
                                }
                            }
                        }
                    }
                } else {
                    WebView(html: html, baseURL: model.baseURL, theme: theme)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("QuickLook Markdown")
                        .font(.title2)
                        .bold()
                    if let errorMessage = model.errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    } else {
                        Text("Drop a file here or use File \u{203A} Open.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        } // Group
        } // VStack
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button(action: { model.goBack() }) {
                    Image(systemName: "chevron.left")
                }
                .disabled(!model.canGoBack)
                .help("Back (⌘[)")

                Button(action: { model.goForward() }) {
                    Image(systemName: "chevron.right")
                }
                .disabled(!model.canGoForward)
                .help("Forward (⌘])")
            }
        }
        .focusedValue(\.documentModel, model)
        .focusedSceneValue(\.showEditor, $showEditor)
        .focusedSceneValue(\.showSearchBar, $showSearchBar)
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
            if let url = AppDelegate.pendingURL {
                MarkdownDocumentModel.log("onAppear: loading pendingURL \(url.path)")
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
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    window.title = model.fileName ?? "QuickMD"
                    window.representedURL = model.currentURL
                }
            }
        }
    }

}
