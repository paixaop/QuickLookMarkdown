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

    private static func loadResource(_ name: String, ext: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }

    private static func loadScript(_ name: String) -> String {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js", subdirectory: "Resources/scripts"),
              let content = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return content
    }

    private static let highlightJS: String = loadResource("highlight.min", ext: "js")
    private static let jsYamlJS: String = loadResource("js-yaml.min", ext: "js")
    private static let katexJS: String = loadResource("katex.min", ext: "js")
    private static let autoRenderJS: String = loadResource("auto-render.min", ext: "js")
    private static let graphvizJS: String = loadResource("viz-standalone", ext: "js")
    private static let highlightGitHubCSS: String = loadResource("highlight-github", ext: "css")
    private static let highlightGitHubDarkCSS: String = loadResource("highlight-github-dark", ext: "css")

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

    // MARK: - HTML Generation

    private static func wrapHTML(_ body: String, isMarkdown: Bool) -> String {
        let highlightBlock: String
        if !highlightJS.isEmpty {
            highlightBlock = """
                <script>\(highlightJS)</script>
                <script>\(jsYamlJS)</script>
                <script>
                (function() {
                  document.querySelectorAll('pre > code.language-json').forEach(function(code) {
                    try {
                      var obj = JSON.parse(code.textContent);
                      code.textContent = JSON.stringify(obj, null, 2);
                    } catch(e) {}
                  });
                  if (window.jsyaml) {
                    document.querySelectorAll('pre > code.language-yaml, pre > code.language-yml').forEach(function(code) {
                      try {
                        var obj = jsyaml.load(code.textContent);
                        code.textContent = jsyaml.dump(obj, { indent: 2, lineWidth: -1 });
                      } catch(e) {}
                    });
                  }
                  if (window.hljs) {
                    document.querySelectorAll('pre code').forEach(function(block) {
                      if (!block.classList.contains('language-mermaid')) {
                        hljs.highlightElement(block);
                      }
                    });
                  }
                })();
                </script>
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
            <script>
              if (window.mermaid) {
                var dt = document.documentElement.getAttribute('data-theme');
                var mermaidTheme;
                if (dt === 'dark') { mermaidTheme = 'dark'; }
                else if (dt === 'light') { mermaidTheme = 'neutral'; }
                else { mermaidTheme = window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'neutral'; }
                mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: mermaidTheme });
                document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
                  var graphDefinition = code.textContent || '';
                  var host = document.createElement('div');
                  host.className = 'mermaid';
                  var pre = code.closest('pre');
                  if (pre) {
                    pre.replaceWith(host);
                    try {
                      mermaid.render('mermaid-' + idx + '-' + Date.now(), graphDefinition)
                        .then(function(result) { host.innerHTML = result.svg; })
                        .catch(function() { host.textContent = 'Mermaid render error'; });
                    } catch(e) { host.textContent = 'Mermaid render error'; }
                  }
                });
              }
            </script>
        """

        let graphvizBlock = graphvizJS.isEmpty ? "" : """
            <script>\(graphvizJS)</script>
            <script>
            (function() {
              if (typeof Viz === 'undefined') return;
              var blocks = document.querySelectorAll('pre > code.language-dot, pre > code.language-graphviz');
              if (blocks.length === 0) return;
              Viz.instance().then(function(viz) {
                blocks.forEach(function(code) {
                  var dot = code.textContent || '';
                  var pre = code.closest('pre');
                  if (!pre) return;
                  try {
                    var svg = viz.renderSVGElement(dot);
                    var host = document.createElement('div');
                    host.className = 'graphviz mermaid';
                    host.appendChild(svg);
                    pre.replaceWith(host);
                  } catch(e) {
                    var errDiv = document.createElement('div');
                    errDiv.className = 'graphviz-error';
                    errDiv.textContent = 'Graphviz error: ' + e.message;
                    pre.replaceWith(errDiv);
                  }
                });
              });
            })();
            </script>
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
              html[data-theme="dark"] { color-scheme: dark; }
              html[data-theme="dark"] body { background: #1e1e1e; color: #d4d4d4; }
              html[data-theme="dark"] .markdown-body pre { background: #2d2d2d; }
              html[data-theme="dark"] .markdown-body :not(pre) > code { background: #2d2d2d; }
              html[data-theme="light"] { color-scheme: light; }
              html[data-theme="light"] body { background: #ffffff; color: #1f2328; }
              html[data-theme="light"] .markdown-body pre { background: #f6f8fa; }
              html[data-theme="light"] .markdown-body :not(pre) > code { background: #f6f8fa; }
              .markdown-body {
                box-sizing: border-box; width: 100%; padding: 24px;
              }
              .markdown-body h1, .markdown-body h2, .markdown-body h3 {
                line-height: 1.25; margin: 1.2em 0 0.5em;
              }
              .markdown-body h1 { font-size: 2em; border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; }
              .markdown-body h2 { font-size: 1.5em; border-bottom: 1px solid #d0d7de; padding-bottom: 0.3em; }
              .markdown-body h3 { font-size: 1.25em; }
              .markdown-body p, .markdown-body ul, .markdown-body ol, .markdown-body blockquote { margin: 0 0 1em; }
              .markdown-body pre { padding: 12px; border-radius: 8px; background: #f6f8fa; overflow-x: auto; }
              .markdown-body code { font: 0.9em ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; }
              .markdown-body :not(pre) > code { background: #f6f8fa; border-radius: 6px; padding: 0.1em 0.35em; }
              .markdown-body blockquote { border-left: 4px solid #d0d7de; padding: 0 1em; color: #656d76; }
              .markdown-body table { border-collapse: collapse; border-spacing: 0; margin: 0 0 1em; width: auto; overflow: auto; }
              .markdown-body table th, .markdown-body table td { border: 1px solid #d0d7de; padding: 6px 13px; }
              .markdown-body table th { font-weight: 600; background: #f6f8fa; }
              .markdown-body table tr:nth-child(2n) { background: #f6f8fa; }
              @media (prefers-color-scheme: dark) {
                .markdown-body table th, .markdown-body table td { border-color: #444c56; }
                .markdown-body table th { background: #2d2d2d; }
                .markdown-body table tr:nth-child(2n) { background: #2d2d2d; }
              }
              html[data-theme="dark"] .markdown-body table th,
              html[data-theme="dark"] .markdown-body table td { border-color: #444c56; }
              html[data-theme="dark"] .markdown-body table th { background: #2d2d2d; }
              html[data-theme="dark"] .markdown-body table tr:nth-child(2n) { background: #2d2d2d; }
              .markdown-body a { color: #0969da; text-decoration: none; }
              .markdown-body a:hover { text-decoration: underline; }
              html[data-theme="dark"] .markdown-body h1,
              html[data-theme="dark"] .markdown-body h2 { border-bottom-color: #444c56; }
              html[data-theme="dark"] .markdown-body blockquote { border-left-color: #444c56; color: #999; }
              html[data-theme="dark"] .markdown-body a { color: #58a6ff; }
              pre code.language-mermaid { white-space: pre; }
              .mermaid { overflow-x: auto; background: #f6f8fa; border-radius: 10px; padding: 10px; cursor: pointer; }
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
                padding: 0 4px; border-radius: 6px; transition: color 0.15s;
              }
              .mermaid-overlay-zoom-label:hover { color: #fff; }
              .mermaid-overlay-viewport { width: 100%; height: 100%; overflow: hidden; display: flex; align-items: center; justify-content: center; }
              .mermaid-overlay-content {
                background: #ffffff; border-radius: 12px; padding: 24px;
                cursor: grab; user-select: none; box-shadow: 0 8px 40px rgba(0,0,0,0.4);
              }
              .mermaid-overlay-content svg { max-width: 85vw; max-height: 80vh; display: block; }
              @media (prefers-color-scheme: dark) {
                .mermaid { background: #2d2d2d; }
                .mermaid-overlay-content { background: #2d2d2d; }
              }
              html[data-theme="dark"] .mermaid { background: #2d2d2d; }
              html[data-theme="dark"] .mermaid-overlay-content { background: #2d2d2d; }
              .markdown-body img { cursor: zoom-in; }
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
              .reading-stats {
                font-size: 13px; color: #656d76;
                padding-bottom: 12px; margin-bottom: 16px; border-bottom: 1px solid #d0d7de;
              }
              @media (prefers-color-scheme: dark) { .reading-stats { color: #999; border-bottom-color: #444c56; } }
              html[data-theme="dark"] .reading-stats { color: #999; border-bottom-color: #444c56; }
              #layout { height: 100vh; }
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
              #find-bar button { background: none; border: none; font-size: 18px; cursor: pointer; color: #656d76; padding: 2px 4px; }
              #find-bar button:hover { color: #1f2328; }
              .find-counter { font-size: 12px; color: #656d76; min-width: 36px; text-align: center; }
              .find-highlight { background: #fff3b0; border-radius: 2px; }
              .find-highlight-active { background: #f9a825; border-radius: 2px; }
              @media (prefers-color-scheme: dark) {
                #find-bar { background: #2d2d2d; border-color: #444c56; }
                #find-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
                #find-bar input:focus { border-color: #58a6ff; }
                #find-bar button { color: #999; } #find-bar button:hover { color: #d4d4d4; }
                .find-counter { color: #999; }
                .find-highlight { background: #5a4e00; }
                .find-highlight-active { background: #8a6d00; }
              }
              html[data-theme="dark"] #find-bar { background: #2d2d2d; border-color: #444c56; }
              html[data-theme="dark"] #find-bar input { background: #1e1e1e; border-color: #444c56; color: #d4d4d4; }
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
              .graphviz-error { color: #d32f2f; background: #ffebee; border-radius: 8px; padding: 12px; margin: 0.5em 0; font-size: 14px; }
              @media (prefers-color-scheme: dark) { .graphviz-error { background: #3e1e1e; color: #ef9a9a; } }
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
              /* Print stylesheet */
              @media print {
                .copy-btn, #find-bar, #jump-bar,
                .reading-stats, .mermaid-overlay { display: none !important; }
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
                color: #0969da; text-decoration: none; font-size: 0.85em; padding: 0 2px;
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
                padding: 16px 0; margin-bottom: 16px; border-bottom: 1px solid #d0d7de;
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
                .frontmatter-tag { background: #1e3a5f; color: #93c5fd; }
              }
              html[data-theme="dark"] .frontmatter-banner { border-bottom-color: #444c56; }
              html[data-theme="dark"] .frontmatter-title { color: #999; }
              html[data-theme="dark"] .frontmatter-tag { background: #1e3a5f; color: #93c5fd; }
              /* Comment annotations */
              .qmd-comment {
                background: rgba(255, 213, 79, 0.3);
                border-bottom: 2px solid rgba(255, 179, 0, 0.6);
              }
              @media (prefers-color-scheme: dark) {
                .qmd-comment {
                  background: rgba(255, 179, 0, 0.2);
                  border-bottom-color: rgba(255, 179, 0, 0.4);
                }
              }
              html[data-theme="dark"] .qmd-comment {
                background: rgba(255, 179, 0, 0.2);
                border-bottom-color: rgba(255, 179, 0, 0.4);
              }
            </style>
          </head>
          <body>
            <div id="layout"><article class="markdown-body">\(body)</article></div>
            \(highlightBlock)
            \(lineNumbersBlock)
            \(copyButtonBlock)
            \(katexBlock)
            \(mermaidBlock)
            \(graphvizBlock)
            \(zoomOverlayBlock)
            \(readingStatsBlock)
            \(fontSizeBlock)
            \(jumpToLineBlock)
            \(findBlock)
            \(emojiBlock)
            \(footnotesBlock)
            \(frontmatterBlock)
            \(anchorLinksBlock)
          </body>
        </html>
        """
    }
}
