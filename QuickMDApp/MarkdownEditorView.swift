import SwiftUI
import CodeEditorView
import LanguageSupport

// MARK: - Markdown Formatting Toolbar

struct MarkdownFormattingToolbar: View {
    @Binding var text: String
    var currentFileURL: (() -> URL?)?
    @Environment(\.colorScheme) private var colorScheme

    private struct ToolbarItem: Identifiable {
        let id = UUID()
        let label: String
        let icon: String?
        let snippet: String
        let wrap: (String, String)?  // (prefix, suffix) for wrapping selection
    }

    private struct ToolbarGroup: Identifiable {
        let id = UUID()
        let items: [ToolbarItem]
    }

    private let groups: [ToolbarGroup] = [
        // Headings
        ToolbarGroup(items: [
            ToolbarItem(label: "H1", icon: nil, snippet: "# ", wrap: nil),
            ToolbarItem(label: "H2", icon: nil, snippet: "## ", wrap: nil),
            ToolbarItem(label: "H3", icon: nil, snippet: "### ", wrap: nil),
        ]),
        // Inline formatting
        ToolbarGroup(items: [
            ToolbarItem(label: "Bold", icon: "bold", snippet: "**text**", wrap: ("**", "**")),
            ToolbarItem(label: "Italic", icon: "italic", snippet: "*text*", wrap: ("*", "*")),
            ToolbarItem(label: "Strikethrough", icon: "strikethrough", snippet: "~~text~~", wrap: ("~~", "~~")),
            ToolbarItem(label: "Code", icon: nil, snippet: "`code`", wrap: ("`", "`")),
        ]),
        // Block elements
        ToolbarGroup(items: [
            ToolbarItem(label: "Link", icon: "link", snippet: "[title](url)", wrap: ("[", "](url)")),
            ToolbarItem(label: "Image", icon: "photo", snippet: "![alt](url)", wrap: nil),
            ToolbarItem(label: "Code Block", icon: nil, snippet: "```\n\n```", wrap: ("```\n", "\n```")),
            ToolbarItem(label: "Quote", icon: "text.quote", snippet: "> ", wrap: nil),
            ToolbarItem(label: "Table", icon: "tablecells", snippet: "| Column 1 | Column 2 |\n|----------|----------|\n| Cell 1   | Cell 2   |", wrap: nil),
        ]),
        // Lists
        ToolbarGroup(items: [
            ToolbarItem(label: "UL", icon: "list.bullet", snippet: "- ", wrap: nil),
            ToolbarItem(label: "OL", icon: "list.number", snippet: "1. ", wrap: nil),
            ToolbarItem(label: "Task", icon: "checklist", snippet: "- [ ] ", wrap: nil),
        ]),
        // Misc
        ToolbarGroup(items: [
            ToolbarItem(label: "HR", icon: "minus", snippet: "\n---\n", wrap: nil),
        ]),
    ]

    // GitHub alert snippets shown in a menu
    private struct AlertType: Identifiable {
        let id = UUID()
        let name: String
        let snippet: String
    }

