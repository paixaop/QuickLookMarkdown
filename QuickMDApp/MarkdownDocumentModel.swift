import AppKit
import Foundation
import Markdown
import os

private let logger = Logger(subsystem: "com.pedro.QuickMDApp", category: "MarkdownModel")

// MARK: - Sidebar Data Models

struct TOCHeading: Identifiable, Equatable {
    let id: String       // slug ID for scrolling in preview
    let text: String     // heading text
    let level: Int       // 1-6
    let sourceLine: Int  // data-source-line value for editor jump
}

enum SidebarPanel: String, CaseIterable {
    case toc, comments, files
    var icon: String {
        switch self {
        case .toc: return "list.bullet"
        case .comments: return "bubble.left"
        case .files: return "folder"
        }
    }
    var title: String {
        switch self {
        case .toc: return "Contents"
        case .comments: return "Comments"
        case .files: return "Files"
        }
    }
}

struct FileNode: Identifiable, Equatable {
    let id: String       // full path for files, dir name for directories
    let name: String
    let isDirectory: Bool
    let path: String
    let children: [FileNode]

    static func == (lhs: FileNode, rhs: FileNode) -> Bool {
        lhs.id == rhs.id && lhs.name == rhs.name && lhs.isDirectory == rhs.isDirectory && lhs.children == rhs.children
    }
}

struct ParsedComment: Identifiable, Equatable {
    let id: Int          // index in source
    let range: NSRange
    let comment: String
    let annotatedText: String

    static func == (lhs: ParsedComment, rhs: ParsedComment) -> Bool {
        lhs.id == rhs.id && lhs.range == rhs.range && lhs.comment == rhs.comment
    }
}

final class MarkdownDocumentModel: ObservableObject {
    @Published var html: String?
    @Published var baseURL: URL?
    @Published var fileName: String?
    @Published var errorMessage: String?

    // MARK: - Sidebar Data
    @Published var tocHeadings: [TOCHeading] = []
    @Published var activeTOCHeadingID: String? = nil
    @Published var parsedComments: [ParsedComment] = []
    @Published var fileTree: [FileNode] = []

    // MARK: - Directory Sandbox Bookmarks

    /// Bookmarks for directories the user has granted access to (via opening files).
    /// Keyed by standardized directory path.
    private static var directoryBookmarks: [String: Data] = [:]

    /// Save a security-scoped bookmark for the parent directory of a file URL.
    static func bookmarkParentDirectory(of url: URL) {
        let dir = url.deletingLastPathComponent()
        let key = dir.standardizedFileURL.path
        guard directoryBookmarks[key] == nil else { return }
        do {
            let bookmark = try dir.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            directoryBookmarks[key] = bookmark
            log("Bookmarked directory: \(key)")
        } catch {
            log("Failed to bookmark directory \(key): \(error)")
        }
    }

