import Foundation
import Markdown
import QuickLookUI
import UniformTypeIdentifiers

final class PreviewViewController: NSViewController, QLPreviewingController {
    private static let mermaidJS: String = {
        guard let url = Bundle.main.url(forResource: "mermaid.min", withExtension: "js", subdirectory: "Resources"),
              let js = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return js
    }()

    private static func loadResource(_ name: String, ext: String, subdirectory: String = "Resources") -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: subdirectory),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }

    private static func loadScript(_ name: String) -> String {
        loadResource(name, ext: "js", subdirectory: "Resources/scripts")
    }

    private static let highlightJS: String = loadResource("highlight.min", ext: "js")
    private static let jsYamlJS: String = loadResource("js-yaml.min", ext: "js")
    private static let katexJS: String = loadResource("katex.min", ext: "js")
    private static let autoRenderJS: String = loadResource("auto-render.min", ext: "js")
    private static let graphvizJS: String = loadResource("viz-standalone", ext: "js")
    private static let highlightGitHubCSS: String = loadResource("highlight-github", ext: "css")
    private static let highlightGitHubDarkCSS: String = loadResource("highlight-github-dark", ext: "css")
    private static let previewCSS: String = loadResource("preview", ext: "css", subdirectory: "Resources/styles")
    private static let extensionTemplate: String = loadResource("preview-extension", ext: "html", subdirectory: "Resources/templates")

    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

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
        if let content = try? String(contentsOf: url, encoding: .utf8) {
            return content
        }
        let data = try Data(contentsOf: url)
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
            let processed = Self.preprocessComments(body)
            var html = HTMLFormatter.format(processed)
            if let fm = frontmatter {
                let escaped = fm
                    .replacingOccurrences(of: "&", with: "&amp;")
                    .replacingOccurrences(of: "<", with: "&lt;")
                    .replacingOccurrences(of: ">", with: "&gt;")
                html = "<div id=\"frontmatter-data\" style=\"display:none\">\(escaped)</div>\n" + html
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

    func preparePreviewOfFile(at url: URL, completionHandler handler: @escaping (Error?) -> Void) {
        do {
            let result = try Self.htmlBody(for: url)
            let html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)

            let tempDir = FileManager.default.temporaryDirectory
            let tempFile = tempDir.appendingPathComponent(UUID().uuidString + ".html")
            try html.write(to: tempFile, atomically: true, encoding: .utf8)

            handler(nil)
        } catch {
            handler(error)
        }
    }

    func providePreview(for request: QLFilePreviewRequest) async throws -> QLPreviewReply {
        let result = try Self.htmlBody(for: request.fileURL)
        let html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)
        let data = Data(html.utf8)

        return QLPreviewReply(
            dataOfContentType: UTType.html,
            contentSize: CGSize(width: 900, height: 800)
        ) { _ in
            return data
        }
    }

    // MARK: - Comment Pre-processing

    /// Replace comment markers with styled HTML spans (mirrors MarkdownDocumentModel.preprocessComments).
    private static func preprocessComments(_ markdown: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: #"<!--\s*COMMENT:\s*(.*?)\s*-->([\s\S]*?)<!--\s*/COMMENT\s*-->"#,
            options: []
        ) else { return markdown }
        let nsMarkdown = markdown as NSString
        var result = markdown
        let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: nsMarkdown.length))
        for match in matches.reversed() {
            let commentText = nsMarkdown.substring(with: match.range(at: 1))
            let annotatedText = nsMarkdown.substring(with: match.range(at: 2))
            let escapedComment = commentText
                .replacingOccurrences(of: "&", with: "&amp;")
                .replacingOccurrences(of: "\"", with: "&quot;")
                .replacingOccurrences(of: "<", with: "&lt;")
                .replacingOccurrences(of: ">", with: "&gt;")
            let replacement = "<mark class=\"qmd-comment\" data-comment=\"\(escapedComment)\" title=\"\(escapedComment)\">\(annotatedText)</mark>"
            let range = Range(match.range, in: result)!
            result.replaceSubrange(range, with: replacement)
        }
        return result
    }

    // MARK: - Scripts loaded from Resources/scripts/

    private static let utilsScript: String = loadScript("utils")
    private static let emojiScript: String = loadScript("emoji")
    private static let footnotesScript: String = loadScript("footnotes")
    private static let frontmatterScript: String = loadScript("frontmatter")
    private static let anchorLinksScript: String = loadScript("anchor-links")
    private static let zoomOverlayScript: String = loadScript("zoom-overlay")
    private static let readingStatsScript: String = loadScript("reading-stats")
    private static let fontSizeScript: String = loadScript("font-size")
    private static let jumpToLineScript: String = loadScript("jump-to-line")
    private static let findScript: String = loadScript("find")
    private static let lineNumbersScript: String = loadScript("line-numbers")
    private static let copyButtonScript: String = loadScript("copy-button")
    private static let highlightRenderScript: String = loadScript("highlight-render")
    private static let mermaidRenderScript: String = loadScript("mermaid-render")
    private static let graphvizRenderScript: String = loadScript("graphviz-render")

    // MARK: - HTML Generation

    private static func wrapHTML(_ body: String, isMarkdown: Bool) -> String {
        let highlightBlock: String
        if !highlightJS.isEmpty {
            highlightBlock = """
                <script>\(highlightJS)</script>
                <script>\(jsYamlJS)</script>
                <script>\(Self.highlightRenderScript)</script>
            """
        } else {
            highlightBlock = ""
        }

        let lineNumbersBlock = "<script>\(Self.lineNumbersScript)</script>"

        let copyButtonBlock = "<script>\(Self.copyButtonScript)</script>"

        let katexBlock: String
        if !katexJS.isEmpty && !autoRenderJS.isEmpty {
            katexBlock = """
                <script>\(katexJS)</script>
                <script>\(autoRenderJS)</script>
                <script>
                (function() {
                  if (!window.renderMathInElement) return;
                  try {
                    renderMathInElement(document.body, {
                      output: 'mathml',
                      delimiters: [
                        { left: '$$', right: '$$', display: true },
                        { left: '$', right: '$', display: false },
                        { left: '\\\\(', right: '\\\\)', display: false },
                        { left: '\\\\[', right: '\\\\]', display: true }
                      ],
                      throwOnError: false
                    });
                  } catch(e) {}
                })();
                </script>
            """
        } else {
            katexBlock = ""
        }

        let mermaidBlock = mermaidJS.isEmpty ? "" : """
            <script>\(mermaidJS)</script>
            <script>\(Self.mermaidRenderScript)</script>
        """

        let graphvizBlock = graphvizJS.isEmpty ? "" : """
            <script>\(graphvizJS)</script>
            <script>\(Self.graphvizRenderScript)</script>
        """

        let zoomOverlayBlock = "<script>\(Self.zoomOverlayScript)</script>"

        let readingStatsBlock = "<script>\(Self.readingStatsScript)</script>"

        let fontSizeBlock = "<script>\(Self.fontSizeScript)</script>"

        let jumpToLineBlock = "<script>\(Self.jumpToLineScript)</script>"

        let findBlock = "<script>\(Self.findScript)</script>"

        let emojiBlock = """
            <script>
            \(emojiScript)
            </script>
        """

        let footnotesBlock = """
            <script>
            \(footnotesScript)
            </script>
        """

        let frontmatterBlock = """
            <script>
            \(frontmatterScript)
            </script>
        """

        let anchorLinksBlock = """
            <script>
            \(anchorLinksScript)
            </script>
        """

        let utilsBlock = "<script>\(Self.utilsScript)</script>"

        let scripts = [
            utilsBlock, highlightBlock, lineNumbersBlock, copyButtonBlock, katexBlock,
            mermaidBlock, graphvizBlock, zoomOverlayBlock, readingStatsBlock,
            fontSizeBlock, jumpToLineBlock, findBlock, emojiBlock,
            footnotesBlock, frontmatterBlock, anchorLinksBlock,
        ].joined(separator: "\n")

        let fileType = isMarkdown ? "markdown" : "code"
        return extensionTemplate
            .replacingOccurrences(of: "{{FILE_TYPE}}", with: fileType)
            .replacingOccurrences(of: "{{HIGHLIGHT_CSS}}", with: highlightGitHubCSS)
            .replacingOccurrences(of: "{{HIGHLIGHT_DARK_CSS}}", with: highlightGitHubDarkCSS)
            .replacingOccurrences(of: "{{PREVIEW_CSS}}", with: previewCSS)
            .replacingOccurrences(of: "{{BODY}}", with: body)
            .replacingOccurrences(of: "{{SCRIPTS}}", with: scripts)
    }
}