    private let alerts: [AlertType] = [
        AlertType(name: "Note", snippet: "> [!NOTE]\n> "),
        AlertType(name: "Tip", snippet: "> [!TIP]\n> "),
        AlertType(name: "Important", snippet: "> [!IMPORTANT]\n> "),
        AlertType(name: "Warning", snippet: "> [!WARNING]\n> "),
        AlertType(name: "Caution", snippet: "> [!CAUTION]\n> "),
    ]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(groups.enumerated()), id: \.element.id) { index, group in
                if index > 0 {
                    Divider().frame(height: 24).padding(.horizontal, 4)
                }
                ForEach(group.items) { item in
                    Button(action: { insert(item) }) {
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 16))
                                .frame(width: 32, height: 32)
                        } else {
                            Text(item.label)
                                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                                .frame(minWidth: 32, minHeight: 32)
                        }
                    }
                    .buttonStyle(.borderless)
                    .help(item.label)
                    .accessibilityLabel(accessibilityLabelFor(item.label))
                }
            }

            Divider().frame(height: 24).padding(.horizontal, 4)

            // GitHub Alerts menu
            Menu {
                ForEach(alerts) { alert in
                    Button(alert.name) {
                        insertSnippet(alert.snippet)
                    }
                }
            } label: {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
            }
            .menuStyle(.borderlessButton)
            .frame(width: 40)
            .help("GitHub Alerts")
            .accessibilityLabel("GitHub Alerts")

            Divider().frame(height: 24).padding(.horizontal, 4)

            // Comment button
            Button(action: { addCommentFromToolbar() }) {
                Image(systemName: "text.bubble")
                    .font(.system(size: 16))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderless)
            .help("Add Comment")
            .accessibilityLabel("Add comment")

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
    }

    private func accessibilityLabelFor(_ label: String) -> String {
        switch label {
        case "H1": return "Heading level 1"
        case "H2": return "Heading level 2"
        case "H3": return "Heading level 3"
        case "Code": return "Inline code"
        case "Code Block": return "Code block"
        case "Link": return "Insert link"
        case "Image": return "Insert image"
        case "Quote": return "Blockquote"
        case "Table": return "Insert table"
        case "UL": return "Bullet list"
        case "OL": return "Numbered list"
        case "Task": return "Task list"
        case "HR": return "Horizontal rule"
        default: return label
        }
    }

    private func addCommentFromToolbar() {
        guard let textView = findEditorTextView() else { return }
        let selectedRange = textView.selectedRange()
        guard selectedRange.length > 0,
              let selectedText = (textView.string as NSString?)?.substring(with: selectedRange) else { return }
        showCommentPanel(selectedText: selectedText, selectedRange: selectedRange, textView: textView)
    }

    private func showCommentPanel(selectedText: String, selectedRange: NSRange, textView: NSTextView) {
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
                panel.close()
                let prefix = "<!-- COMMENT: \(comment) -->"
                let suffix = "<!-- /COMMENT -->"
                let wrapped = "\(prefix)\(selectedText)\(suffix)"
                textView.insertText(wrapped, replacementRange: selectedRange)
            },
            onDelete: nil,
            onCancel: { panel.close() }
        )
        panel.contentView = NSHostingView(rootView: view)
        panel.makeKeyAndOrderFront(nil)
    }

    private func insert(_ item: ToolbarItem) {
        // For heading/list prefixes, ensure we're on a new line
        if item.wrap == nil && !item.snippet.contains("\n") {
            let needsNewline = !text.isEmpty && !text.hasSuffix("\n")
            insertSnippet((needsNewline ? "\n" : "") + item.snippet)
        } else {
            insertSnippet(item.snippet)
        }
    }

    private func insertSnippet(_ snippet: String) {
        if let textView = findEditorTextView() {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0,
               let selectedText = (textView.string as NSString?)?.substring(with: selectedRange) {
                // Link button with filename-like selection: resolve to file link
                if snippet == "[title](url)", let link = resolveFileLink(selectedText) {
                    textView.insertText(link, replacementRange: selectedRange)
                    return
                }
                if let (prefix, suffix) = findWrapPattern(for: snippet) {
                    let wrapped = prefix + selectedText + suffix
                    textView.insertText(wrapped, replacementRange: selectedRange)
                    return
                }
            }
            textView.insertText(snippet, replacementRange: selectedRange)
        } else {
            text += snippet
        }
    }

    /// If text looks like a filename, resolve it relative to the current file and return a markdown link.
    private func resolveFileLink(_ name: String) -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // Must have a file extension
        guard let dot = trimmed.lastIndex(of: "."),
              dot > trimmed.startIndex,
              trimmed.distance(from: dot, to: trimmed.endIndex) <= 10 else { return nil }
        // No spaces allowed unless the whole thing is a path
        let looksLikePath = trimmed.contains("/") || !trimmed.contains(" ")
        guard looksLikePath else { return nil }

        // Try to resolve relative to current file's directory
        if let baseURL = currentFileURL?()?.deletingLastPathComponent() {
            let candidate = baseURL.appendingPathComponent(trimmed)
            if FileManager.default.fileExists(atPath: candidate.path) {
                let relativePath = trimmed.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? trimmed
                return "[\(trimmed)](\(relativePath))"
            }
            // Also try just the filename in the same directory
            let nameOnly = (trimmed as NSString).lastPathComponent
            let candidate2 = baseURL.appendingPathComponent(nameOnly)
            if FileManager.default.fileExists(atPath: candidate2.path) {
                let relativePath = nameOnly.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? nameOnly
                return "[\(nameOnly)](\(relativePath))"
            }
        }
        // File not found on disk — still use it as a relative link
        return "[\(trimmed)](\(trimmed))"
    }

    private func findWrapPattern(for snippet: String) -> (String, String)? {
        for group in groups {
            for item in group.items {
                if item.snippet == snippet, let wrap = item.wrap {
                    return wrap
                }
            }
        }
        return nil
    }

    private func findEditorTextView() -> NSTextView? {
        guard let window = NSApp.keyWindow else { return nil }
        return findTextView(in: window.contentView)
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Editor Font Manager

/// Manages the editor font via NSFontPanel. Persists font name and size in UserDefaults.
final class EditorFontManager: NSObject {
    static let shared = EditorFontManager()

    var editorFont: NSFont {
        let name = UserDefaults.standard.string(forKey: "editorFontName") ?? "Menlo"
        let size = CGFloat(UserDefaults.standard.double(forKey: "editorFontSize").rounded() == 0 ? 13 : UserDefaults.standard.double(forKey: "editorFontSize"))
        return NSFont(name: name, size: size) ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    func showFontPanel() {
        let fontManager = NSFontManager.shared
        fontManager.target = self
        fontManager.setSelectedFont(editorFont, isMultiple: false)
        fontManager.orderFrontFontPanel(nil)
    }

    @objc func changeFont(_ sender: Any?) {
        guard let fontManager = sender as? NSFontManager else { return }
        let newFont = fontManager.convert(editorFont)
        UserDefaults.standard.set(newFont.fontName, forKey: "editorFontName")
        UserDefaults.standard.set(Double(newFont.pointSize), forKey: "editorFontSize")
        applyToEditor()
    }

    func applyToEditor() {
        guard let window = NSApp.keyWindow else { return }
        if let tv = findTextView(in: window.contentView) {
            tv.font = editorFont
        }
    }

    /// Apply font after a delay (for when the editor is first created).
    func applyToEditorDeferred() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.applyToEditor()
        }
    }

    private func findTextView(in view: NSView?) -> NSTextView? {
        guard let view = view else { return nil }
        if let tv = view as? NSTextView, tv.isEditable { return tv }
        for sub in view.subviews {
            if let found = findTextView(in: sub) { return found }
        }
        return nil
    }
}

