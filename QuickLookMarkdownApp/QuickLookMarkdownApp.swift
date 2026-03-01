import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static var pendingURL: URL?

    static weak var model: MarkdownDocumentModel? {
        didSet {
            MarkdownDocumentModel.log("AppDelegate.model didSet, model=\(model == nil ? "nil" : "set"), pendingURL=\(pendingURL?.path ?? "nil")")
            if let url = pendingURL, let model {
                MarkdownDocumentModel.log("Loading pending URL: \(url.path)")
                model.load(from: url)
                pendingURL = nil
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        MarkdownDocumentModel.log("applicationDidFinishLaunching")
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        MarkdownDocumentModel.log("openFiles called: \(filenames)")
        let url = filenames.first.map { URL(fileURLWithPath: $0) }
        if let url {
            if let model = Self.model {
                MarkdownDocumentModel.log("Model available, loading directly")
                model.load(from: url)
            } else {
                MarkdownDocumentModel.log("Model not yet available, queuing URL")
                Self.pendingURL = url
            }
        }
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        MarkdownDocumentModel.log("open(urls:) called: \(urls.map(\.path))")
        if let url = urls.first {
            if let model = Self.model {
                model.load(from: url)
            } else {
                Self.pendingURL = url
            }
        }
    }
}

@main
struct QuickLookMarkdownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = MarkdownDocumentModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .frame(minWidth: 400, idealWidth: 900, minHeight: 300, idealHeight: 620)
                .onAppear {
                    MarkdownDocumentModel.log("WindowGroup.onAppear, setting AppDelegate.model")
                    AppDelegate.model = model
                }
                .onOpenURL { url in
                    MarkdownDocumentModel.log("onOpenURL: \(url.path)")
                    model.load(from: url)
                }
        }
        .windowResizability(.contentMinSize)
    }
}
