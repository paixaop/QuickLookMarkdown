import SwiftUI
import UniformTypeIdentifiers
import WebKit

// MARK: - FocusedValue for active document model

private struct FocusedModelKey: FocusedValueKey {
    typealias Value = MarkdownDocumentModel
}

extension FocusedValues {
    var documentModel: MarkdownDocumentModel? {
        get { self[FocusedModelKey.self] }
        set { self[FocusedModelKey.self] = newValue }
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
}

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let theme: String

    class Coordinator {
        var lastHTML: String?
        var lastTheme: String?
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

        let view = ZoomableWebView(frame: .zero, configuration: config)
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

// MARK: - ContentView

struct ContentView: View {
    @StateObject private var model = MarkdownDocumentModel()
    @AppStorage("theme") var theme = "system"

    var body: some View {
        Group {
            if let html = model.html {
                WebView(html: html, baseURL: model.baseURL, theme: theme)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .focusedValue(\.documentModel, model)
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
            if let url = AppDelegate.pendingURL {
                MarkdownDocumentModel.log("onAppear: loading pendingURL \(url.path)")
                model.load(from: url)
                AppDelegate.pendingURL = nil
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
                }
            }
        }
        .onChange(of: model.fileName) { _ in
            DispatchQueue.main.async {
                if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                    window.title = model.fileName ?? "QuickMD"
                }
            }
        }
    }
}