// MARK: - Auto-Pair Handler

/// Installs an NSEvent local monitor that auto-pairs brackets, backticks, and markdown formatting.
final class AutoPairHandler: ObservableObject {
    private var monitor: Any?
    private var isInserting = false

    private static let pairs: [(String, String)] = [
        ("(", ")"), ("[", "]"), ("{", "}"),
        ("`", "`"), ("*", "*"), ("~", "~"),
    ]

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self, !self.isInserting else { return event }
            guard UserDefaults.standard.bool(forKey: "autoPair") else { return event }
            return self.handleKeyEvent(event)
        }
    }

    func uninstall() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) -> NSEvent? {
        guard let chars = event.charactersIgnoringModifiers, chars.count == 1,
              let window = NSApp.keyWindow,
              let textView = findEditorTextViewInView(window.contentView) else { return event }

        let char = chars
        let selectedRange = textView.selectedRange()
        let nsString = textView.string as NSString

        // Check if typed char is a closing char and the next char matches — skip over it
        for (open, close) in Self.pairs where close == char && open != close {
            let nextIdx = selectedRange.location + selectedRange.length
            if nextIdx < nsString.length && nsString.substring(with: NSRange(location: nextIdx, length: 1)) == close && selectedRange.length == 0 {
                isInserting = true
                textView.setSelectedRange(NSRange(location: nextIdx + 1, length: 0))
                isInserting = false
                return nil
            }
        }

        // Handle backtick + Enter for code fences
        if char == "\r" || char == "\n" {
            let loc = selectedRange.location
            if loc >= 3 {
                let before = nsString.substring(with: NSRange(location: loc - 3, length: 3))
                if before == "```" && (loc == nsString.length || nsString.substring(with: NSRange(location: loc, length: min(1, nsString.length - loc))) == "\n" || loc == nsString.length) {
                    isInserting = true
                    textView.insertText("\n\n```", replacementRange: selectedRange)
                    textView.setSelectedRange(NSRange(location: loc + 1, length: 0))
                    isInserting = false
                    return nil
                }
            }
        }

        // Auto-pair: wrap selection or insert pair
        for (open, close) in Self.pairs where open == char {
            isInserting = true
            if selectedRange.length > 0 {
                let selected = nsString.substring(with: selectedRange)
                textView.insertText(open + selected + close, replacementRange: selectedRange)
                textView.setSelectedRange(NSRange(location: selectedRange.location + open.count, length: selected.count))
            } else {
                textView.insertText(open + close, replacementRange: selectedRange)
                textView.setSelectedRange(NSRange(location: selectedRange.location + open.count, length: 0))
            }
            isInserting = false
            return nil
        }

        return event
    }

    deinit { uninstall() }
}

// MARK: - Image Paste Handler

/// Handles Cmd+V image paste: saves PNG to images/ subdir next to the .md file and inserts markdown link.
final class ImagePasteHandler: ObservableObject {
    private var monitor: Any?
    var currentFileURL: (() -> URL?)?