    /// Attempt to gain sandbox access to a file URL by resolving a bookmark for its parent directory.
    /// Returns true if access was granted (caller must call `stopAccessingSecurityScopedResource()` on the returned URL).
    @discardableResult
    static func accessDirectoryForFile(_ url: URL) -> URL? {
        let dir = url.deletingLastPathComponent()
        let key = dir.standardizedFileURL.path
        guard let bookmark = directoryBookmarks[key] else { return nil }
        var isStale = false
        do {
            let resolved = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope, relativeTo: nil, bookmarkDataIsStale: &isStale)
            if isStale {
                directoryBookmarks.removeValue(forKey: key)
                return nil
            }
            if resolved.startAccessingSecurityScopedResource() {
                return resolved
            }
        } catch {
            log("Failed to resolve bookmark for \(key): \(error)")
        }
        return nil
    }

    static let logFileURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QuickMD.log")
        logger.info("Log file: \(url.path)")
        return url
    }()

    static func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] \(message)\n"
        logger.info("\(message)")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFileURL.path) {
                if let handle = try? FileHandle(forWritingTo: logFileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                try? data.write(to: logFileURL)
            }
        }
    }

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    static func isMarkdownExtension(_ ext: String) -> Bool {
        markdownExtensions.contains(ext)
    }

    private static let extensionToLanguage: [String: String] = [
        "json": "json", "yaml": "yaml", "yml": "yaml",
        "py": "python", "rb": "ruby", "pl": "perl", "php": "php",
        "c": "c", "h": "c", "cpp": "cpp", "cxx": "cpp", "cc": "cpp",
        "hpp": "cpp", "hxx": "cpp", "m": "objectivec", "mm": "objectivec",
        "swift": "swift", "java": "java", "js": "javascript", "mjs": "javascript",
        "ts": "typescript", "tsx": "typescript", "jsx": "javascript",
        "css": "css", "html": "html", "htm": "html", "xml": "xml",
        "rs": "rust", "go": "go", "sh": "bash", "bash": "bash", "zsh": "bash",
        "sql": "sql", "r": "r", "kt": "kotlin", "kts": "kotlin",
        "scala": "scala", "hs": "haskell", "lua": "lua", "dart": "dart",
        "toml": "toml", "ini": "ini", "conf": "ini", "cfg": "ini",
        "dockerfile": "dockerfile", "makefile": "makefile",
        "cs": "csharp", "fs": "fsharp", "ex": "elixir", "exs": "elixir",
        "erl": "erlang", "clj": "clojure", "zig": "zig", "nim": "nim",
        "v": "v", "groovy": "groovy", "gradle": "groovy",
        "dot": "dot", "gv": "graphviz",
    ]

    private static func readFileContent(from url: URL) throws -> String {
        // Try UTF-8 first
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        // Auto-detect encoding
        let data = try Data(contentsOf: url)
        // Try common encodings
        let encodings: [String.Encoding] = [.utf16, .isoLatin1, .windowsCP1252, .macOSRoman]
        for encoding in encodings {
            if let content = String(data: data, encoding: encoding) {
                return content
            }
        }
        throw NSError(domain: "QuickMD", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unable to detect file encoding"])
    }

    private static func stripFrontmatter(_ content: String) -> (body: String, frontmatter: String?) {
        guard content.hasPrefix("---\n") || content.hasPrefix("---\r\n") else {
            return (content, nil)
        }
        let lines = content.components(separatedBy: "\n")
        var endIndex: Int?
        for i in 1..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces) == "---" {
                endIndex = i
                break
            }
        }
        guard let end = endIndex else { return (content, nil) }
        let yamlLines = lines[1..<end]
        let yaml = yamlLines.joined(separator: "\n")
        let bodyLines = lines[(end + 1)...]
        let body = bodyLines.joined(separator: "\n")
        return (body, yaml)
    }

    private static func htmlBody(for url: URL) throws -> (html: String, isMarkdown: Bool) {
        let content = try readFileContent(from: url)
        let ext = url.pathExtension.lowercased()

        if markdownExtensions.contains(ext) {
            let (body, frontmatter) = stripFrontmatter(content)
            let processed = preprocessComments(body)
            var html = SourceMappedHTMLFormatter.format(processed)
            if let fm = frontmatter {
                // Track frontmatter line count for editor sync (+2 for the two --- delimiters)
                SourceMappedHTMLFormatter.lastFrontmatterLineCount = fm.components(separatedBy: "\n").count + 2
                let escaped = fm
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                html = "<div id=\"frontmatter-data\" style=\"display:none\">\(escaped)</div>\n" + html
            } else {
                SourceMappedHTMLFormatter.lastFrontmatterLineCount = 0
            }
            return (html, true)
        }

        let lang = extensionToLanguage[ext] ?? ""
        let escaped = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let langClass = lang.isEmpty ? "" : " class=\"language-\(lang)\""
        return ("<pre><code\(langClass)>\(escaped)</code></pre>", false)
    }

    @Published var currentURL: URL?
    @Published var rawContent: String = ""
    @Published var isDirty = false
    var frontmatterLineCount: Int = 0
    @Published var autoReload = false
    let undoManager = UndoManager()

    func markClean() {
        isDirty = false
    }

    /// Set rawContent with undo support. Use for programmatic changes (AI, toolbar actions).
    func setContent(_ newContent: String, actionName: String = "AI Transform") {
        let oldContent = rawContent
        undoManager.registerUndo(withTarget: self) { target in
            target.setContent(oldContent, actionName: actionName)
        }
        undoManager.setActionName(actionName)
        rawContent = newContent
        if let url = currentURL {
            try? newContent.write(to: url, atomically: true, encoding: .utf8)
        }
        rerender()
    }
    private var fileWatcherSource: DispatchSourceFileSystemObject?

    // MARK: - File Tree for Sidebar

    static func scanDirectoryForMarkdown(_ dirURL: URL) -> [[String: Any]] {
        let fm = FileManager.default
        let mdExts: Set<String> = ["md", "markdown", "mdown", "mkd"]
        guard let items = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = items.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var results: [[String: Any]] = []
        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let children = scanDirectoryForMarkdown(item)
                if !children.isEmpty {
                    results.append([
                        "type": "dir",
                        "name": item.lastPathComponent,
                        "children": children
                    ])
                }
            } else if mdExts.contains(item.pathExtension.lowercased()) {
                results.append([
                    "type": "file",
                    "name": item.lastPathComponent,
                    "path": item.path
                ])
            }
        }
        return results
    }

    // MARK: - Sidebar Data Refresh

    /// Refresh parsed comments from current rawContent
    func refreshParsedComments() {
        let comments = Self.parseComments(in: rawContent)
        parsedComments = comments.enumerated().map { idx, c in
            ParsedComment(id: idx, range: c.range, comment: c.comment, annotatedText: c.annotatedText)
        }
    }

    /// Refresh file tree from current file's directory
    func refreshFileTree() {
        guard let dirURL = currentURL?.deletingLastPathComponent() else {
            fileTree = []
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let tree = Self.scanDirectoryForMarkdown(dirURL)
            let nodes = Self.convertToFileNodes(tree)
            DispatchQueue.main.async {
                self?.fileTree = nodes
            }
        }
    }

    /// Convert scanDirectoryForMarkdown output to FileNode array
    private static func convertToFileNodes(_ items: [[String: Any]]) -> [FileNode] {
        items.compactMap { dict -> FileNode? in
            guard let name = dict["name"] as? String,
                  let type = dict["type"] as? String else { return nil }
            if type == "dir" {
                let children = (dict["children"] as? [[String: Any]]) ?? []
                return FileNode(id: "dir:\(name)", name: name, isDirectory: true, path: "", children: convertToFileNodes(children))
            } else {
                let path = dict["path"] as? String ?? ""
                return FileNode(id: path, name: name, isDirectory: false, path: path, children: [])
            }
        }
    }

    // MARK: - Navigation History

    @Published var backStack: [URL] = []
    @Published var forwardStack: [URL] = []
    /// Fragment (e.g. "tls-termination") to scroll to after next page load.
    var pendingFragment: String?
    private var isNavigating = false

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    /// Navigate to a URL via link click — pushes current URL onto back stack.
    func navigateTo(_ url: URL) {
        if let current = currentURL {
            backStack.append(current)
            forwardStack.removeAll()
        }
        pendingFragment = url.fragment
        isNavigating = true
        load(from: url)
        isNavigating = false
    }

    func goBack() {
        guard let prev = backStack.popLast() else { return }
        if let current = currentURL {
            forwardStack.append(current)
        }
        // If the target URL is open in another tab, switch to it
        if switchToWindowWithURL(prev) { return }
        isNavigating = true
        load(from: prev)
        isNavigating = false
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = currentURL {
            backStack.append(current)
        }
        // If the target URL is open in another tab, switch to it
        if switchToWindowWithURL(next) { return }
        isNavigating = true
        load(from: next)
        isNavigating = false
    }

    /// Try to switch to a window/tab that has the given URL open. Returns true if found.
    @discardableResult
    private func switchToWindowWithURL(_ url: URL) -> Bool {
        let standardized = url.standardizedFileURL
        for window in NSApp.windows {
            if let represented = window.representedURL, represented.standardizedFileURL == standardized {
                window.makeKeyAndOrderFront(nil)
                if let tabGroup = window.tabGroup {
                    tabGroup.selectedWindow = window
                }
                return true
            }
        }
        return false
    }

    /// Re-render HTML from current rawContent without reloading from disk.
    func rerender() {
        guard let url = currentURL else { return }
        let ext = url.pathExtension.lowercased()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "." + ext)
        try? rawContent.write(to: tempURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        if let result = try? Self.htmlBody(for: tempURL) {
            frontmatterLineCount = SourceMappedHTMLFormatter.lastFrontmatterLineCount
            html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)
        }
    }

    func load(from url: URL) {
        Self.log("load(from: \(url.path))")

        // File size guard
        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
           let size = attrs[.size] as? Int {
            if size > 50_000_000 { // 50MB
                Self.log("File too large: \(size) bytes")
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    alert.messageText = "File Too Large"
                    alert.informativeText = "This file is \(size / 1_000_000)MB. QuickMD supports files up to 50MB."
                    alert.alertStyle = .warning
                    alert.runModal()
                }
                return
            }
            if size > 5_000_000 { // 5MB
                Self.log("Large file warning: \(size) bytes")
            }
        }

        let didAccess = url.startAccessingSecurityScopedResource()
        defer { if didAccess { url.stopAccessingSecurityScopedResource() } }
        do {
            let result = try Self.htmlBody(for: url)
            let content = try Self.readFileContent(from: url)
            Self.log("Read \(content.count) chars from file")
            Self.log("Produced \(result.html.count) chars of HTML")
            rawContent = content
            frontmatterLineCount = SourceMappedHTMLFormatter.lastFrontmatterLineCount
            html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)
            Self.log("Wrapped HTML total: \(html?.count ?? 0) chars")
            baseURL = url.deletingLastPathComponent()
            fileName = url.lastPathComponent
            currentURL = url
            errorMessage = nil
            Self.log("Model updated successfully, fileName=\(url.lastPathComponent)")

            // Note recent document
            NSDocumentController.shared.noteNewRecentDocumentURL(url)

            // Bookmark parent directory for sandbox access to sibling files
            Self.bookmarkParentDirectory(of: url)

            // Auto-reload by default
            startWatching(url: url)
        } catch {
            Self.log("ERROR: \(error.localizedDescription)")
            html = nil
            baseURL = nil
            fileName = url.lastPathComponent
            errorMessage = "Could not render \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: - Live Reload

    func startWatching(url: URL) {
        stopWatching()
        guard let fileDescriptor = open(url.path, O_EVTONLY) as Int32?,
              fileDescriptor != -1 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            // Check if file was deleted
            guard FileManager.default.fileExists(atPath: url.path) else {
                Self.log("File was deleted: \(url.path)")
                DispatchQueue.main.async { [weak self] in
                    self?.autoReload = false
                    self?.stopWatching()
                }
                return
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Capture scroll position before reload so it can be restored
                if let webView = WebViewStore.shared.webView {
                    webView.evaluateJavaScript("window.__getScrollFraction ? __getScrollFraction() : (document.documentElement.scrollTop / Math.max(1, document.documentElement.scrollHeight - document.documentElement.clientHeight))") { result, _ in
                        WebViewStore.shared.preReloadScrollFraction = result as? Double ?? 0
                        WebViewStore.shared.isFileWatcherReload = true
                        self?.load(from: url)
                    }
                } else {
                    self?.load(from: url)
                }
            }
        }
        source.setCancelHandler {
            close(fileDescriptor)
        }
        source.resume()
        fileWatcherSource = source
        autoReload = true
    }

    func stopWatching() {
        fileWatcherSource?.cancel()
        fileWatcherSource = nil
        autoReload = false
    }

    static let mermaidJS: String = {
        log("Loading mermaid.min.js from bundle...")
        if let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Resources") {
            log("Found mermaid at: \(url.path)")
            if let js = try? String(contentsOf: url, encoding: .utf8) {
                log("Loaded mermaid.min.js: \(js.count) chars")
                return js
            } else {
                log("ERROR: Could not read mermaid.min.js as UTF-8")
            }
        } else {
            log("ERROR: mermaid.min.js not found in bundle")
            if let resourcePath = Bundle.main.resourcePath {
                log("Bundle resourcePath: \(resourcePath)")
                let contents = (try? FileManager.default.contentsOfDirectory(atPath: resourcePath)) ?? []
                log("Bundle contents: \(contents.joined(separator: ", "))")
            }
        }
        return ""
    }()

    static let highlightJS: String = {
        loadResource("highlight.min", ext: "js", label: "highlight.js")
    }()

    static let jsYamlJS: String = {
        loadResource("js-yaml.min", ext: "js", label: "js-yaml")
    }()

    static let katexJS: String = {
        loadResource("katex.min", ext: "js", label: "katex.js")
    }()

    static let autoRenderJS: String = {
        loadResource("auto-render.min", ext: "js", label: "auto-render.js")
    }()

    static let graphvizJS: String = {
        loadResource("viz-standalone", ext: "js", label: "viz-standalone.js")
    }()

    static let morphdomJS: String = {
        loadResource("morphdom-umd.min", ext: "js", label: "morphdom")
    }()

    static let highlightGitHubCSS: String = {
        loadResource("highlight-github", ext: "css", label: "highlight GitHub CSS")
    }()

    static let highlightGitHubDarkCSS: String = {
        loadResource("highlight-github-dark", ext: "css", label: "highlight GitHub Dark CSS")
    }()

    private static func loadResource(_ name: String, ext: String, subdirectory: String? = nil, label: String) -> String {
        let subdir = subdirectory.map { "Resources/\($0)" } ?? "Resources"
        log("Loading \(label) from bundle...")
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdir),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            log("Loaded \(label): \(content.count) chars")
            return content
        }
        log("ERROR: \(label) not found in bundle")
        return ""
    }

    private static func loadScript(_ name: String) -> String {
        loadResource(name, ext: "js", subdirectory: "scripts", label: name)
    }

    static let themeScript = loadScript("theme")

    static let mermaidRenderScript = loadScript("mermaid-render")

    static let zoomOverlayScript = loadScript("zoom-overlay")

    static let highlightRenderScript = loadScript("highlight-render")

    static let copyButtonScript = loadScript("copy-button")

    static let katexRenderScript = loadScript("katex-render")

    static let readingStatsScript = loadScript("reading-stats")

    static let fontSizeScript: String = loadScript("font-size")

    static let lineNumbersScript = loadScript("line-numbers")

    static let jumpToLineScript = loadScript("jump-to-line")

    static let findScript = loadScript("find")

    static let graphvizRenderScript = loadScript("graphviz-render")

    static let speakScript = loadScript("speak")

    // MARK: - Heading Data Script (sends TOC data to Swift via bridge)

    static let headingDataScript = loadScript("heading-data")

    static let tocScript = loadScript("toc")

    // MARK: - Custom CSS Themes

    // MARK: - Built-in Themes

    static let builtInThemes: [(name: String, css: String)] = [
        ("Dracula", """
        .markdown-body { background: #282a36; color: #f8f8f2; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { color: #bd93f9; border-color: #44475a; }
        .markdown-body a { color: #8be9fd; }
        .markdown-body pre, .markdown-body code { background: #44475a; }
        .markdown-body pre code.hljs { background: transparent; }
        .markdown-body blockquote { border-left-color: #6272a4; color: #6272a4; }
        .markdown-body table th, .markdown-body table td { border-color: #44475a; }
        .markdown-body table tr { background: #282a36; }
        .markdown-body table tr:nth-child(2n) { background: #2e303e; }
        .markdown-body hr { background: #44475a; }
        .markdown-body strong { color: #ffb86c; }
        .markdown-body em { color: #ff79c6; }
        """),
        ("Solarized Light", """
        .markdown-body { background: #fdf6e3; color: #657b83; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { color: #268bd2; border-color: #eee8d5; }
        .markdown-body a { color: #268bd2; }
        .markdown-body pre, .markdown-body code { background: #eee8d5; }
        .markdown-body pre code.hljs { background: transparent; }
        .markdown-body blockquote { border-left-color: #93a1a1; color: #93a1a1; }
        .markdown-body table th, .markdown-body table td { border-color: #eee8d5; }
        .markdown-body hr { background: #eee8d5; }
        """),
        ("Solarized Dark", """
        .markdown-body { background: #002b36; color: #839496; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { color: #268bd2; border-color: #073642; }
        .markdown-body a { color: #2aa198; }
        .markdown-body pre, .markdown-body code { background: #073642; }
        .markdown-body pre code.hljs { background: transparent; }
        .markdown-body blockquote { border-left-color: #586e75; color: #586e75; }
        .markdown-body table th, .markdown-body table td { border-color: #073642; }
        .markdown-body table tr { background: #002b36; }
        .markdown-body table tr:nth-child(2n) { background: #073642; }
        .markdown-body hr { background: #073642; }
        """),
        ("Nord", """
        .markdown-body { background: #2e3440; color: #d8dee9; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { color: #88c0d0; border-color: #3b4252; }
        .markdown-body a { color: #88c0d0; }
        .markdown-body pre, .markdown-body code { background: #3b4252; }
        .markdown-body pre code.hljs { background: transparent; }
        .markdown-body blockquote { border-left-color: #4c566a; color: #616e88; }
        .markdown-body table th, .markdown-body table td { border-color: #3b4252; }
        .markdown-body table tr { background: #2e3440; }
        .markdown-body table tr:nth-child(2n) { background: #3b4252; }
        .markdown-body hr { background: #3b4252; }
        .markdown-body strong { color: #81a1c1; }
        """),
        ("Sepia", """
        .markdown-body { background: #f5f0e8; color: #5b4636; }
        .markdown-body h1, .markdown-body h2, .markdown-body h3, .markdown-body h4, .markdown-body h5, .markdown-body h6 { color: #8b4513; border-color: #e8ddd0; }
        .markdown-body a { color: #b8860b; }
        .markdown-body pre, .markdown-body code { background: #ede5d8; }
        .markdown-body pre code.hljs { background: transparent; }
        .markdown-body blockquote { border-left-color: #c4a882; color: #8b7355; }
        .markdown-body table th, .markdown-body table td { border-color: #e8ddd0; }
        .markdown-body table tr { background: #f5f0e8; }
        .markdown-body table tr:nth-child(2n) { background: #ede5d8; }
        .markdown-body hr { background: #e8ddd0; }
        """),
    ]

    static let themesDirectory: URL = {
        let url = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("QuickMD/themes")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static func availableThemes() -> [String] {
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: themesDirectory.path) else { return [] }
        return files.filter { $0.hasSuffix(".css") }.map { String($0.dropLast(4)) }.sorted()
    }

    static func customCSS(for theme: String) -> String {
        let url = themesDirectory.appendingPathComponent("\(theme).css")
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    // MARK: - Word Wrap Toggle

    static let wordWrapScript = loadScript("word-wrap")

    // MARK: - Anchor Links

    static let anchorLinksScript = loadScript("anchor-links")

    // MARK: - Emoji Shortcodes

    static let emojiScript = loadScript("emoji")

    // MARK: - Footnotes

    static let footnotesScript = loadScript("footnotes")

    // MARK: - Frontmatter

    static let frontmatterScript = loadScript("frontmatter")

    // MARK: - Presentation Mode

    static let presentationScript = loadScript("presentation")

    // Intercept link clicks via JS and forward to Swift, because WKWebView
    // may silently block file:// navigations from loadHTMLString pages
    // before decidePolicyFor is ever called.
    static let linkClickScript = loadScript("link-click")

    static let linkHoverScript = loadScript("link-hover")

    static let checkboxToggleScript = loadScript("checkbox-toggle")

    static let editorSyncScript = loadScript("editor-sync")

    // MARK: - Comment interaction script

    static let commentScript = loadScript("comment")

    // MARK: - Comments sidebar script

    static let commentsSidebarScript = loadScript("comments-sidebar")

    // MARK: - Files sidebar script

    static let filesBrowserScript = loadScript("files-browser")

    // MARK: - Sidebar arrange script

    static let sidebarArrangeScript = loadScript("sidebar-arrange")

    /// Incremental content update: replaces article content and re-runs post-processing scripts.
    /// This avoids a full page reload which causes flickering during live editing.
    /// Note: The HTML is generated from the user's own markdown via the Down library (trusted content),
    /// and is injected via evaluateJavaScript from Swift — not from external/untrusted sources.
    static let contentUpdateScript: String = loadScript("content-update")

    /// Toggle the nth task list checkbox in markdown source between [ ] and [x].
    static func toggleCheckbox(at index: Int, checked: Bool, in text: String) -> String {
        let pattern = checked ? "- [ ]" : "- [x]"
        let replacement = checked ? "- [x]" : "- [ ]"
        var count = 0
        var result = text
        var searchRange = result.startIndex..<result.endIndex
        while let range = result.range(of: pattern, range: searchRange) {
            if count == index {
                result.replaceSubrange(range, with: replacement)
                break
            }
            count += 1
            searchRange = range.upperBound..<result.endIndex
        }
        return result
    }

    static func htmlBodyPublic(for url: URL) throws -> (html: String, isMarkdown: Bool) {
        try htmlBody(for: url)
    }

    /// Generate just the body HTML from markdown text (for incremental updates without full page reload).
    static func markdownBodyHTML(from text: String) -> String {
        let (body, frontmatter) = stripFrontmatter(text)
        let processed = preprocessComments(body)
        var html = SourceMappedHTMLFormatter.format(processed)
        if let fm = frontmatter {
            SourceMappedHTMLFormatter.lastFrontmatterLineCount = fm.components(separatedBy: "\n").count + 2
            let escaped = fm
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            html = "<div id=\"frontmatter-data\" style=\"display:none\">\(escaped)</div>\n" + html
        } else {
            SourceMappedHTMLFormatter.lastFrontmatterLineCount = 0
        }
        return html
    }

    // MARK: - Source-Mapped HTML Formatter

    /// MarkupWalker that produces HTML with data-source-line/col attributes on block elements.
    /// This enables the rendered preview to map double-clicked positions back to exact source lines.
    struct SourceMappedHTMLFormatter: MarkupWalker {
        private(set) var result = ""
        var inTableHead = false
        var tableColumnAlignments: [Table.ColumnAlignment?]? = nil
        var currentTableColumn = 0

        /// Track frontmatter line count from the most recent format call (static context).
        static var lastFrontmatterLineCount: Int = 0

        static func format(_ inputString: String) -> String {
            let document = Document(parsing: inputString)
            var walker = SourceMappedHTMLFormatter()
            walker.visit(document)
            return walker.result
        }

        private func sourceAttrs(_ markup: Markup) -> String {
            guard let range = markup.range else { return "" }
            return " data-source-line=\"\(range.lowerBound.line)\" data-source-col=\"\(range.lowerBound.column)\""
        }

        // MARK: Block elements

        mutating func visitBlockQuote(_ blockQuote: BlockQuote) {
            result += "<blockquote\(sourceAttrs(blockQuote))>\n"
            descendInto(blockQuote)
            result += "</blockquote>\n"
        }

        mutating func visitCodeBlock(_ codeBlock: CodeBlock) {
            let languageAttr: String
            if let language = codeBlock.language {
                languageAttr = " class=\"language-\(language)\""
            } else {
                languageAttr = ""
            }
            result += "<pre\(sourceAttrs(codeBlock))><code\(languageAttr)>\(codeBlock.code)</code></pre>\n"
        }

        mutating func visitHeading(_ heading: Heading) {
            result += "<h\(heading.level)\(sourceAttrs(heading))>"
            descendInto(heading)
            result += "</h\(heading.level)>\n"
        }

        mutating func visitThematicBreak(_ thematicBreak: ThematicBreak) {
            result += "<hr />\n"
        }

        mutating func visitHTMLBlock(_ html: HTMLBlock) {
            result += html.rawHTML
        }

        mutating func visitListItem(_ listItem: ListItem) {
            result += "<li\(sourceAttrs(listItem))>"
            if let checkbox = listItem.checkbox {
                result += "<input type=\"checkbox\" disabled=\"\""
                if checkbox == .checked {
                    result += " checked=\"\""
                }
                result += " /> "
            }
            descendInto(listItem)
            result += "</li>\n"
        }

        mutating func visitOrderedList(_ orderedList: OrderedList) {
            let start: String
            if orderedList.startIndex != 1 {
                start = " start=\"\(orderedList.startIndex)\""
            } else {
                start = ""
            }
            result += "<ol\(start)\(sourceAttrs(orderedList))>\n"
            descendInto(orderedList)
            result += "</ol>\n"
        }

        mutating func visitUnorderedList(_ unorderedList: UnorderedList) {
            result += "<ul\(sourceAttrs(unorderedList))>\n"
            descendInto(unorderedList)
            result += "</ul>\n"
        }

        mutating func visitParagraph(_ paragraph: Paragraph) {
            result += "<p\(sourceAttrs(paragraph))>"
            descendInto(paragraph)
            result += "</p>\n"
        }

        mutating func visitTable(_ table: Table) {
            result += "<table\(sourceAttrs(table))>\n"
            tableColumnAlignments = table.columnAlignments
            descendInto(table)
            tableColumnAlignments = nil
            result += "</table>\n"
        }

        mutating func visitTableHead(_ tableHead: Table.Head) {
            result += "<thead>\n<tr>\n"
            inTableHead = true
            currentTableColumn = 0
            descendInto(tableHead)
            inTableHead = false
            result += "</tr>\n</thead>\n"
        }

        mutating func visitTableBody(_ tableBody: Table.Body) {
            if !tableBody.isEmpty {
                result += "<tbody>\n"
                descendInto(tableBody)
                result += "</tbody>\n"
            }
        }

        mutating func visitTableRow(_ tableRow: Table.Row) {
            result += "<tr>\n"
            currentTableColumn = 0
            descendInto(tableRow)
            result += "</tr>\n"
        }

        mutating func visitTableCell(_ tableCell: Table.Cell) {
            guard let alignments = tableColumnAlignments, currentTableColumn < alignments.count else { return }
            guard tableCell.colspan > 0 && tableCell.rowspan > 0 else { return }
            let element = inTableHead ? "th" : "td"
            result += "<\(element)\(sourceAttrs(tableCell))"
            if let alignment = alignments[currentTableColumn] {
                result += " align=\"\(alignment)\""
            }
            currentTableColumn += 1
            if tableCell.rowspan > 1 { result += " rowspan=\"\(tableCell.rowspan)\"" }
            if tableCell.colspan > 1 { result += " colspan=\"\(tableCell.colspan)\"" }
            result += ">"
            descendInto(tableCell)
            result += "</\(element)>\n"
        }

        // MARK: Inline elements

        private mutating func printInline(tag: String, _ content: Markup) {
            result += "<\(tag)>"
            descendInto(content)
            result += "</\(tag)>"
        }

        mutating func visitInlineCode(_ inlineCode: InlineCode) {
            result += "<code>\(inlineCode.code)</code>"
        }

        mutating func visitEmphasis(_ emphasis: Emphasis) {
            printInline(tag: "em", emphasis)
        }

        mutating func visitStrong(_ strong: Strong) {
            printInline(tag: "strong", strong)
        }

        mutating func visitImage(_ image: Image) {
            result += "<img"
            if let source = image.source, !source.isEmpty { result += " src=\"\(source)\"" }
            if let title = image.title, !title.isEmpty { result += " title=\"\(title)\"" }
            result += " />"
        }

        mutating func visitInlineHTML(_ inlineHTML: InlineHTML) {
            result += inlineHTML.rawHTML
        }

        mutating func visitLineBreak(_ lineBreak: LineBreak) {
            result += "<br />\n"
        }

        mutating func visitSoftBreak(_ softBreak: SoftBreak) {
            result += "\n"
        }

        mutating func visitLink(_ link: Link) {
            result += "<a"
            if let destination = link.destination { result += " href=\"\(destination)\"" }
            result += ">"
            descendInto(link)
            result += "</a>"
        }

        mutating func visitText(_ text: Text) {
            result += text.string
        }

        mutating func visitStrikethrough(_ strikethrough: Strikethrough) {
            printInline(tag: "del", strikethrough)
        }

        mutating func visitSymbolLink(_ symbolLink: SymbolLink) {
            if let destination = symbolLink.destination {
                result += "<code>\(destination)</code>"
            }
        }
    }

    // MARK: - Comment Annotations

    /// Replace comment markers with styled HTML spans before markdown parsing.
    /// Transforms `<!-- COMMENT: foo -->text<!-- /COMMENT -->` into `<mark class="qmd-comment" data-comment="foo">text</mark>`.
    static func preprocessComments(_ markdown: String) -> String {
        // Pattern: <!-- COMMENT: ... -->...<!-- /COMMENT -->
        // Using NSRegularExpression for reliable matching across multiline content
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*COMMENT:\s*(.*?)\s*-->([\s\S]*?)<!--\s*/COMMENT\s*-->"#,
            options: []
        ) else { return markdown }

        let nsMarkdown = markdown as NSString
        var result = markdown
        // Process matches in reverse order to preserve offsets
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        for match in matches.reversed() {
            let commentText = nsMarkdown.substring(with: match.range(at: 1))
            let annotatedText = nsMarkdown.substring(with: match.range(at: 2))
            let escapedComment = commentText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let replacement = "<mark class=\"qmd-comment\" data-comment=\"\(escapedComment)\">\(annotatedText)</mark>"
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    /// Wrap selected text with comment markers in the source.
    static func addComment(around selectedRange: NSRange, comment: String, in text: String) -> String {
        let nsText = text as NSString
        let selectedText = nsText.substring(with: selectedRange)
        let prefix = "<!-- COMMENT: \(comment) -->"
        let suffix = "<!-- /COMMENT -->"
        let replacement = "\(prefix)\(selectedText)\(suffix)"
        return nsText.replacingCharacters(in: selectedRange, with: replacement) as String
    }

    /// Remove comment markers at the given match index, keeping the annotated text.
    static func removeComment(at index: Int, in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*COMMENT:\s*.*?\s*-->([\s\S]*?)<!--\s*/COMMENT\s*-->"#,
            options: []
        ) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard index < matches.count else { return text }
        let match = matches[index]
        let annotatedText = nsText.substring(with: match.range(at: 1))
        return nsText.replacingCharacters(in: match.range, with: annotatedText) as String
    }

    /// Update the comment text at the given match index.
    static func updateComment(at index: Int, newComment: String, in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*COMMENT:\s*.*?\s*-->([\s\S]*?)<!--\s*/COMMENT\s*-->"#,
            options: []
        ) else { return text }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        guard index < matches.count else { return text }
        let match = matches[index]
        let annotatedText = nsText.substring(with: match.range(at: 1))
        let replacement = "<!-- COMMENT: \(newComment) -->\(annotatedText)<!-- /COMMENT -->"
        return nsText.replacingCharacters(in: match.range, with: replacement) as String
    }

    /// Parse all comments in the source text, returning their ranges and content.
    static func parseComments(in text: String) -> [(range: NSRange, comment: String, annotatedText: String)] {
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*COMMENT:\s*(.*?)\s*-->([\s\S]*?)<!--\s*/COMMENT\s*-->"#,
            options: []
        ) else { return [] }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        return matches.map { match in
            (
                range: match.range,
                comment: nsText.substring(with: match.range(at: 1)),
                annotatedText: nsText.substring(with: match.range(at: 2))
            )
        }
    }

    static func wrapHTMLPublic(_ body: String, isMarkdown: Bool) -> String {
        wrapHTML(body, isMarkdown: isMarkdown)
    }

    private static func wrapHTML(_ body: String, isMarkdown: Bool) -> String {
        // Sidebar markup removed — sidebars are now native SwiftUI views
        let sidebarsMarkup = ""

        let fileType = isMarkdown ? "markdown" : "code"
        return """
        <!doctype html>
        <html data-filetype="\(fileType)" data-theme="system">
          <head>
            <meta charset="utf-8" />
            <meta name="viewport" content="width=device-width,initial-scale=1" />
            <style>\(highlightGitHubCSS)</style>
            <style>
              @media (prefers-color-scheme: dark) { \(highlightGitHubDarkCSS) }
              /* Override hljs backgrounds to use our pre styling */
              pre code.hljs { display: block; overflow-x: auto; padding: 0; background: transparent; }
              code.hljs { padding: 0; background: transparent; }
              :root { color-scheme: light dark; }
              body {
                margin: 0;
                background: #ffffff;
                color: #1f2328;
                font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Helvetica, Arial, sans-serif;
              }
              @media (prefers-color-scheme: dark) {
                body { background: #1e1e1e; color: #d4d4d4; }
                .markdown-body pre { background: #2d2d2d; }
                .markdown-body :not(pre) > code { background: #2d2d2d; }
              }
              /* Forced dark theme */
              html[data-theme="dark"] { color-scheme: dark; }
              html[data-theme="dark"] body { background: #1e1e1e; color: #d4d4d4; }
              html[data-theme="dark"] .markdown-body pre { background: #2d2d2d; }
              html[data-theme="dark"] .markdown-body :not(pre) > code { background: #2d2d2d; }
              /* Forced light theme */
              html[data-theme="light"] { color-scheme: light; }
              html[data-theme="light"] body { background: #ffffff; color: #1f2328; }
              html[data-theme="light"] .markdown-body pre { background: #f6f8fa; }
              html[data-theme="light"] .markdown-body :not(pre) > code { background: #f6f8fa; }
              .markdown-body {
                box-sizing: border-box;
                width: 100%;
                padding: 24px;
              }
              .markdown-body h1, .markdown-body h2, .markdown-body h3 {
                line-height: 1.25;
                margin: 1.2em 0 0.5em;
              }
              .markdown-body h1 { font-size: 2em; border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; }
              .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; }
              .markdown-body h3 { font-size: 1.25em; }
              .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body blockquote {
                margin: 0 0 1em;
              }
              .markdown-body pre {
                padding: 12px;
                border-radius: 8px;
                background: #f6f8fa;
                overflow-x: auto;
              }
              .markdown-body code {
                font: 0.9em ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace;
              }
              .markdown-body :not(pre) > code {
                background: #f6f8fa;
                border-radius: 6px;
                padding: 0.1em 0.35em;
              }
              .markdown-body blockquote {
                border-left: 4px solid #d0d7de;
                padding: 0 1em;
                color: #656d76;
              }
              .markdown-body table {
                border-collapse: collapse;
                border-spacing: 0;
                margin: 0 0 1em;
                width: auto;
                overflow: auto;
              }
              .markdown-body table th, .markdown-body table td {
                border: 1px solid #d0d7de;
                padding: 6px 13px;
              }
              .markdown-body table th {
                font-weight: 600;
                background: #f6f8fa;
              }
              .markdown-body table tr:nth-child(2n) {
                background: #f6f8fa;
              }
              @media (prefers-color-scheme: dark) {
                .markdown-body table th, .markdown-body table td { border-color: #444c56; }
                .markdown-body table th { background: #2d2d2d; }
                .markdown-body table tr:nth-child(2n) { background: #2d2d2d; }
              }
              html[data-theme="dark"] .markdown-body table th,
              html[data-theme="dark"] .markdown-body table td { border-color: #444c56; }
              html[data-theme="dark"] .markdown-body table th { background: #2d2d2d; }
              html[data-theme="dark"] .markdown-body table tr:nth-child(2n) { background: #2d2d2d; }
              html[data-theme="light"] .markdown-body table th,
              html[data-theme="light"] .markdown-body table td { border-color: #d0d7de; }
              html[data-theme="light"] .markdown-body table th { background: #f6f8fa; }
              html[data-theme="light"] .markdown-body table tr:nth-child(2n) { background: #f6f8fa; }
              .markdown-body a { color: #0969da; text-decoration: none; }
              .markdown-body a:hover { text-decoration: underline; }
              pre code.language-mermaid { white-space: pre; }
              .mermaid {
                overflow-x: auto;
                background: #f6f8fa;
                border-radius: 10px;
                padding: 10px;
                cursor: pointer;
              }
              .mermaid-overlay {
                position: fixed; top: 0; left: 0; width: 100%; height: 100%;
                background: rgba(30,30,30,0.92); z-index: 9999;
                display: flex; align-items: center; justify-content: center;
                backdrop-filter: blur(6px); -webkit-backdrop-filter: blur(6px);
              }
              .mermaid-overlay-controls {
                position: absolute; top: 16px; right: 16px; z-index: 10001;
                display: flex; gap: 6px; align-items: center;
                background: rgba(0,0,0,0.5); border-radius: 10px; padding: 4px;
              }
              .mermaid-overlay-controls button {
                width: 36px; height: 36px; border-radius: 8px;
                border: 1px solid rgba(255,255,255,0.2); background: rgba(255,255,255,0.12);
                color: #fff; font-size: 20px; cursor: pointer;
                display: flex; align-items: center; justify-content: center;
                transition: background 0.15s;
              }
              .mermaid-overlay-controls button:hover { background: rgba(255,255,255,0.25); }
              .mermaid-overlay-zoom-label {
                color: rgba(255,255,255,0.7); font-size: 13px;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
                min-width: 44px; text-align: center; cursor: pointer;
                padding: 0 4px; border-radius: 6px;
                transition: color 0.15s;
              }
              .mermaid-overlay-zoom-label:hover { color: #fff; }
              .mermaid-overlay-viewport {
                width: 100%; height: 100%; overflow: hidden;
                display: flex; align-items: center; justify-content: center;
              }
              .mermaid-overlay-content {
                background: #ffffff; border-radius: 12px; padding: 24px;
                cursor: grab; user-select: none;
                box-shadow: 0 8px 40px rgba(0,0,0,0.4);
              }
              .mermaid-overlay-content svg { max-width: 85vw; max-height: 80vh; display: block; }
              @media (prefers-color-scheme: dark) {
                .mermaid { background: #2d2d2d; }
                .mermaid-overlay-content { background: #2d2d2d; }
              }
              html[data-theme="dark"] .mermaid { background: #2d2d2d; }
              html[data-theme="dark"] .mermaid-overlay-content { background: #2d2d2d; }
              html[data-theme="light"] .mermaid { background: #f6f8fa; }
              html[data-theme="light"] .mermaid-overlay-content { background: #ffffff; }
              /* Image zoom */
              .markdown-body img { cursor: zoom-in; }
              /* Copy button */
              .copy-btn {
                position: absolute; top: 8px; right: 8px;
                padding: 3px 10px; border-radius: 6px;
                border: 1px solid #d0d7de; background: #f6f8fa;
                color: #656d76; font-size: 12px; cursor: pointer;
                opacity: 0; transition: opacity 0.15s;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              }
              pre:hover .copy-btn { opacity: 1; }
              .copy-btn:hover { background: #e8e8e8; color: #1f2328; }
              @media (prefers-color-scheme: dark) {
                .copy-btn { border-color: #444c56; background: #2d2d2d; color: #999; }
                .copy-btn:hover { background: #3d3d3d; color: #d4d4d4; }
              }
              html[data-theme="dark"] .copy-btn { border-color: #444c56; background: #2d2d2d; color: #999; }
              html[data-theme="dark"] .copy-btn:hover { background: #3d3d3d; color: #d4d4d4; }
              html[data-theme="light"] .copy-btn { border-color: #d0d7de; background: #f6f8fa; color: #656d76; }
              html[data-theme="light"] .copy-btn:hover { background: #e8e8e8; color: #1f2328; }
              /* Reading stats */
              .reading-stats {
                font-size: 13px; color: #656d76;
                padding-bottom: 12px; margin-bottom: 16px;
                border-bottom: 1px solid #d0d7de;
              }
              @media (prefers-color-scheme: dark) {
                .reading-stats { color: #999; border-bottom-color: #444c56; }
              }
              html[data-theme="dark"] .reading-stats { color: #999; border-bottom-color: #444c56; }
              html[data-theme="light"] .reading-stats { color: #656d76; border-bottom-color: #d0d7de; }
              /* Layout */
              #layout { height: 100vh; }
              /* Comment flash animation (in-content highlights) */
              .qmd-comment-flash { animation: comment-flash 1.5s ease; }
              @keyframes comment-flash {
                0%, 100% { background: rgba(255, 213, 79, 0.3); }
                25%, 75% { background: rgba(255, 213, 79, 0.7); }
              }
              html[data-theme="dark"] .markdown-body h1,
              html[data-theme="dark"] .markdown-body h2 { border-bottom-color: #444c56; }
              html[data-theme="dark"] .markdown-body blockquote { border-left-color: #444c56; color: #999; }
              html[data-theme="dark"] .markdown-body a { color: #58a6ff; }
              html[data-theme="light"] .markdown-body h1,
              html[data-theme="light"] .markdown-body h2 { border-bottom-color: #d0d7de; }
              html[data-theme="light"] .markdown-body blockquote { border-left-color: #d0d7de; color: #656d76; }
              html[data-theme="light"] .markdown-body a { color: #0969da; }
              /* Line numbers */
              .code-line { display: block; }
              pre code.has-line-numbers { counter-reset: line; padding-left: 3.5em !important; }
              pre code.has-line-numbers .code-line { position: relative; }
              pre code.has-line-numbers .code-line::before {
                counter-increment: line; content: counter(line);
                position: absolute; left: -3.5em; width: 2.8em;
                text-align: right; color: #9ca3af; font-size: 0.85em;
                user-select: none; -webkit-user-select: none;
              }
              /* Jump to line */
              #jump-bar {
                position: fixed; top: 50%; left: 50%; transform: translate(-50%, -50%);
                background: #fff; border: 1px solid #d0d7de; border-radius: 10px;
                padding: 12px 16px; box-shadow: 0 8px 30px rgba(0,0,0,0.15);
                z-index: 10000; font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              }
              #jump-bar input {
                font-size: 16px; border: 1px solid #d0d7de; border-radius: 6px;
                padding: 6px 10px; width: 120px; outline: none;
              }
              #jump-bar input:focus { border-color: #0969da; }
              .code-line.line-flash { background: rgba(255,220,50,0.35); transition: background 0.3s; }
              @media (prefers-color-scheme: dark) {
                #jump-bar { background: #2d2d2d; border-color: #444c56; }
                #jump-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
                #jump-bar input:focus { border-color: #58a6ff; }
                .code-line.line-flash { background: rgba(255,220,50,0.2); }
              }
              html[data-theme="dark"] #jump-bar { background: #2d2d2d; border-color: #444c56; }
              html[data-theme="dark"] #jump-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
              html[data-theme="dark"] #jump-bar input:focus { border-color: #58a6ff; }
              html[data-theme="dark"] .code-line.line-flash { background: rgba(255,220,50,0.2); }
              /* Find bar */
              #find-bar {
                position: fixed; top: 10px; right: 10px;
                background: #fff; border: 1px solid #d0d7de; border-radius: 10px;
                padding: 6px 10px; box-shadow: 0 4px 20px rgba(0,0,0,0.12);
                z-index: 10000; display: flex; align-items: center; gap: 6px;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              }
              #find-bar input {
                font-size: 14px; border: 1px solid #d0d7de; border-radius: 6px;
                padding: 4px 8px; width: 180px; outline: none;
              }
              #find-bar input:focus { border-color: #0969da; }
              #find-bar button {
                background: none; border: none; font-size: 18px; cursor: pointer;
                color: #656d76; padding: 2px 4px;
              }
              #find-bar button:hover { color: #1f2328; }
              .find-counter { font-size: 12px; color: #656d76; min-width: 36px; text-align: center; }
              .find-highlight { background: #fff3b0; border-radius: 2px; }
              .find-highlight-active { background: #f9a825; border-radius: 2px; }
              @media (prefers-color-scheme: dark) {
                #find-bar { background: #2d2d2d; border-color: #444c56; }
                #find-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
                #find-bar input:focus { border-color: #58a6ff; }
                #find-bar button { color: #999; }
                #find-bar button:hover { color: #d4d4d4; }
                .find-counter { color: #999; }
                .find-highlight { background: #5a4e00; }
                .find-highlight-active { background: #8a6d00; }
              }
              html[data-theme="dark"] #find-bar { background: #2d2d2d; border-color: #444c56; }
              html[data-theme="dark"] #find-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
              html[data-theme="dark"] #find-bar input:focus { border-color: #58a6ff; }
              html[data-theme="dark"] #find-bar button { color: #999; }
              html[data-theme="dark"] #find-bar button:hover { color: #d4d4d4; }
              html[data-theme="dark"] .find-counter { color: #999; }
              html[data-theme="dark"] .find-highlight { background: #5a4e00; }
              html[data-theme="dark"] .find-highlight-active { background: #8a6d00; }
              /* Graphviz dark mode */
              @media (prefers-color-scheme: dark) {
                .graphviz svg polygon[fill="white"],.graphviz svg polygon[fill="#ffffff"] { fill: transparent !important; }
                .graphviz svg text { fill: #c9d1d9 !important; }
                .graphviz svg path,.graphviz svg polygon:not([fill="white"]):not([fill="#ffffff"]) { stroke: #c9d1d9 !important; }
                .graphviz svg [fill="#e8f0fe"],.graphviz svg [fill="#fff3b0"] { fill: #1c2333 !important; }
              }
              html[data-theme="dark"] .graphviz svg polygon[fill="white"],html[data-theme="dark"] .graphviz svg polygon[fill="#ffffff"] { fill: transparent !important; }
              html[data-theme="dark"] .graphviz svg text { fill: #c9d1d9 !important; }
              html[data-theme="dark"] .graphviz svg path,html[data-theme="dark"] .graphviz svg polygon:not([fill="white"]):not([fill="#ffffff"]) { stroke: #c9d1d9 !important; }
              html[data-theme="dark"] .graphviz svg [fill="#e8f0fe"],html[data-theme="dark"] .graphviz svg [fill="#fff3b0"] { fill: #1c2333 !important; }
              /* Graphviz errors */
              .graphviz-error {
                color: #d32f2f; background: #ffebee; border-radius: 8px;
                padding: 12px; margin: 0.5em 0; font-size: 14px;
              }
              @media (prefers-color-scheme: dark) {
                .graphviz-error { background: #3e1e1e; color: #ef9a9a; }
              }
              html[data-theme="dark"] .graphviz-error { background: #3e1e1e; color: #ef9a9a; }
              /* Forced dark highlight.js theme */
              html[data-theme="dark"] .hljs{color:#c9d1d9;background:transparent}
              html[data-theme="dark"] .hljs-doctag,html[data-theme="dark"] .hljs-keyword,html[data-theme="dark"] .hljs-meta .hljs-keyword,html[data-theme="dark"] .hljs-template-tag,html[data-theme="dark"] .hljs-template-variable,html[data-theme="dark"] .hljs-type,html[data-theme="dark"] .hljs-variable.language_{color:#ff7b72}
              html[data-theme="dark"] .hljs-title,html[data-theme="dark"] .hljs-title.class_,html[data-theme="dark"] .hljs-title.class_.inherited__,html[data-theme="dark"] .hljs-title.function_{color:#d2a8ff}
              html[data-theme="dark"] .hljs-attr,html[data-theme="dark"] .hljs-attribute,html[data-theme="dark"] .hljs-literal,html[data-theme="dark"] .hljs-meta,html[data-theme="dark"] .hljs-number,html[data-theme="dark"] .hljs-operator,html[data-theme="dark"] .hljs-variable,html[data-theme="dark"] .hljs-selector-attr,html[data-theme="dark"] .hljs-selector-class,html[data-theme="dark"] .hljs-selector-id{color:#79c0ff}
              html[data-theme="dark"] .hljs-regexp,html[data-theme="dark"] .hljs-string,html[data-theme="dark"] .hljs-meta .hljs-string{color:#a5d6ff}
              html[data-theme="dark"] .hljs-built_in,html[data-theme="dark"] .hljs-symbol{color:#ffa657}
              html[data-theme="dark"] .hljs-comment,html[data-theme="dark"] .hljs-code,html[data-theme="dark"] .hljs-formula{color:#8b949e}
              html[data-theme="dark"] .hljs-name,html[data-theme="dark"] .hljs-quote,html[data-theme="dark"] .hljs-selector-tag,html[data-theme="dark"] .hljs-selector-pseudo{color:#7ee787}
              html[data-theme="dark"] .hljs-subst{color:#c9d1d9}
              html[data-theme="dark"] .hljs-section{color:#1f6feb;font-weight:700}
              html[data-theme="dark"] .hljs-bullet{color:#f2cc60}
              html[data-theme="dark"] .hljs-emphasis{color:#c9d1d9;font-style:italic}
              html[data-theme="dark"] .hljs-strong{color:#c9d1d9;font-weight:700}
              html[data-theme="dark"] .hljs-addition{color:#aff5b4;background-color:#033a16}
              html[data-theme="dark"] .hljs-deletion{color:#ffdcd7;background-color:#67060c}
              /* Forced light highlight.js theme */
              html[data-theme="light"] .hljs{color:#24292e;background:transparent}
              html[data-theme="light"] .hljs-doctag,html[data-theme="light"] .hljs-keyword,html[data-theme="light"] .hljs-meta .hljs-keyword,html[data-theme="light"] .hljs-template-tag,html[data-theme="light"] .hljs-template-variable,html[data-theme="light"] .hljs-type,html[data-theme="light"] .hljs-variable.language_{color:#d73a49}
              html[data-theme="light"] .hljs-title,html[data-theme="light"] .hljs-title.class_,html[data-theme="light"] .hljs-title.class_.inherited__,html[data-theme="light"] .hljs-title.function_{color:#6f42c1}
              html[data-theme="light"] .hljs-attr,html[data-theme="light"] .hljs-attribute,html[data-theme="light"] .hljs-literal,html[data-theme="light"] .hljs-meta,html[data-theme="light"] .hljs-number,html[data-theme="light"] .hljs-operator,html[data-theme="light"] .hljs-variable,html[data-theme="light"] .hljs-selector-attr,html[data-theme="light"] .hljs-selector-class,html[data-theme="light"] .hljs-selector-id{color:#005cc5}
              html[data-theme="light"] .hljs-regexp,html[data-theme="light"] .hljs-string,html[data-theme="light"] .hljs-meta .hljs-string{color:#032f62}
              html[data-theme="light"] .hljs-built_in,html[data-theme="light"] .hljs-symbol{color:#e36209}
              html[data-theme="light"] .hljs-comment,html[data-theme="light"] .hljs-code,html[data-theme="light"] .hljs-formula{color:#6a737d}
              html[data-theme="light"] .hljs-name,html[data-theme="light"] .hljs-quote,html[data-theme="light"] .hljs-selector-tag,html[data-theme="light"] .hljs-selector-pseudo{color:#22863a}
              html[data-theme="light"] .hljs-subst{color:#24292e}
              html[data-theme="light"] .hljs-section{color:#005cc5;font-weight:700}
              html[data-theme="light"] .hljs-bullet{color:#735c0f}
              html[data-theme="light"] .hljs-emphasis{color:#24292e;font-style:italic}
              html[data-theme="light"] .hljs-strong{color:#24292e;font-weight:700}
              html[data-theme="light"] .hljs-addition{color:#22863a;background-color:#f0fff4}
              html[data-theme="light"] .hljs-deletion{color:#b31d28;background-color:#ffeef0}
              /* Speak button */
              #speak-btn {
                position: fixed; bottom: 12px; right: 12px;
                width: 28px; height: 28px; border-radius: 6px;
                border: 1px solid #d0d7de; background: #f6f8fa;
                color: #9ca3af; cursor: pointer; z-index: 9998;
                display: flex; align-items: center; justify-content: center;
                opacity: 0.5; transition: opacity 0.15s, background 0.15s;
                padding: 0;
              }
              #speak-btn:hover { opacity: 1; background: #e8e8e8; color: #656d76; }
              #speak-btn.speaking { opacity: 1; background: #dbeafe; border-color: #0969da; color: #0969da; }
              #speak-btn.paused { opacity: 1; background: #fff3b0; border-color: #f9a825; color: #b45309; }
              @media (prefers-color-scheme: dark) {
                #speak-btn { background: #2d2d2d; border-color: #444c56; color: #666; }
                #speak-btn:hover { background: #3d3d3d; color: #999; }
                #speak-btn.speaking { background: #264f78; border-color: #58a6ff; color: #58a6ff; }
                #speak-btn.paused { background: #5a4e00; border-color: #f9a825; color: #f9a825; }
              }
              html[data-theme="dark"] #speak-btn { background: #2d2d2d; border-color: #444c56; color: #666; }
              html[data-theme="dark"] #speak-btn:hover { background: #3d3d3d; color: #999; }
              html[data-theme="dark"] #speak-btn.speaking { background: #264f78; border-color: #58a6ff; color: #58a6ff; }
              html[data-theme="dark"] #speak-btn.paused { background: #5a4e00; border-color: #f9a825; color: #f9a825; }
              html[data-theme="light"] #speak-btn { background: #f6f8fa; border-color: #d0d7de; color: #9ca3af; }
              html[data-theme="light"] #speak-btn:hover { background: #e8e8e8; color: #656d76; }
              /* Print stylesheet */
              @media print {
                #toc-container, .copy-btn, #speak-btn, #find-bar, #jump-bar,
                .reading-stats, .pres-overlay, .mermaid-overlay { display: none !important; }
                body { background: white !important; color: black !important; }
                .markdown-body { padding: 0 !important; }
                #layout { display: block !important; height: auto !important; }
                h1, h2, h3, h4, h5, h6 { page-break-after: avoid; }
                pre, table, blockquote, img { page-break-inside: avoid; }
                a[href]::after { content: ' (' attr(href) ')'; font-size: 0.85em; color: #666; }
                a[href^="#"]::after { content: ''; }
                pre { border: 1px solid #ccc !important; }
              }
              /* Task lists */
              .markdown-body li:has(> input[type="checkbox"]) { list-style: none; margin-left: -1.5em; }
              .markdown-body input[type="checkbox"] {
                margin-right: 0.4em; vertical-align: middle;
                width: 1em; height: 1em; accent-color: #0969da;
              }
              /* Heading anchor links */
              .heading-anchor {
                color: #d0d7de; text-decoration: none; font-weight: 400;
                padding-right: 0.3em; opacity: 0; transition: opacity 0.15s;
              }
              .markdown-body h1:hover .heading-anchor,
              .markdown-body h2:hover .heading-anchor,
              .markdown-body h3:hover .heading-anchor,
              .markdown-body h4:hover .heading-anchor,
              .markdown-body h5:hover .heading-anchor,
              .markdown-body h6:hover .heading-anchor { opacity: 1; }
              .heading-anchor:hover { color: #0969da; text-decoration: none; }
              @media (prefers-color-scheme: dark) {
                .heading-anchor { color: #444c56; }
                .heading-anchor:hover { color: #58a6ff; }
              }
              html[data-theme="dark"] .heading-anchor { color: #444c56; }
              html[data-theme="dark"] .heading-anchor:hover { color: #58a6ff; }
              /* Footnotes */
              .footnote-ref a {
                color: #0969da; text-decoration: none; font-size: 0.85em;
                padding: 0 2px;
              }
              .footnote-ref a:hover { text-decoration: underline; }
              .footnotes { margin-top: 2em; }
              .footnotes hr { border: none; border-top: 1px solid #d0d7de; margin-bottom: 1em; }
              .footnotes ol { font-size: 0.9em; color: #656d76; }
              .footnote-backref { text-decoration: none; margin-left: 4px; }
              @media (prefers-color-scheme: dark) {
                .footnotes hr { border-top-color: #444c56; }
                .footnotes ol { color: #999; }
                .footnote-ref a { color: #58a6ff; }
              }
              html[data-theme="dark"] .footnotes hr { border-top-color: #444c56; }
              html[data-theme="dark"] .footnotes ol { color: #999; }
              html[data-theme="dark"] .footnote-ref a { color: #58a6ff; }
              /* Frontmatter banner */
              .frontmatter-banner {
                padding: 16px 0; margin-bottom: 16px;
                border-bottom: 1px solid #d0d7de;
              }
              .frontmatter-title { font-size: 0.9em; font-weight: 600; color: #656d76; margin-bottom: 4px; }
              .frontmatter-meta { font-size: 0.8em; color: #999; margin-bottom: 8px; }
              .frontmatter-tags { display: flex; gap: 6px; flex-wrap: wrap; }
              .frontmatter-tag {
                font-size: 0.75em; padding: 2px 8px; border-radius: 12px;
                background: #dbeafe; color: #1e40af;
              }
              @media (prefers-color-scheme: dark) {
                .frontmatter-banner { border-bottom-color: #444c56; }
                .frontmatter-title { color: #999; }
                .frontmatter-meta { color: #666; }
                .frontmatter-tag { background: #1e3a5f; color: #93c5fd; }
              }
              html[data-theme="dark"] .frontmatter-banner { border-bottom-color: #444c56; }
              html[data-theme="dark"] .frontmatter-title { color: #999; }
              html[data-theme="dark"] .frontmatter-tag { background: #1e3a5f; color: #93c5fd; }
              /* Presentation mode */
              .pres-overlay {
                position: fixed; top: 0; left: 0; width: 100%; height: 100%;
                background: #fff; z-index: 10000;
                display: flex; align-items: center; justify-content: center;
              }
              .pres-content {
                max-width: 80%; max-height: 80%;
                font-size: 1.5em; overflow: auto;
                padding: 40px;
              }
              /* Comment annotations */
              .qmd-comment {
                background: rgba(255, 213, 79, 0.3);
                border-bottom: 2px solid rgba(255, 179, 0, 0.6);
                cursor: pointer;
                position: relative;
              }
              .qmd-comment:hover {
                background: rgba(255, 213, 79, 0.5);
              }
              .qmd-comment-tooltip {
                position: absolute;
                bottom: calc(100% + 4px);
                left: 0;
                background: #fefce8;
                border: 1px solid #d4a017;
                border-radius: 6px;
                padding: 6px 10px;
                font-size: 13px;
                max-width: 320px;
                white-space: pre-wrap;
                z-index: 10000;
                box-shadow: 0 2px 8px rgba(0,0,0,0.15);
                color: #333;
                pointer-events: none;
              }
              @media (prefers-color-scheme: dark) {
                .qmd-comment {
                  background: rgba(255, 179, 0, 0.2);
                  border-bottom-color: rgba(255, 179, 0, 0.4);
                }
                .qmd-comment:hover {
                  background: rgba(255, 179, 0, 0.35);
                }
                .qmd-comment-tooltip {
                  background: #3a3000;
                  border-color: #a08000;
                  color: #e0d8c0;
                }
              }
              html[data-theme="dark"] .qmd-comment {
                background: rgba(255, 179, 0, 0.2);
                border-bottom-color: rgba(255, 179, 0, 0.4);
              }
              html[data-theme="dark"] .qmd-comment:hover {
                background: rgba(255, 179, 0, 0.35);
              }
              html[data-theme="dark"] .qmd-comment-tooltip {
                background: #3a3000;
                border-color: #a08000;
                color: #e0d8c0;
              }
              .pres-counter {
                position: fixed; bottom: 20px; right: 20px;
                font-size: 14px; color: #999;
                font-family: -apple-system, BlinkMacSystemFont, sans-serif;
              }
              .pres-close {
                position: fixed; top: 16px; right: 16px;
                background: none; border: none; font-size: 28px;
                cursor: pointer; color: #999; z-index: 10001;
              }
              .pres-close:hover { color: #333; }
              @media (prefers-color-scheme: dark) {
                .pres-overlay { background: #1e1e1e; color: #d4d4d4; }
                .pres-close:hover { color: #d4d4d4; }
              }
              html[data-theme="dark"] .pres-overlay { background: #1e1e1e; color: #d4d4d4; }
              html[data-theme="dark"] .pres-close:hover { color: #d4d4d4; }
            </style>
          </head>
          <body>
            <div id="layout">\(sidebarsMarkup)<article class="markdown-body">\(body)</article></div>
          </body>
        </html>
        """
    }
}
