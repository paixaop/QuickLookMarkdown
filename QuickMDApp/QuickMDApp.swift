import AppKit
import SwiftUI
import UniformTypeIdentifiers
import WebKit

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
                    if let model = activeModel, let url = model.currentURL {
                        try? model.rawContent.write(to: url, atomically: true, encoding: .utf8)
                    }
                }
                .keyboardShortcut("s")

                Button("Export as PDF\u{2026}") {
                    guard let webView = WebViewStore.shared.webView else { return }
                    let panel = NSSavePanel()
                    panel.allowedContentTypes = [UTType.pdf]
                    let baseName = activeModel?.fileName ?? "document"
                    let ext = URL(fileURLWithPath: baseName).pathExtension
                    panel.nameFieldStringValue = ext.isEmpty ? baseName + ".pdf" : baseName.replacingOccurrences(of: ".\(ext)", with: ".pdf")
                    if panel.runModal() == .OK, let url = panel.url {
                        // Apply print-like styles before capturing PDF
                        let applyPrintCSS = """
                        (function() {
                            var s = document.createElement('style');
                            s.id = '__pdfExportStyle';
                            s.textContent = '#toc-container, .copy-btn, #speak-btn, #find-bar, #jump-bar, .reading-stats, .pres-overlay, .mermaid-overlay { display: none !important; } #layout { display: block !important; height: auto !important; } #layout.has-toc .markdown-body { overflow: visible !important; margin-left: 0 !important; } body { background: white !important; } .markdown-body { padding: 20px !important; max-width: 100% !important; }';
                            document.head.appendChild(s);
                        })();
                        """
                        let removePrintCSS = "var s = document.getElementById('__pdfExportStyle'); if (s) s.remove();"

                        webView.evaluateJavaScript(applyPrintCSS) { _, _ in
                            // Small delay to let layout reflow
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                webView.createPDF { result in
                                    // Restore normal styles
                                    webView.evaluateJavaScript(removePrintCSS) { _, _ in }
                                    switch result {
                                    case .success(let data):
                                        do {
                                            try data.write(to: url)
                                        } catch {
                                            DispatchQueue.main.async {
                                                let alert = NSAlert()
                                                alert.messageText = "Failed to save PDF"
                                                alert.informativeText = error.localizedDescription
                                                alert.runModal()
                                            }
                                        }
                                    case .failure(let error):
                                        DispatchQueue.main.async {
                                            let alert = NSAlert()
                                            alert.messageText = "Failed to create PDF"
                                            alert.informativeText = error.localizedDescription
                                            alert.runModal()
                                        }
                                    }
                                }
                            }
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
                    activeModel?.goBack()
                }
                .keyboardShortcut("[")
                .disabled(activeModel?.canGoBack != true)
                Button("Forward") {
                    activeModel?.goForward()
                }
                .keyboardShortcut("]")
                .disabled(activeModel?.canGoForward != true)
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
            }
            CommandMenu("Tools") {
                Button("Find\u{2026}") {
                    evalJS("if(window.__findOpen) __findOpen()")
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
                Toggle("Show Editor", isOn: Binding(
                    get: { showEditor?.wrappedValue ?? false },
                    set: { showEditor?.wrappedValue = $0 }
                ))
                .keyboardShortcut("e", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
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

struct SettingsView: View {
    @AppStorage("theme") private var theme = "system"
    @AppStorage("lineNumbers") private var lineNumbers = false
    @AppStorage("fontSize") private var fontSize = 16
    @AppStorage("openLinksInNewTab") private var openLinksInNewTab = true

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)

            Toggle("Show line numbers by default", isOn: $lineNumbers)
            Toggle("Open file links in new tab", isOn: $openLinksInNewTab)

            HStack {
                Text("Default font size")
                Stepper("\(fontSize)px", value: $fontSize, in: 10...32, step: 2)
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