    func install() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self = self,
                  event.modifierFlags.contains(.command),
                  event.charactersIgnoringModifiers == "v" else { return event }
            return self.handlePaste(event)
        }
    }

    func uninstall() {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }
    }

    private func handlePaste(_ event: NSEvent) -> NSEvent? {
        let pasteboard = NSPasteboard.general
        guard let window = NSApp.keyWindow,
              let textView = findEditorTextViewInView(window.contentView) else { return event }

        // Check for image data on pasteboard
        var imageData: Data?

        if let data = pasteboard.data(forType: .png) {
            imageData = data
        } else if let data = pasteboard.data(forType: .tiff),
                  let image = NSImage(data: data),
                  let tiffRep = image.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffRep),
                  let png = bitmap.representation(using: .png, properties: [:]) {
            imageData = png
        } else if let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] {
            // Check if any URL is an image file
            let imageExts = Set(["png", "jpg", "jpeg", "gif", "webp", "svg", "bmp", "tiff"])
            if let imageURL = urls.first(where: { imageExts.contains($0.pathExtension.lowercased()) }) {
                if let data = try? Data(contentsOf: imageURL),
                   let image = NSImage(data: data),
                   let tiffRep = image.tiffRepresentation,
                   let bitmap = NSBitmapImageRep(data: tiffRep),
                   let png = bitmap.representation(using: .png, properties: [:]) {
                    imageData = png
                }
            }
        }

        guard let pngData = imageData else { return event } // Not an image, let normal paste handle it

        guard let fileURL = currentFileURL?() else {
            let alert = NSAlert()
            alert.messageText = "Save file first"
            alert.informativeText = "Please save the markdown file before pasting images."
            alert.runModal()
            return nil
        }

        // Create images/ subdirectory
        let imagesDir = fileURL.deletingLastPathComponent().appendingPathComponent("images")
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)

        // Generate filename
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "image-\(formatter.string(from: Date())).png"
        let imageURL = imagesDir.appendingPathComponent(filename)

        do {
            try pngData.write(to: imageURL)
            let markdown = "![](images/\(filename))"
            textView.insertText(markdown, replacementRange: textView.selectedRange())
            return nil
        } catch {
            let alert = NSAlert()
            alert.messageText = "Failed to save image"
            alert.informativeText = error.localizedDescription
            alert.runModal()
            return nil
        }
    }

    deinit { uninstall() }
}

// MARK: - Editor Status Bar

struct EditorStatusBar: View {
    let position: CodeEditor.Position
    let text: String

    private var cursorLocation: (line: Int, column: Int) {
        let loc = position.selections.first?.location ?? 0
        let clamped = min(loc, text.count)
        let prefix = text.prefix(clamped)
        let line = prefix.filter { $0 == "\n" }.count + 1
        let lastNewline = prefix.lastIndex(of: "\n")
        let column: Int
        if let nl = lastNewline {
            column = text.distance(from: text.index(after: nl), to: text.index(text.startIndex, offsetBy: clamped)) + 1
        } else {
            column = clamped + 1
        }
        return (line, column)
    }

