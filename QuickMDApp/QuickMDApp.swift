import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit
#if canImport(FoundationModels)
import FoundationModels
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingURL: URL?
    static var pendingDirAccess: URL?  // directory with active security scope for pendingURL
    static weak var activeModel: MarkdownDocumentModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MarkdownDocumentModel.log("applicationDidFinishLaunching")
        NSWindow.allowsAutomaticWindowTabbing = true
        UserDefaults.standard.register(defaults: ["openLinksInNewTab": true, "spellCheck": true, "autoPair": true])
        // Disable state restoration so previous documents don't reopen on launch
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        // Close restored blank windows — keep only windows that have content or the one that will receive a file
        DispatchQueue.main.async {
            let windows = NSApp.windows.filter { $0.isVisible && !$0.isSheet }
            guard windows.count > 1 else { return }
            // Close blank windows (no representedURL), keeping at least one
            let blankWindows = windows.filter { $0.representedURL == nil }
            let contentWindows = windows.filter { $0.representedURL != nil }
            if !contentWindows.isEmpty {
                for w in blankWindows { w.close() }
            } else if blankWindows.count > 1 {
                for w in blankWindows.dropLast() { w.close() }
            }
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Delete saved window state so tabs don't persist across launches
        if let bundleID = Bundle.main.bundleIdentifier {
            let savedStatePath = NSHomeDirectory() + "/Library/Saved Application State/\(bundleID).savedState"
            try? FileManager.default.removeItem(atPath: savedStatePath)
        }

        // Check if any window has unsaved changes
        let hasUnsaved = NSApp.windows.contains(where: { $0.isDocumentEdited })
        if hasUnsaved {
            let alert = NSAlert()
            alert.messageText = "You have unsaved changes"
            alert.informativeText = "Do you want to save your changes before quitting?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Save All & Quit")
            alert.addButton(withTitle: "Quit Without Saving")
            alert.addButton(withTitle: "Cancel")
            let response = alert.runModal()
            switch response {
            case .alertFirstButtonReturn:
                // Save all dirty documents
                for window in NSApp.windows where window.isDocumentEdited {
                    NotificationCenter.default.post(name: .init("saveDocument"), object: window)
                }
                return .terminateNow
            case .alertSecondButtonReturn:
                return .terminateNow
            default:
                return .terminateCancel
            }
        }

        return .terminateNow
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        MarkdownDocumentModel.log("openFiles called: \(filenames)")
        if let path = filenames.first {
            let url = URL(fileURLWithPath: path)
            // Always store as pending — macOS creates a new tab for document opens,
            // so the new tab's onAppear will pick it up.
            Self.pendingURL = url
            // Fallback: if no new tab appears within 0.5s, load into active tab
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if Self.pendingURL != nil, let model = Self.activeModel {
                    model.load(from: url)
                    Self.pendingURL = nil
                }
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    @objc func showHelp() {
        if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "help" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 640),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("help")
        panel.title = "QuickMD Help"
        panel.isFloatingPanel = true
        panel.contentView = NSHostingView(rootView: HelpView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    @objc func showShortcuts() {
        if let existingWindow = NSApp.windows.first(where: { $0.identifier?.rawValue == "shortcuts" }) {
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.identifier = NSUserInterfaceItemIdentifier("shortcuts")
        panel.title = "Keyboard Shortcuts"
        panel.isFloatingPanel = true
        panel.contentView = NSHostingView(rootView: ShortcutsView())
        panel.center()
        panel.makeKeyAndOrderFront(nil)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MarkdownDocumentModel.log("open(urls:) called: \(urls.map(\.path))")
        if let url = urls.first {
            Self.pendingURL = url
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if Self.pendingURL != nil, let model = Self.activeModel {
                    model.load(from: url)
                    Self.pendingURL = nil
                }
            }
        }
    }
}

private func evalJS(_ code: String) {
    WebViewStore.shared.webView?.evaluateJavaScript(code) { _, _ in }
}

private func applyCustomCSS(_ css: String) {
    let escaped = css
        .replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: "'", with: "\\'")
        .replacingOccurrences(of: "\n", with: "\\n")
    evalJS("(function(){var el=document.getElementById('custom-theme');if(!el){el=document.createElement('style');el.id='custom-theme';document.head.appendChild(el);}el.textContent='\(escaped)';})()")
}

private func applySpellCheck(_ enabled: Bool) {
    guard let window = NSApp.keyWindow else { return }
    if let tv = findEditorTextViewIn(window.contentView) {
        tv.isContinuousSpellCheckingEnabled = enabled
    }
}

private func findEditorTextViewIn(_ view: NSView?) -> NSTextView? {
    guard let view = view else { return nil }
    if let tv = view as? NSTextView, tv.isEditable { return tv }
    for sub in view.subviews {
        if let found = findEditorTextViewIn(sub) { return found }
    }
    return nil
}

// MARK: - Pandoc Integration

enum PandocHelper {
    /// Pandoc export formats: (menu label, pandoc format name, file extension)
    static let exportFormats: [(label: String, format: String, ext: String)] = [
        ("Word (DOCX)", "docx", "docx"),
        ("EPUB", "epub", "epub"),
        ("LaTeX", "latex", "tex"),
        ("reStructuredText", "rst", "rst"),
        ("OpenDocument (ODT)", "odt", "odt"),
        ("Rich Text (RTF)", "rtf", "rtf"),
        ("Plain Text", "plain", "txt"),
        ("AsciiDoc", "asciidoc", "adoc"),
        ("MediaWiki", "mediawiki", "wiki"),
        ("Org-mode", "org", "org"),
        ("Textile", "textile", "textile"),
        ("Man Page", "man", "1"),
        ("Typst", "typst", "typ"),
    ]

