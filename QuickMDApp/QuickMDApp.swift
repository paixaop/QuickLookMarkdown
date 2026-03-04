import SwiftUI
import UniformTypeIdentifiers

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var pendingURL: URL?
    static weak var activeModel: MarkdownDocumentModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        MarkdownDocumentModel.log("applicationDidFinishLaunching")
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

@main
struct QuickMDApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @AppStorage("theme") private var theme = "system"
    @FocusedValue(\.documentModel) private var activeModel

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
            }
            CommandMenu("Theme") {
                Button("System") {
                    theme = "system"
                    evalJS("if(window.__setTheme) __setTheme('system')")
                }
                .keyboardShortcut("1", modifiers: [.command, .shift])
                Button("Light") {
                    theme = "light"
                    evalJS("if(window.__setTheme) __setTheme('light')")
                }
                .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Dark") {
                    theme = "dark"
                    evalJS("if(window.__setTheme) __setTheme('dark')")
                }
                .keyboardShortcut("d", modifiers: [.command, .option])
            }
            CommandGroup(after: .toolbar) {
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
                Button("Toggle Line Numbers") {
                    evalJS("if(window.__toggleLineNumbers) __toggleLineNumbers()")
                }
                .keyboardShortcut("l")
                Button("Jump to Line\u{2026}") {
                    evalJS("if(window.__jumpToLine) __jumpToLine()")
                }
                .keyboardShortcut("g")
                Divider()
                Button("Read Aloud") {
                    evalJS("if(window.__speak){if(typeof speechSynthesis!=='undefined'&&speechSynthesis.speaking&&!speechSynthesis.paused)__speak.pause();else __speak.start();}")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                Button("Stop Reading") {
                    evalJS("if(window.__speak) __speak.stop()")
                }
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

    var body: some View {
        Form {
            Picker("Theme", selection: $theme) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)

            Toggle("Show line numbers by default", isOn: $lineNumbers)

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