    private var wordCount: Int {
        text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    private var charCount: Int { text.count }

    private var readTime: Int { max(1, wordCount / 200) }

    var body: some View {
        let loc = cursorLocation
        HStack(spacing: 16) {
            Text("Ln \(loc.line), Col \(loc.column)")
            Text("Words: \(wordCount)")
            Text("Chars: \(charCount)")
            Text("~\(readTime) min read")
            Spacer()
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(Color(nsColor: .controlBackgroundColor))
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Markdown Editor View

/// SwiftUI wrapper around CodeEditorView with formatting toolbar, line numbers, minimap, and syntax highlighting.
struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    var onTopLineChange: ((Int, CGFloat) -> Void)?
    var currentFileURL: (() -> URL?)?
    @State private var messages: Set<TextLocated<Message>> = []
    @Environment(\.colorScheme) private var colorScheme
    @StateObject private var autoPairHandler = AutoPairHandler()
    @StateObject private var imagePasteHandler = ImagePasteHandler()

    var body: some View {
        VStack(spacing: 0) {
            MarkdownFormattingToolbar(text: $text, currentFileURL: currentFileURL)
            CodeEditor(
                text: $text,
                position: $position,
                messages: $messages,
                language: .none
            )
            .environment(\.codeEditorTheme, colorScheme == .dark ? Theme.defaultDark : Theme.defaultLight)
            .environment(\.codeEditorLayoutConfiguration, CodeEditor.LayoutConfiguration(
                showMinimap: true,
                wrapText: true
            ))
            .background(TopLineObserver(onTopLineChange: onTopLineChange))
            .onAppear {
                EditorFontManager.shared.applyToEditorDeferred()
                autoPairHandler.install()
                imagePasteHandler.currentFileURL = currentFileURL
                imagePasteHandler.install()
                // Apply spell check setting when editor appears
                let spellCheck = UserDefaults.standard.bool(forKey: "spellCheck")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if let window = NSApp.keyWindow, let tv = findEditorTextViewInView(window.contentView) {
                        tv.isContinuousSpellCheckingEnabled = spellCheck
                    }
                }
            }
            .onDisappear {
                autoPairHandler.uninstall()
                imagePasteHandler.uninstall()
            }
            EditorStatusBar(position: position, text: text)
        }
    }
}

/// Monitors the nearest NSScrollView's bounds changes and reports the top visible source line number.
private struct TopLineObserver: NSViewRepresentable {
    var onTopLineChange: ((Int, CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onTopLineChange = onTopLineChange
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onTopLineChange = onTopLineChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var onTopLineChange: ((Int, CGFloat) -> Void)?
        private weak var observedScrollView: NSScrollView?

        func attach(to view: NSView) {
            guard let scrollView = findCodeEditorScrollView(from: view) else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if let sv = self.findCodeEditorScrollView(from: view) {
                        self.startObserving(sv)
                    }
                }
                return
            }
            startObserving(scrollView)
        }

        private func startObserving(_ scrollView: NSScrollView) {
            guard observedScrollView == nil else { return }
            observedScrollView = scrollView
            scrollView.contentView.postsBoundsChangedNotifications = true
            NotificationCenter.default.addObserver(
                self,
                selector: #selector(boundsDidChange),
                name: NSView.boundsDidChangeNotification,
                object: scrollView.contentView
            )
        }

        private func findCodeEditorScrollView(from view: NSView) -> NSScrollView? {
            guard let window = view.window else { return nil }
            return findTextScrollView(in: window.contentView)
        }

        private func findTextScrollView(in view: NSView?) -> NSScrollView? {
            guard let view = view else { return nil }
            if let sv = view as? NSScrollView,
               sv.documentView is NSTextView || containsTextView(sv.documentView) {
                return sv
            }
            for sub in view.subviews {
                if let found = findTextScrollView(in: sub) {
                    return found
                }
            }
            return nil
        }

        private func containsTextView(_ view: NSView?) -> Bool {
            guard let view = view else { return false }
            if view is NSTextView { return true }
            return view.subviews.contains { containsTextView($0) }
        }

        @objc private func boundsDidChange(_ notification: Notification) {
            guard let scrollView = observedScrollView,
                  let textView = scrollView.documentView as? NSTextView ?? findTextViewIn(scrollView.documentView),
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            let visibleRect = scrollView.contentView.bounds
            let topY = visibleRect.origin.y + textView.textContainerInset.height
            let topPoint = NSPoint(x: textView.textContainerInset.width + 5, y: topY)

            // Find character index at top of visible rect
            let charIndex = layoutManager.characterIndex(for: topPoint, in: textContainer, fractionOfDistanceBetweenInsertionPoints: nil)

            // Count newlines to get 1-based line number
            let nsSource = textView.string as NSString
            let safeIndex = min(charIndex, nsSource.length)
            let prefix = nsSource.substring(to: safeIndex)
            let lineNumber = prefix.components(separatedBy: "\n").count // 1-based

            // Compute fractionPast: how far into the current line we've scrolled
            var fractionPast: CGFloat = 0
            let glyphIndex = layoutManager.glyphIndexForCharacter(at: min(charIndex, nsSource.length > 0 ? nsSource.length - 1 : 0))
            let lineFragmentRect = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            if lineFragmentRect.height > 0 {
                let lineTop = lineFragmentRect.origin.y + textView.textContainerInset.height
                fractionPast = max(0, min(1, (topY - lineTop) / lineFragmentRect.height))
            }

            onTopLineChange?(lineNumber, fractionPast)
        }

        private func findTextViewIn(_ view: NSView?) -> NSTextView? {
            guard let view = view else { return nil }
            if let tv = view as? NSTextView { return tv }
            for sub in view.subviews {
                if let found = findTextViewIn(sub) { return found }
            }
            return nil
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}

// MARK: - Helpers

private func findEditorTextViewInView(_ view: NSView?) -> NSTextView? {
    guard let view = view else { return nil }
    if let tv = view as? NSTextView, tv.isEditable { return tv }
    for sub in view.subviews {
        if let found = findEditorTextViewInView(sub) { return found }
    }
    return nil
}
