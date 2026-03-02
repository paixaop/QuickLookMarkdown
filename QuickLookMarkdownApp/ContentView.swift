import SwiftUI
import WebKit

struct WebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?

    class Coordinator {
        var lastHTML: String?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> WKWebView {
        MarkdownDocumentModel.log("WebView.makeNSView called, html length=\(html.count)")
        let config = WKWebViewConfiguration()

        // Inject highlight.js + js-yaml (before render scripts)
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
        // Highlight + format render script (runs after libs are loaded)
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.highlightRenderScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        // Inject mermaid.js
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
            config.userContentController.addUserScript(WKUserScript(
                source: MarkdownDocumentModel.mermaidZoomScript,
                injectionTime: .atDocumentEnd, forMainFrameOnly: true
            ))
        }

        // Inject TOC sidebar script
        config.userContentController.addUserScript(WKUserScript(
            source: MarkdownDocumentModel.tocScript,
            injectionTime: .atDocumentEnd, forMainFrameOnly: true
        ))

        let view = WKWebView(frame: .zero, configuration: config)
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: baseURL)
        MarkdownDocumentModel.log("WebView.loadHTMLString called, baseURL=\(baseURL?.path ?? "nil")")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        guard html != context.coordinator.lastHTML else {
            MarkdownDocumentModel.log("WebView.updateNSView skipped (same HTML)")
            return
        }
        MarkdownDocumentModel.log("WebView.updateNSView reloading, html length=\(html.count)")
        context.coordinator.lastHTML = html
        view.loadHTMLString(html, baseURL: baseURL)
    }
}

struct ContentView: View {
    @ObservedObject var model: MarkdownDocumentModel

    var body: some View {
        Group {
            if let html = model.html {
                VStack(spacing: 0) {
                    HStack {
                        Text(model.fileName ?? "Markdown")
                            .font(.headline)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(.thinMaterial)

                    WebView(html: html, baseURL: model.baseURL)
                }
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
                        Text("Double-click a .md file to open and render it here.")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .onAppear {
            MarkdownDocumentModel.log("ContentView.onAppear, html=\(model.html == nil ? "nil" : "\(model.html!.count) chars")")
        }
    }
}