    /// Pandoc import formats: (menu label, file extensions for open panel)
    static let importFormats: [(label: String, extensions: [String])] = [
        ("Word (DOCX)", ["docx"]),
        ("EPUB", ["epub"]),
        ("LaTeX", ["tex", "latex"]),
        ("reStructuredText", ["rst"]),
        ("OpenDocument (ODT)", ["odt"]),
        ("Rich Text (RTF)", ["rtf"]),
        ("HTML", ["html", "htm"]),
        ("MediaWiki", ["wiki"]),
        ("Org-mode", ["org"]),
        ("Textile", ["textile"]),
        ("OPML", ["opml"]),
        ("DocBook", ["xml", "dbk"]),
        ("Typst", ["typ"]),
    ]

    static func pandocPath() -> String? {
        let candidates = [
            "/opt/homebrew/bin/pandoc",
            "/usr/local/bin/pandoc",
            "/usr/bin/pandoc",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        // Try `which pandoc` as fallback
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        proc.arguments = ["pandoc"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        try? proc.run()
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.isEmpty ? nil : path
    }

    static func showInstallAlert() {
        let alert = NSAlert()
        alert.messageText = "Pandoc Not Found"
        alert.informativeText = """
        Pandoc is required for format conversion. Install it with Homebrew:

            brew install pandoc

        Or download from: https://pandoc.org/installing.html
        """
        alert.addButton(withTitle: "Copy Install Command")
        alert.addButton(withTitle: "Open Download Page")
        alert.addButton(withTitle: "Cancel")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString("brew install pandoc", forType: .string)
        } else if response == .alertSecondButtonReturn {
            NSWorkspace.shared.open(URL(string: "https://pandoc.org/installing.html")!)
        }
    }

    /// Convert a web URL to markdown: let pandoc fetch the URL, then clean the resulting markdown.
    @discardableResult
    static func convertURL(_ urlString: String, output: URL) -> (success: Bool, error: String) {
        guard let pandoc = pandocPath() else {
            return (false, "Pandoc not found")
        }
        guard URL(string: urlString) != nil else {
            return (false, "Invalid URL")
        }

        // 1. Let pandoc fetch and convert (it handles JS-rendered pages better than URLSession)
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".md")
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pandoc)
        proc.arguments = [
            "-f", "html-native_divs-native_spans",
            "-t", "gfm-raw_html",
            "--wrap=none",
            "--strip-comments",
            "--markdown-headings=atx",
            urlString,
            "-o", tempFile.path
        ]
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }

        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let errStr = String(data: errData, encoding: .utf8) ?? ""
        guard proc.terminationStatus == 0 else {
            return (false, errStr.isEmpty ? "Pandoc exited with code \(proc.terminationStatus)" : errStr)
        }

        // 2. Read the raw markdown and clean it
        guard var markdown = try? String(contentsOf: tempFile, encoding: .utf8) else {
            return (false, "Failed to read pandoc output")
        }

        markdown = cleanMarkdown(markdown)

        // 3. Write cleaned markdown to final output
        do {
            try markdown.write(to: output, atomically: true, encoding: .utf8)
            return (true, "")
        } catch {
            return (false, "Failed to write output: \(error.localizedDescription)")
        }
    }

    /// Clean pandoc-generated markdown by removing noise artifacts.
    private static func cleanMarkdown(_ md: String) -> String {
        var lines = md.components(separatedBy: "\n")

        // Remove lines that look like CSS class dumps: {.class-name .another-class}
        lines = lines.filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("{.") && trimmed.hasSuffix("}") && !trimmed.contains("](") { return false }
            if trimmed.hasPrefix("{") && trimmed.hasSuffix("}") {
                let inner = trimmed.dropFirst().dropLast()
                let tokens = inner.split(separator: " ")
                let cssLike = tokens.filter { $0.hasPrefix(".") || $0.hasPrefix("#") || $0.contains(":") }
                if tokens.count > 2 && cssLike.count > tokens.count / 2 { return false }
            }
            return true
        }

        var result = lines.joined(separator: "\n")

        // Remove inline bracketed class/id attributes: {.class-name ...} or {#id}
        if let bracketAttrs = try? NSRegularExpression(pattern: #"\{[.#][^}]*\}"#, options: []) {
            result = bracketAttrs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove images with data: URIs — inline style: ![alt](data:...)
        if let dataImgs = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\(data:[^)]+\)"#, options: []) {
            result = dataImgs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove images with data: URIs — reference style: ![][28] and [28]: data:...
        if let dataRefs = try? NSRegularExpression(pattern: #"^\s*\[\d+\]:\s*data:[^\n]+$"#, options: [.anchorsMatchLines]) {
            result = dataRefs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove reference-style image/link refs: ![][N] or [][N] or [text][N] where ref was removed
        if let refImgs = try? NSRegularExpression(pattern: #"!\[[^\]]*\]\[\d+\]"#, options: []) {
            result = refImgs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove empty reference links: [​][N] (zero-width space or whitespace only)
        if let emptyRefs = try? NSRegularExpression(pattern: #"\[[\u{200B}\s]*\]\[\d+\]"#, options: []) {
            result = emptyRefs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }
        // Remove orphaned reference definitions pointing to fragment anchors: [N]: #something
        if let fragRefs = try? NSRegularExpression(pattern: #"^\s*\[\d+\]:\s*#[^\n]*$"#, options: [.anchorsMatchLines]) {
            result = fragRefs.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove ::: div markers (pandoc fenced divs)
        if let divMarkers = try? NSRegularExpression(pattern: #"^:{3,}.*$"#, options: [.anchorsMatchLines]) {
            result = divMarkers.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove empty anchor links like [​](#some-id) (zero-width space + fragment link)
        if let emptyAnchors = try? NSRegularExpression(pattern: #"\[[\u{200B}\s]*\]\(#[^)]*\)"#, options: []) {
            result = emptyAnchors.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove "Copy page" / "Copy" standalone lines (common in documentation sites)
        if let copyLines = try? NSRegularExpression(pattern: #"^Copy( page)?$"#, options: [.anchorsMatchLines]) {
            result = copyLines.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove empty headings (## with only whitespace after)
        if let emptyHeadings = try? NSRegularExpression(pattern: #"^#{1,6}\s*$"#, options: [.anchorsMatchLines]) {
            result = emptyHeadings.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
        }

        // Remove common page feedback/navigation noise at end
        let noisePatterns = [
            #"^Was this page helpful\?.*$"#,
            #"^(Yes|No)$"#,
            #"^(Previous|Next)$"#,
            #"^Skip to main content$"#,
            #"^Search\.{3}$"#,
            #"^Navigation$"#,
        ]
        for pattern in noisePatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]) {
                result = regex.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "")
            }
        }

        // Try to find and keep content from first heading onward (skip nav/sidebar preamble)
        if let firstHeading = result.range(of: #"^#{1,6}\s"#, options: .regularExpression) {
            result = String(result[firstHeading.lowerBound...])
        }

        // Tighten loose lists: remove blank lines between list items
        // Matches: list item, blank line, list item (-, *, +, or 1.)
        if let looseList = try? NSRegularExpression(pattern: #"(^[ \t]*[-*+][ \t].+)\n\n([ \t]*[-*+][ \t])"#, options: [.anchorsMatchLines]) {
            // Run multiple passes since each replacement only catches adjacent pairs
            for _ in 0..<5 {
                result = looseList.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1\n$2")
            }
        }
        if let looseNumList = try? NSRegularExpression(pattern: #"(^[ \t]*\d+\.[ \t].+)\n\n([ \t]*\d+\.[ \t])"#, options: [.anchorsMatchLines]) {
            for _ in 0..<5 {
                result = looseNumList.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "$1\n$2")
            }
        }

        // Collapse 3+ consecutive blank lines to 1
        if let multiBlank = try? NSRegularExpression(pattern: #"\n{3,}"#, options: []) {
            result = multiBlank.stringByReplacingMatches(in: result, range: NSRange(result.startIndex..., in: result), withTemplate: "\n\n")
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Run pandoc to convert `input` to `output` with the given format.
    @discardableResult
    static func convert(input: URL, output: URL, to format: String? = nil, from inputFormat: String? = nil) -> (success: Bool, error: String) {
        guard let pandoc = pandocPath() else {
            return (false, "Pandoc not found")
        }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pandoc)
        var args = [input.path, "-o", output.path, "--standalone"]
        if let format = format { args += ["-t", format] }
        if let inputFormat = inputFormat { args += ["-f", inputFormat] }
        proc.arguments = args
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        do {
            try proc.run()
            proc.waitUntilExit()
            let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            let errStr = String(data: errData, encoding: .utf8) ?? ""
            if proc.terminationStatus == 0 {
                return (true, "")
            } else {
                return (false, errStr.isEmpty ? "Pandoc exited with code \(proc.terminationStatus)" : errStr)
            }
        } catch {
            return (false, error.localizedDescription)
        }
    }
}

@main
struct QuickMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("theme") private var theme = "system"
    @AppStorage("lineNumbers") private var lineNumbers = false
    @AppStorage("wordWrap") private var wordWrap = false
    @AppStorage("spellCheck") private var spellCheck = true
    @AppStorage("autoPair") private var autoPair = true
    @FocusedValue(\.documentModel) private var activeModel
    @FocusedValue(\.showEditor) private var showEditor
    @FocusedValue(\.showSearchBar) private var showSearchBar
    @FocusedValue(\.showSidebar) private var showSidebar
    @FocusedValue(\.activePanel) private var activePanel

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 400, idealWidth: 900, minHeight: 300, idealHeight: 620)
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .newItem) {
                Button("Open\u{2026}") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [
                        UTType.plainText,
                        UTType(filenameExtension: "md") ?? .plainText,
                        UTType.json,
                        UTType.yaml,
                        UTType.xml,
                        UTType.html,
                        UTType.sourceCode,
                    ]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        activeModel?.load(from: url)
                    }
                }
                .keyboardShortcut("o")

                // Recent Files submenu
                Menu("Open Recent") {
                    ForEach(NSDocumentController.shared.recentDocumentURLs, id: \.self) { url in
                        Button(url.lastPathComponent) {
                            activeModel?.load(from: url)
                        }
                    }
                    Divider()
                    Button("Clear Menu") {
                        NSDocumentController.shared.clearRecentDocuments(nil)
                    }
                }

                Divider()

                Button("Save") {
                    guard let model = activeModel ?? AppDelegate.activeModel,
                          let url = model.currentURL else { return }
                    try? model.rawContent.write(to: url, atomically: true, encoding: .utf8)
                    model.markClean()
                    if let window = WebViewStore.shared.webView?.window {
                        window.isDocumentEdited = false
                    }
                    ContentView.pushIncrementalUpdate(model: model)
                }
                .keyboardShortcut("s")

                Button("Export as PDF\u{2026}") {
                    guard let model = activeModel, let inputURL = model.currentURL else { return }
                    guard PandocHelper.pandocPath() != nil else {
                        PandocHelper.showInstallAlert()
                        return
                    }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType.pdf]
                    let baseName = inputURL.deletingPathExtension().lastPathComponent
                    panel.nameFieldStringValue = "\(baseName).pdf"
                    if panel.runModal() == .OK, let outputURL = panel.url {
                        let result = PandocHelper.convert(input: inputURL, output: outputURL)
                        if !result.success {
                            let alert = NSAlert()
                            alert.messageText = "Export Failed"
                            alert.informativeText = result.error
                            alert.runModal()
                        }
                    }
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])

                Button("Export as HTML\u{2026}") {
                    guard let model = activeModel, let htmlContent = model.html else { return }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [.html]
                    let baseName = model.fileName ?? "document"
                    let ext = URL(fileURLWithPath: baseName).pathExtension
                    panel.nameFieldStringValue = ext.isEmpty ? baseName + ".html" : baseName.replacingOccurrences(of: ".\(ext)", with: ".html")
                    if panel.runModal() == .OK, let url = panel.url {
                        do {
                            try htmlContent.write(to: url, atomically: true, encoding: .utf8)
                        } catch {
                            let alert = NSAlert()
                            alert.messageText = "Failed to save HTML"
                            alert.informativeText = error.localizedDescription
                            alert.runModal()
                        }
                    }
                }
                .keyboardShortcut("h", modifiers: [.command, .shift])

                Divider()

                Button("Print\u{2026}") {
                    guard let webView = WebViewStore.shared.webView else { return }
                    let printInfo = NSPrintInfo.shared
                    printInfo.topMargin = 36
                    printInfo.bottomMargin = 36
                    printInfo.leftMargin = 36
                    printInfo.rightMargin = 36
                    let printOp = webView.printOperation(with: printInfo)
                    printOp.showsPrintPanel = true
                    printOp.showsProgressPanel = true
                    printOp.run()
                }
                .keyboardShortcut("p")

                Divider()

                Menu("Export with Pandoc") {
                    ForEach(PandocHelper.exportFormats, id: \.format) { fmt in
                        Button(fmt.label) {
                            guard let model = activeModel, let inputURL = model.currentURL else { return }
                            guard PandocHelper.pandocPath() != nil else {
                                PandocHelper.showInstallAlert()
                                return
                            }
                            let panel = NSSavePanel()
                            if let uttype = UTType(filenameExtension: fmt.ext) {
                                panel.allowedContentTypes = [uttype]
                            }
                            let baseName = inputURL.deletingPathExtension().lastPathComponent
                            panel.nameFieldStringValue = "\(baseName).\(fmt.ext)"
                            if panel.runModal() == .OK, let outputURL = panel.url {
                                let result = PandocHelper.convert(input: inputURL, output: outputURL, to: fmt.format)
                                if !result.success {
                                    let alert = NSAlert()
                                    alert.messageText = "Export Failed"
                                    alert.informativeText = result.error
                                    alert.runModal()
                                }
                            }
                        }
                    }
                }

                Menu("Import to Markdown") {
                    Button("From URL\u{2026}") {
                        guard PandocHelper.pandocPath() != nil else {
                            PandocHelper.showInstallAlert()
                            return
                        }
                        let alert = NSAlert()
                        alert.messageText = "Import from URL"
                        alert.informativeText = "Enter a web page URL to convert to Markdown:"
                        alert.addButton(withTitle: "Import")
                        alert.addButton(withTitle: "Cancel")
                        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 350, height: 24))
                        textField.placeholderString = "https://example.com/page"
                        alert.accessoryView = textField
                        alert.window.initialFirstResponder = textField
                        guard alert.runModal() == .alertFirstButtonReturn else { return }
                        let urlString = textField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard let url = URL(string: urlString), url.scheme != nil else {
                            let err = NSAlert()
                            err.messageText = "Invalid URL"
                            err.informativeText = "Please enter a valid URL starting with http:// or https://"
                            err.runModal()
                            return
                        }
                        // Derive filename from URL host+path
                        let baseName = (url.host ?? "page").replacingOccurrences(of: ".", with: "-")
                        let savePanel = NSSavePanel()
                        savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
                        savePanel.nameFieldStringValue = "\(baseName).md"
                        guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }

                        let result = PandocHelper.convertURL(urlString, output: outputURL)
                        if result.success {
                            activeModel?.load(from: outputURL)
                            #if canImport(FoundationModels)
                            if #available(macOS 26.0, *), AIHelper.isAvailable {
                                let aiAlert = NSAlert()
                                aiAlert.messageText = "Clean with Apple Intelligence?"
                                aiAlert.informativeText = "Would you like AI to clean up the imported markdown?"
                                aiAlert.addButton(withTitle: "Clean Up")
                                aiAlert.addButton(withTitle: "Skip")
                                if aiAlert.runModal() == .alertFirstButtonReturn {
                                    if let model = activeModel {
                                        AIProgressHUD.shared.show("Cleaning up import\u{2026}")
                                        Task { @MainActor in
                                            defer { AIProgressHUD.shared.dismiss() }
                                            let cleaned = await AIHelper.cleanupImportedMarkdown(model.rawContent)
                                            model.setContent(cleaned, actionName: "AI Clean Up")
                                        }
                                    }
                                }
                            }
                            #endif
                        } else {
                            let err = NSAlert()
                            err.messageText = "Import Failed"
                            err.informativeText = result.error
                            err.runModal()
                        }
                    }

                    Divider()

                    ForEach(PandocHelper.importFormats, id: \.label) { fmt in
                        Button("From \(fmt.label)\u{2026}") {
                            guard PandocHelper.pandocPath() != nil else {
                                PandocHelper.showInstallAlert()
                                return
                            }
                            let openPanel = NSOpenPanel()
                            openPanel.allowedContentTypes = fmt.extensions.compactMap { UTType(filenameExtension: $0) }
                            openPanel.allowsMultipleSelection = false
                            guard openPanel.runModal() == .OK, let inputURL = openPanel.url else { return }

                            let baseName = inputURL.deletingPathExtension().lastPathComponent
                            let savePanel = NSSavePanel()
                            savePanel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
                            savePanel.nameFieldStringValue = "\(baseName).md"
                            guard savePanel.runModal() == .OK, let outputURL = savePanel.url else { return }

                            let result = PandocHelper.convert(input: inputURL, output: outputURL, to: "markdown")
                            if result.success {
                                activeModel?.load(from: outputURL)
                            } else {
                                let alert = NSAlert()
                                alert.messageText = "Import Failed"
                                alert.informativeText = result.error
                                alert.runModal()
                            }
                        }
                    }
                }
            }
            CommandMenu("Theme") {
                Button("System (Default)") {
                    theme = "system"
                    evalJS("if(window.__setTheme) __setTheme('system')")
                    evalJS("document.getElementById('custom-theme')?.remove()")
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("Force Light") {
                    theme = "light"
                    evalJS("if(window.__setTheme) __setTheme('light')")
                    evalJS("document.getElementById('custom-theme')?.remove()")
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Force Dark") {
                    theme = "dark"
                    evalJS("if(window.__setTheme) __setTheme('dark')")
                    evalJS("document.getElementById('custom-theme')?.remove()")
                }
                .keyboardShortcut("d", modifiers: [.command, .option])

                Divider()

                // Built-in color themes
                ForEach(MarkdownDocumentModel.builtInThemes, id: \.name) { builtIn in
                    Button(builtIn.name) {
                        theme = "builtin:\(builtIn.name)"
                        applyCustomCSS(builtIn.css)
                    }
                }

                let customThemes = MarkdownDocumentModel.availableThemes()
                if !customThemes.isEmpty {
                    Divider()
                    ForEach(customThemes, id: \.self) { name in
                        Button(name) {
                            theme = "custom:\(name)"
                            let css = MarkdownDocumentModel.customCSS(for: name)
                            applyCustomCSS(css)
                        }
                    }
                }

                Divider()

                Button("Custom CSS\u{2026}") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.init(filenameExtension: "css") ?? .plainText]
                    panel.allowsMultipleSelection = false
                    if panel.runModal() == .OK, let url = panel.url {
                        let dest = MarkdownDocumentModel.themesDirectory.appendingPathComponent(url.lastPathComponent)
                        try? FileManager.default.copyItem(at: url, to: dest)
                        let name = url.deletingPathExtension().lastPathComponent
                        theme = "custom:\(name)"
                        let css = MarkdownDocumentModel.customCSS(for: name)
                        applyCustomCSS(css)
                    }
                }

                Button("Open Themes Folder") {
                    NSWorkspace.shared.open(MarkdownDocumentModel.themesDirectory)
                }
            }
            CommandGroup(after: .toolbar) {
                Button("Back") {
                    let openInNewTab = UserDefaults.standard.bool(forKey: "openLinksInNewTab")
                    if openInNewTab {
                        WebViewStore.shared.goBackTab()
                    } else {
                        activeModel?.goBack()
                    }
                }
                .keyboardShortcut(.leftArrow, modifiers: [.command, .shift])
                Button("Forward") {
                    let openInNewTab = UserDefaults.standard.bool(forKey: "openLinksInNewTab")
                    if openInNewTab {
                        WebViewStore.shared.goForwardTab()
                    } else {
                        activeModel?.goForward()
                    }
                }
                .keyboardShortcut(.rightArrow, modifiers: [.command, .shift])
                Divider()
                Button("Zoom In") {
                    WebViewStore.shared.webView?.zoomIn()
                }
                .keyboardShortcut("=")
                Button("Zoom Out") {
                    WebViewStore.shared.webView?.zoomOut()
                }
                .keyboardShortcut("-")
                Button("Actual Size") {
                    WebViewStore.shared.webView?.zoomReset()
                }
                .keyboardShortcut("0")
                Divider()
                Button("Toggle Sidebar") {
                    showSidebar?.wrappedValue.toggle()
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
                Button("Show Comments") {
                    showSidebar?.wrappedValue = true
                    activePanel?.wrappedValue = .comments
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                Button("Move Sidebar to Other Side") {
                    if let binding = showSidebar {
                        // Toggle position
                        let current = UserDefaults.standard.string(forKey: "sidebarPosition") ?? "leading"
                        UserDefaults.standard.set(current == "leading" ? "trailing" : "leading", forKey: "sidebarPosition")
                        if !binding.wrappedValue { binding.wrappedValue = true }
                    }
                }
            }
            CommandMenu("Tools") {
                Button("Find\u{2026}") {
                    if let binding = showSearchBar {
                        binding.wrappedValue.toggle()
                    } else {
                        evalJS("if(window.__findOpen) __findOpen()")
                    }
                }
                .keyboardShortcut("f")
                Divider()
                Toggle("Line Numbers", isOn: Binding(
                    get: { lineNumbers },
                    set: { newValue in
                        lineNumbers = newValue
                        evalJS("if(window.__toggleLineNumbers) __toggleLineNumbers()")
                    }
                ))
                .keyboardShortcut("l")
                Toggle("Word Wrap", isOn: Binding(
                    get: { wordWrap },
                    set: { newValue in
                        wordWrap = newValue
                        evalJS("if(window.__toggleWordWrap) __toggleWordWrap()")
                    }
                ))
                .keyboardShortcut("w", modifiers: [.command, .option])
                Toggle("Spell Check", isOn: Binding(
                    get: { spellCheck },
                    set: { newValue in
                        spellCheck = newValue
                        applySpellCheck(newValue)
                    }
                ))
                Toggle("Auto-Pair Brackets", isOn: $autoPair)
                Button("Jump to Line\u{2026}") {
                    evalJS("if(window.__jumpToLine) __jumpToLine()")
                }
                .keyboardShortcut("g")
                Divider()
                Button("Presentation Mode") {
                    evalJS("if(window.__startPresentation) __startPresentation()")
                }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                Divider()
                Toggle("Auto-Reload", isOn: Binding(
                    get: { activeModel?.autoReload ?? false },
                    set: { newValue in
                        if let model = activeModel {
                            if newValue, let url = model.currentURL {
                                model.startWatching(url: url)
                            } else {
                                model.stopWatching()
                            }
                        }
                    }
                ))
                .keyboardShortcut("a", modifiers: [.command, .shift])
                Divider()
                Button("Read Aloud") {
                    evalJS("if(window.__speak){if(typeof speechSynthesis!=='undefined'&&speechSynthesis.speaking&&!speechSynthesis.paused)__speak.pause();else __speak.start();}")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Stop Reading") {
                    evalJS("if(window.__speak) __speak.stop()")
                }
                Divider()
                Button("Editor Font\u{2026}") {
                    EditorFontManager.shared.showFontPanel()
                }
                .keyboardShortcut("t", modifiers: [.command])
                Divider()
                Button("Add Comment\u{2026}") {
                    NotificationCenter.default.post(name: .addCommentAction, object: nil)
                }
                .keyboardShortcut("k", modifiers: [.command])
                Button("Remove Comment") {
                    NotificationCenter.default.post(name: .removeCommentAction, object: nil)
                }
                Button("Next Comment") {
                    evalJS("if(window.__nextComment) __nextComment()")
                }
                .keyboardShortcut("j", modifiers: [.command, .option])
                Button("Previous Comment") {
                    evalJS("if(window.__prevComment) __prevComment()")
                }
                .keyboardShortcut("k", modifiers: [.command, .option])
                Divider()
                Toggle("Show Editor", isOn: Binding(
                    get: { showEditor?.wrappedValue ?? false },
                    set: { showEditor?.wrappedValue = $0 }
                ))
                .keyboardShortcut("e", modifiers: .command)
            }
            aiMenu()
            CommandGroup(replacing: .help) {
                Button("QuickMD Help") {
                    NSApp.sendAction(#selector(AppDelegate.showHelp), to: nil, from: nil)
                }
                .keyboardShortcut("?", modifiers: [.command])
                Button("Keyboard Shortcuts") {
                    NSApp.sendAction(#selector(AppDelegate.showShortcuts), to: nil, from: nil)
                }
                .keyboardShortcut("/", modifiers: [.command])
            }
        }

        Settings {
            SettingsView()
        }
    }
}

// MARK: - AI Menu

extension QuickMDApp {
    @CommandsBuilder
    func aiMenu() -> some Commands {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            CommandMenu("AI") {
                aiMenuContent()
            }
        }
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    @ViewBuilder
    private func aiMenuContent() -> some View {
        let isReady = AIHelper.isAvailable

        Section {
            ForEach(AIHelper.Action.allCases, id: \.rawValue) { action in
                Button(action.rawValue) {
                    aiTransform(action: action)
                }
                .disabled(!isReady)
            }
        }

        Divider()

        Button("Generate Frontmatter") {
            aiGenerateFrontmatter()
        }
        .disabled(!isReady)

        Button("Clean Up with AI") {
            aiCleanupDocument()
        }
        .disabled(!isReady)

        if !isReady {
            Divider()
            Text("Apple Intelligence not available")
                .foregroundStyle(.secondary)
        }
    }

    @available(macOS 26.0, *)
    private func aiTransform(action: AIHelper.Action) {
        guard let model = activeModel ?? AppDelegate.activeModel else { return }
        let selectedText = getSelectedEditorText()
        let selectionRange = getEditorSelectionRange()
        let textToTransform = selectedText ?? model.rawContent
        guard !textToTransform.isEmpty else { return }

        AIProgressHUD.shared.show()
        Task { @MainActor in
            let originalContent = model.rawContent
            let result = await AIHelper.transform(textToTransform, action: action)
            AIProgressHUD.shared.dismiss()
            let newContent: String
            var replacedRange: NSRange?
            if let selected = selectedText, let nsRange = selectionRange {
                let nsOriginal = originalContent as NSString
                newContent = nsOriginal.replacingCharacters(in: nsRange, with: result)
                replacedRange = NSRange(location: nsRange.location, length: (result as NSString).length)
            } else {
                newContent = result
            }
            model.setContent(newContent, actionName: action.rawValue)

            // Select the replaced text so user can see what changed
            if let range = replacedRange {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    setEditorSelection(range)
                }
            }

            // Show accept/reject bar
            AIReviewBar.shared.show(onAccept: {
                // Already applied — just dismiss
            }, onReject: {
                model.undoManager.undo()
            })
        }
    }

    @available(macOS 26.0, *)
    private func aiGenerateFrontmatter() {
        guard let model = activeModel ?? AppDelegate.activeModel, !model.rawContent.isEmpty else { return }
        guard !model.rawContent.hasPrefix("---\n") else {
            let alert = NSAlert()
            alert.messageText = "Frontmatter Exists"
            alert.informativeText = "This document already has frontmatter. Remove it first to regenerate."
            alert.runModal()
            return
        }

        AIProgressHUD.shared.show("Generating frontmatter\u{2026}")
        Task { @MainActor in
            do {
                let frontmatter = try await AIHelper.generateFrontmatter(for: model.rawContent)
                AIProgressHUD.shared.dismiss()
                model.setContent(frontmatter + "\n\n" + model.rawContent, actionName: "Generate Frontmatter")
                AIReviewBar.shared.show(onAccept: {}, onReject: { model.undoManager.undo() })
            } catch {
                AIProgressHUD.shared.dismiss()
                let alert = NSAlert()
                alert.messageText = "AI Error"
                alert.informativeText = error.localizedDescription
                alert.runModal()
            }
        }
    }

    @available(macOS 26.0, *)
    private func aiCleanupDocument() {
        guard let model = activeModel ?? AppDelegate.activeModel, !model.rawContent.isEmpty else { return }

        AIProgressHUD.shared.show("Cleaning up document\u{2026}")
        Task { @MainActor in
            let cleaned = await AIHelper.cleanupImportedMarkdown(model.rawContent)
            AIProgressHUD.shared.dismiss()
            model.setContent(cleaned, actionName: "AI Clean Up")
            AIReviewBar.shared.show(onAccept: {}, onReject: { model.undoManager.undo() })
        }
    }
    #endif
}

