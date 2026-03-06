import SwiftUI
import CodeEditorView
import LanguageSupport

// MARK: - Markdown Formatting Toolbar

struct MarkdownFormattingToolbar: View {
    @Binding var text: String
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

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(colorScheme == .dark ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .windowBackgroundColor))
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
        // Find the NSTextView in the window to insert at cursor
        if let textView = findEditorTextView() {
            let selectedRange = textView.selectedRange()
            if selectedRange.length > 0,
               let selectedText = (textView.string as NSString?)?.substring(with: selectedRange) {
                // Wrap selection if the snippet has a wrap pattern
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

// MARK: - Markdown Editor View

/// SwiftUI wrapper around CodeEditorView with formatting toolbar, line numbers, minimap, and syntax highlighting.
struct MarkdownEditorView: View {
    @Binding var text: String
    @Binding var position: CodeEditor.Position
    var onScrollFractionChange: ((CGFloat) -> Void)?
    @State private var messages: Set<TextLocated<Message>> = []
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 0) {
            MarkdownFormattingToolbar(text: $text)
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
            .background(ScrollFractionObserver(onFractionChange: onScrollFractionChange))
            .onAppear {
                EditorFontManager.shared.applyToEditorDeferred()
            }
        }
    }
}

/// Monitors the nearest NSScrollView's bounds changes and reports the scroll fraction (0…1).
private struct ScrollFractionObserver: NSViewRepresentable {
    var onFractionChange: ((CGFloat) -> Void)?

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.onFractionChange = onFractionChange
        // Delay to let the CodeEditor's NSScrollView appear in the hierarchy
        DispatchQueue.main.async {
            context.coordinator.attach(to: view)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onFractionChange = onFractionChange
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    class Coordinator: NSObject {
        var onFractionChange: ((CGFloat) -> Void)?
        private weak var observedScrollView: NSScrollView?

        func attach(to view: NSView) {
            // Walk up the view hierarchy to find the CodeEditor's NSScrollView
            // [SYNC] ScrollFractionObserver.attach called, window=\(view.window != nil)")
            guard let scrollView = findCodeEditorScrollView(from: view) else {
                // [SYNC] ScrollView not found on first try, retrying in 0.5s")
                // Retry once more after a short delay (view hierarchy may not be ready)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    guard let self = self else { return }
                    if let sv = self.findCodeEditorScrollView(from: view) {
                        // [SYNC] ScrollView found on retry")
                        self.startObserving(sv)
                    } else {
                        // [SYNC] ScrollView NOT found on retry either, window=\(view.window != nil)")
                    }
                }
                return
            }
            // [SYNC] ScrollView found immediately")
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

        /// Find the NSScrollView that belongs to the CodeEditor (not a WebView).
        private func findCodeEditorScrollView(from view: NSView) -> NSScrollView? {
            // Walk up to the window, then search for scroll views that contain a text view
            guard let window = view.window else { return nil }
            return findTextScrollView(in: window.contentView)
        }

        /// Recursively find an NSScrollView whose documentView is (or contains) an NSTextView.
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
            guard let scrollView = observedScrollView else { return }
            let contentHeight = scrollView.documentView?.frame.height ?? 0
            let viewportHeight = scrollView.contentView.bounds.height
            let maxScroll = contentHeight - viewportHeight
            guard maxScroll > 0 else { return }
            let offset = scrollView.contentView.bounds.origin.y
            let fraction = min(max(offset / maxScroll, 0), 1)
            onFractionChange?(fraction)
        }

        deinit {
            NotificationCenter.default.removeObserver(self)
        }
    }
}
