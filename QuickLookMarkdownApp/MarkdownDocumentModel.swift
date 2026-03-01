import Foundation
import Markdown
import os

private let logger = Logger(subsystem: "com.pedro.QuickLookMarkdownApp", category: "MarkdownModel")

final class MarkdownDocumentModel: ObservableObject {
    @Published var html: String?
    @Published var baseURL: URL?
    @Published var fileName: String?
    @Published var errorMessage: String?

    static let logFileURL: URL = {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("QuickLookMarkdown.log")
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
    ]

    private static func htmlBody(for url: URL) throws -> String {
        let content = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()

        if markdownExtensions.contains(ext) {
            return HTMLFormatter.format(content)
        }

        let lang = extensionToLanguage[ext] ?? ""
        let escaped = content
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
        let langClass = lang.isEmpty ? "" : " class=\"language-\(lang)\""
        return "<pre><code\(langClass)>\(escaped)</code></pre>"
    }

    func load(from url: URL) {
        Self.log("load(from: \(url.path))")
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            Self.log("Read \(content.count) chars from file")
            let htmlBody = try Self.htmlBody(for: url)
            Self.log("Produced \(htmlBody.count) chars of HTML")
            html = Self.wrapHTML(htmlBody)
            Self.log("Wrapped HTML total: \(html?.count ?? 0) chars")
            baseURL = url.deletingLastPathComponent()
            fileName = url.lastPathComponent
            errorMessage = nil
            Self.log("Model updated successfully, fileName=\(url.lastPathComponent)")
        } catch {
            Self.log("ERROR: \(error.localizedDescription)")
            html = nil
            baseURL = nil
            fileName = url.lastPathComponent
            errorMessage = "Could not render \(url.lastPathComponent): \(error.localizedDescription)"
        }
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

    static let highlightGitHubCSS: String = {
        loadResource("highlight-github", ext: "css", label: "highlight GitHub CSS")
    }()

    static let highlightGitHubDarkCSS: String = {
        loadResource("highlight-github-dark", ext: "css", label: "highlight GitHub Dark CSS")
    }()

    private static func loadResource(_ name: String, ext: String, label: String) -> String {
        log("Loading \(label) from bundle...")
        if let url = Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Resources"),
           let content = try? String(contentsOf: url, encoding: .utf8) {
            log("Loaded \(label): \(content.count) chars")
            return content
        }
        log("ERROR: \(label) not found in bundle")
        return ""
    }

    static let mermaidRenderScript = """
    if (window.mermaid) {
      mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'default' });
      document.querySelectorAll('pre > code.language-mermaid').forEach(function(code, idx) {
        var graphDefinition = code.textContent || '';
        var host = document.createElement('div');
        host.className = 'mermaid';
        var pre = code.closest('pre');
        if (pre) {
          pre.replaceWith(host);
          mermaid.render('mermaid-' + idx + '-' + Date.now(), graphDefinition)
            .then(function(result) { host.innerHTML = result.svg; })
            .catch(function() { host.textContent = 'Mermaid render error'; });
        }
      });
    }
    """

    static let highlightRenderScript = """
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
    """

    private static func wrapHTML(_ body: String) -> String {
        """
        <!doctype html>
        <html>
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
              .markdown-body a { color: #0969da; text-decoration: none; }
              .markdown-body a:hover { text-decoration: underline; }
              pre code.language-mermaid { white-space: pre; }
              .mermaid {
                overflow-x: auto;
                background: #f6f8fa;
                border-radius: 10px;
                padding: 10px;
              }
            </style>
          </head>
          <body>
            <article class="markdown-body">\(body)</article>
          </body>
        </html>
        """
    }
}