// MARK: - AI Progress HUD

private class AIProgressHUD {
    static let shared = AIProgressHUD()
    private var panel: NSPanel?

    func show(_ message: String = "Apple Intelligence is thinking\u{2026}") {
        guard panel == nil else { return }
        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 70),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.backgroundColor = .windowBackgroundColor
        p.level = .floating

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false

        let spinner = NSProgressIndicator()
        spinner.style = .spinning
        spinner.controlSize = .small
        spinner.startAnimation(nil)
        spinner.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13)
        label.translatesAutoresizingMaskIntoConstraints = false

        stack.addArrangedSubview(spinner)
        stack.addArrangedSubview(label)

        p.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: p.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: p.contentView!.centerYAnchor),
        ])

        p.center()
        p.makeKeyAndOrderFront(nil)
        panel = p
    }

    func dismiss() {
        panel?.close()
        panel = nil
    }
}

// MARK: - AI Review Bar (Accept/Reject)

private class AIReviewBar {
    static let shared = AIReviewBar()
    private var panel: NSPanel?
    private var onReject: (() -> Void)?
    private var monitor: Any?

    func show(onAccept: @escaping () -> Void, onReject: @escaping () -> Void) {
        dismiss()
        self.onReject = onReject

        let p = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 44),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.isFloatingPanel = true
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isMovableByWindowBackground = true
        p.backgroundColor = .windowBackgroundColor
        p.level = .floating

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(labelWithString: "AI changes applied")
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor

        let rejectBtn = NSButton(title: "Reject (Esc)", target: nil, action: nil)
        rejectBtn.bezelStyle = .rounded
        rejectBtn.target = self
        rejectBtn.action = #selector(rejectAction)

        let acceptBtn = NSButton(title: "Accept (\u{21A9})", target: nil, action: nil)
        acceptBtn.bezelStyle = .rounded
        acceptBtn.hasDestructiveAction = false
        acceptBtn.keyEquivalent = "\r"
        acceptBtn.target = self
        acceptBtn.action = #selector(acceptAction)

        stack.addArrangedSubview(label)
        stack.addArrangedSubview(rejectBtn)
        stack.addArrangedSubview(acceptBtn)

        p.contentView?.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: p.contentView!.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: p.contentView!.centerYAnchor),
        ])

        // Position near top of main window
        if let mainWindow = NSApp.keyWindow {
            let mainFrame = mainWindow.frame
            p.setFrameOrigin(NSPoint(
                x: mainFrame.midX - 190,
                y: mainFrame.maxY - 80
            ))
        } else {
            p.center()
        }

        p.makeKeyAndOrderFront(nil)
        panel = p

        // Monitor Escape key globally
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 { // Escape
                self?.rejectAction()
                return nil
            }
            return event
        }
    }

    @objc private func acceptAction() {
        dismiss()
    }

    @objc private func rejectAction() {
        onReject?()
        dismiss()
    }

    func dismiss() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        panel?.close()
        panel = nil
        onReject = nil
    }
}

