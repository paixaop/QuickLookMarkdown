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

    private static let logFormatter = ISO8601DateFormatter()

    static func log(_ message: String) {
        let timestamp = logFormatter.string(from: Date())
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

    private static func htmlBody(for url: URL) throws -> (html: String, isMarkdown: Bool, content: String) {
        let content = try readFileContent(from: url)
        let result = htmlBody(content: content, extension: url.pathExtension.lowercased())
        return (result.html, result.isMarkdown, content)
    }

    private static func htmlBody(content: String, extension ext: String) -> (html: String, isMarkdown: Bool) {
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

    static func scanDirectoryForMarkdown(_ dirURL: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let items = try? fm.contentsOfDirectory(
            at: dirURL, includingPropertiesForKeys: [.isDirectoryKey, .nameKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        let sorted = items.sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var results: [FileNode] = []
        for item in sorted {
            let isDir = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let children = scanDirectoryForMarkdown(item)
                if !children.isEmpty {
                    results.append(FileNode(id: "dir:\(item.path)", name: item.lastPathComponent, isDirectory: true, path: item.path, children: children))
                }
            } else if markdownExtensions.contains(item.pathExtension.lowercased()) {
                results.append(FileNode(id: item.path, name: item.lastPathComponent, isDirectory: false, path: item.path, children: []))
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
            let nodes = Self.scanDirectoryForMarkdown(dirURL)
            DispatchQueue.main.async {
                self?.fileTree = nodes
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
        let result = Self.htmlBody(content: rawContent, extension: ext)
        frontmatterLineCount = SourceMappedHTMLFormatter.lastFrontmatterLineCount
        html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)
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
            Self.log("Read \(result.content.count) chars from file")
            Self.log("Produced \(result.html.count) chars of HTML")
            rawContent = result.content
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

    static let utilsScript = loadScript("utils")

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
        let result = try htmlBody(for: url)
        return (result.html, result.isMarkdown)
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

    static let previewCSS: String = loadResource("preview", ext: "css", subdirectory: "styles", label: "preview CSS")
    private static let appTemplate: String = loadResource("preview-app", ext: "html", subdirectory: "templates", label: "app HTML template")

    private static func wrapHTML(_ body: String, isMarkdown: Bool) -> String {
        let fileType = isMarkdown ? "markdown" : "code"
        return appTemplate
            .replacingOccurrences(of: "{{FILE_TYPE}}", with: fileType)
            .replacingOccurrences(of: "{{HIGHLIGHT_CSS}}", with: highlightGitHubCSS)
            .replacingOccurrences(of: "{{HIGHLIGHT_DARK_CSS}}", with: highlightGitHubDarkCSS)
            .replacingOccurrences(of: "{{PREVIEW_CSS}}", with: previewCSS)
            .replacingOccurrences(of: "{{BODY}}", with: body)
    }
}