private func getSelectedEditorText() -> String? {
    guard let window = NSApp.keyWindow else { return nil }
    if let tv = findEditorTextViewIn(window.contentView),
       tv.selectedRange().length > 0,
       let text = tv.string as NSString? {
        return text.substring(with: tv.selectedRange())
    }
    return nil
}

private func getEditorSelectionRange() -> NSRange? {
    guard let window = NSApp.keyWindow,
          let tv = findEditorTextViewIn(window.contentView),
          tv.selectedRange().length > 0 else { return nil }
    return tv.selectedRange()
}

private func setEditorSelection(_ range: NSRange) {
    guard let window = NSApp.keyWindow,
          let tv = findEditorTextViewIn(window.contentView) else { return }
    tv.setSelectedRange(range)
    tv.scrollRangeToVisible(range)
}

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("lineNumbers") private var lineNumbers = false
    @AppStorage("fontSize") private var fontSize = 16
    @AppStorage("openLinksInNewTab") private var openLinksInNewTab = true
    @AppStorage("spellCheck") private var spellCheck = true
    @AppStorage("autoPair") private var autoPair = true

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $theme) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                HStack {
                    Text("Default font size")
                    Stepper("\(fontSize)px", value: $fontSize, in: 10...32, step: 2)
                }
            }

            Section("Editor") {
                Toggle("Show line numbers by default", isOn: $lineNumbers)
                Toggle("Spell Check", isOn: $spellCheck)
                Toggle("Auto-Pair Brackets", isOn: $autoPair)

                HStack {
                    Text("Editor Font")
                    Spacer()
                    Text(UserDefaults.standard.string(forKey: "editorFontName") ?? "System Mono")
                        .foregroundStyle(.secondary)
                    Text("\(Int(UserDefaults.standard.double(forKey: "editorFontSize").rounded()))pt")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Behavior") {
                Toggle("Open file links in new tab", isOn: $openLinksInNewTab)
            }

            Section {
                Text("QuickMD handles Markdown, JSON, YAML, and source code files. File type associations are configured at build time via Info.plist.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } header: {
                Text("File Associations")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .navigationTitle("Settings")
    }
}

// MARK: - Help View

struct HelpView: View {
    private struct HelpSection: Identifiable {
        let id = UUID()
        let title: String
        let content: String
    }

    private let sections: [HelpSection] = [
        HelpSection(title: "Getting Started", content: """
            QuickMD is a Markdown previewer and editor for macOS. It renders Markdown, JSON, YAML, and 190+ source code languages with syntax highlighting.

            Open a file: File > Open (\u{2318}O), drag and drop a file onto the window, or select a file in Finder and press Space for Quick Look.

            The editor: Toggle with Tools > Show Editor (\u{2318}E) or double-click any word in the preview to jump to it in the editor. Changes are live-previewed as you type.
            """),
        HelpSection(title: "Editor", content: """
            The split editor shows a formatting toolbar with buttons for headings, bold, italic, strikethrough, code, links, images, code blocks, quotes, tables, lists, task lists, horizontal rules, and GitHub Alerts.

            Features:
            \u{2022} Live preview updates as you type (0.3s debounce)
            \u{2022} Bidirectional scroll sync between editor and preview
            \u{2022} Double-click a word in the preview to jump to it in the editor
            \u{2022} Spell check (Tools > Spell Check)
            \u{2022} Auto-pair brackets and quotes (Tools > Auto-Pair Brackets)
            \u{2022} Paste images from clipboard (auto-saved next to the file)
            \u{2022} Status bar shows line, column, word count, character count, and estimated read time
            \u{2022} Customizable font (Tools > Editor Font, \u{2318}T)
            \u{2022} Line numbers and word wrap toggles
            """),
        HelpSection(title: "Preview Features", content: """
            \u{2022} Mermaid diagrams render automatically in fenced code blocks
            \u{2022} Syntax highlighting for 190+ languages via highlight.js
            \u{2022} JSON and YAML are pretty-printed before highlighting
            \u{2022} Task list checkboxes are interactive (click to toggle)
            \u{2022} File links open in the same tab or a new tab (configurable in Settings)
            \u{2022} Table of contents generated from headings
            \u{2022} Back/Forward navigation (\u{2318}[ / \u{2318}])
            \u{2022} Zoom In/Out (\u{2318}= / \u{2318}-)
            \u{2022} Find in preview and editor (\u{2318}F)
            \u{2022} Presentation mode (\u{21E7}\u{2318}P) — uses --- or headings as slide breaks
            \u{2022} Read Aloud (\u{21E7}\u{2318}R) — text-to-speech for the document
            """),
        HelpSection(title: "Themes", content: """
            Theme > System / Light / Dark controls the base appearance. Built-in color themes include Dracula, Solarized Light, Solarized Dark, Nord, and Sepia.

            Custom CSS themes: Theme > Custom CSS to import a .css file, or place .css files in the themes folder (Theme > Open Themes Folder). Custom themes appear in the Theme menu automatically.
            """),
        HelpSection(title: "Export & Import", content: """
            Built-in export:
            \u{2022} Export as PDF (\u{21E7}\u{2318}E)
            \u{2022} Export as HTML (\u{21E7}\u{2318}H)

            Pandoc export (requires pandoc installed):
            \u{2022} Word (DOCX), EPUB, LaTeX, reStructuredText, ODT, RTF, Plain Text, AsciiDoc, MediaWiki, Org-mode, Textile, Man Page, Typst

            Pandoc import:
            \u{2022} From URL — converts web pages to Markdown
            \u{2022} From file — Word, EPUB, LaTeX, HTML, ODT, RTF, and more

            Install pandoc: brew install pandoc
            """),
        HelpSection(title: "Apple Intelligence", content: """
            The AI menu (macOS 26+) provides on-device text transformations powered by Apple Intelligence. All processing happens locally on your Mac.

            Text actions (works on selected text or full document):
            \u{2022} Fix Markdown — corrects syntax errors, formatting, and structure
            \u{2022} Improve Writing — enhances clarity and flow
            \u{2022} Fix Grammar & Spelling
            \u{2022} Make Concise / Expand & Elaborate
            \u{2022} Simplify Language
            \u{2022} Professional / Casual Tone
            \u{2022} Summarize / Convert to Bullet Points

            Other AI features:
            \u{2022} Generate Frontmatter — auto-generates YAML title, description, and tags
            \u{2022} Clean Up with AI — removes noise from imported web content

            After any AI action, a review bar appears:
            \u{2022} Accept (Return) — keep the changes
            \u{2022} Reject (Escape) — revert to original text

            You can also undo AI changes with Edit > Undo (\u{2318}Z).
            """),
        HelpSection(title: "Auto-Reload", content: """
            When a file is opened, QuickMD watches it for changes and automatically reloads the preview. This works great with external editors — edit in your favorite editor, preview in QuickMD.

            Toggle with Tools > Auto-Reload (\u{21E7}\u{2318}A). Scroll position is preserved across reloads.
            """),
        HelpSection(title: "Quick Look Extension", content: """
            QuickMD includes a Quick Look extension that replaces the built-in macOS Markdown previewer. Select any supported file in Finder and press Space to preview it.

            Supported file types: Markdown, JSON, YAML, and 40+ source code languages.

            If previews don't work after installation, try:
            1. Open System Settings > Privacy & Security > Extensions > Quick Look
            2. Ensure QuickMDPreview is enabled
            """),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("QuickMD")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Markdown previewer, editor, and Quick Look extension")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Divider()

                ForEach(sections) { section in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(section.title)
                            .font(.title2)
                            .fontWeight(.semibold)
                        Text(section.content)
                            .font(.body)
                            .foregroundStyle(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
        }
        .frame(minWidth: 480, idealWidth: 560, minHeight: 400)
    }
}

struct ShortcutsView: View {
    private struct Shortcut: Identifiable {
        let id = UUID()
        let keys: String
        let action: String
    }

    private struct ShortcutGroup: Identifiable {
        let id = UUID()
        let title: String
        let shortcuts: [Shortcut]
    }

    private let groups: [ShortcutGroup] = [
        ShortcutGroup(title: "File", shortcuts: [
            Shortcut(keys: "\u{2318}O", action: "Open"),
            Shortcut(keys: "\u{21E7}\u{2318}E", action: "Export as PDF"),
            Shortcut(keys: "\u{2318}S", action: "Save"),
        ]),
        ShortcutGroup(title: "View", shortcuts: [
            Shortcut(keys: "\u{2318}=", action: "Zoom In"),
            Shortcut(keys: "\u{2318}-", action: "Zoom Out"),
            Shortcut(keys: "\u{2318}0", action: "Actual Size"),
            Shortcut(keys: "\u{2318}E", action: "Show Editor"),
        ]),
        ShortcutGroup(title: "Theme", shortcuts: [
            Shortcut(keys: "\u{21E7}\u{2318}1", action: "System"),
            Shortcut(keys: "\u{2325}\u{2318}L", action: "Light"),
            Shortcut(keys: "\u{2325}\u{2318}D", action: "Dark"),
        ]),
        ShortcutGroup(title: "Tools", shortcuts: [
            Shortcut(keys: "\u{2318}F", action: "Find"),
            Shortcut(keys: "\u{2318}L", action: "Toggle Line Numbers"),
            Shortcut(keys: "\u{2325}\u{2318}W", action: "Toggle Word Wrap"),
            Shortcut(keys: "\u{2318}G", action: "Jump to Line"),
            Shortcut(keys: "\u{21E7}\u{2318}P", action: "Presentation Mode"),
            Shortcut(keys: "\u{21E7}\u{2318}A", action: "Auto-Reload"),
            Shortcut(keys: "\u{21E7}\u{2318}R", action: "Read Aloud"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(groups) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.title)
                            .font(.headline)
                            .padding(.bottom, 2)
                        ForEach(group.shortcuts) { shortcut in
                            HStack {
                                Text(shortcut.action)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text(shortcut.keys)
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .padding(20)
        }
        .frame(minWidth: 320, idealWidth: 380, minHeight: 300)
    }
}
