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

    private static let highlightJS: String = loadResource("highlight.min", ext: "js")
    private static let jsYamlJS: String = loadResource("js-yaml.min", ext: "js")
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
    ]

    private static func htmlBody(for url: URL) throws -> (html: String, isMarkdown: Bool) {
        let content = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()

        if markdownExtensions.contains(ext) {
            return (HTMLFormatter.format(content), true)
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

    private static let tocScript = """
    (function() {
      var container = document.getElementById('toc-container');
      if (!container) return;
      var content = document.querySelector('.markdown-body');
      if (!content) return;
      var headings = content.querySelectorAll('h1, h2, h3, h4, h5, h6');
      if (headings.length === 0) {
        container.classList.add('hidden');
        layout.classList.remove('has-toc');
        return;
      }
      var layout = document.getElementById('layout');
      if (!layout) return;
      layout.classList.add('has-toc');
      var slugCounts = {};
      headings.forEach(function(h) {
        var text = h.textContent || '';
        var slug = text.toLowerCase().trim()
          .replace(/[^\\w\\s-]/g, '').replace(/[\\s]+/g, '-').replace(/^-+|-+$/g, '');
        if (!slug) slug = 'heading';
        if (slugCounts[slug] != null) { slugCounts[slug]++; slug += '-' + slugCounts[slug]; }
        else { slugCounts[slug] = 0; }
        h.id = slug;
      });
      var tree = document.getElementById('toc-tree');
      var items = [];
      headings.forEach(function(h) {
        var level = parseInt(h.tagName.charAt(1));
        items.push({ el: h, level: level });
      });
      items.forEach(function(item, idx) {
        var minLevel = items[0].level;
        var indent = item.level - minLevel;
        var hasChildren = (idx + 1 < items.length && items[idx + 1].level > item.level);
        var row = document.createElement('div');
        row.className = 'toc-item';
        row.setAttribute('data-heading-id', item.el.id);
        row.style.paddingLeft = (8 + indent * 14) + 'px';
        var toggle = document.createElement('span');
        toggle.className = 'toc-toggle';
        if (hasChildren) {
          toggle.textContent = '\\u25B6';
          toggle.addEventListener('click', function(e) {
            e.stopPropagation();
            row.classList.toggle('collapsed');
            var myLevel = item.level;
            var sibling = row.nextElementSibling;
            while (sibling && sibling.classList.contains('toc-item')) {
              var sibLevel = parseInt(sibling.getAttribute('data-level'));
              if (sibLevel <= myLevel) break;
              sibling.style.display = row.classList.contains('collapsed') ? 'none' : 'flex';
              sibling = sibling.nextElementSibling;
            }
          });
        } else {
          toggle.classList.add('no-children');
        }
        row.appendChild(toggle);
        var label = document.createElement('span');
        label.className = 'toc-label';
        label.textContent = item.el.textContent;
        label.addEventListener('click', function() {
          item.el.scrollIntoView({ behavior: 'smooth' });
        });
        row.appendChild(label);
        row.setAttribute('data-level', item.level);
        tree.appendChild(row);
      });
      var tocItems = tree.querySelectorAll('.toc-item');
      var observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
          if (entry.isIntersecting) {
            tocItems.forEach(function(ti) { ti.classList.remove('active'); });
            var id = entry.target.id;
            var match = tree.querySelector('.toc-item[data-heading-id="' + id + '"]');
            if (match) match.classList.add('active');
          }
        });
      }, { root: content, rootMargin: '0px 0px -70% 0px', threshold: 0.1 });
      headings.forEach(function(h) { observer.observe(h); });
      var toggleBtn = document.getElementById('toc-toggle');
      if (toggleBtn) {
        toggleBtn.addEventListener('click', function() {
          container.classList.toggle('collapsed');
        });
      }
      // Resize handle
      var resizeHandle = document.getElementById('toc-resize');
      if (resizeHandle) {
        resizeHandle.addEventListener('mousedown', function(e) {
          e.preventDefault();
          resizeHandle.classList.add('dragging');
          document.body.classList.add('toc-resizing');
          var startX = e.clientX;
          var startW = container.offsetWidth;
          function onMove(e) {
            var newW = startW + (e.clientX - startX);
            if (newW < 100) newW = 100;
            var maxW = window.innerWidth * 0.5;
            if (newW > maxW) newW = maxW;
            container.style.width = newW + 'px';
          }
          function onUp() {
            resizeHandle.classList.remove('dragging');
            document.body.classList.remove('toc-resizing');
            document.removeEventListener('mousemove', onMove);
            document.removeEventListener('mouseup', onUp);
          }
          document.addEventListener('mousemove', onMove);
          document.addEventListener('mouseup', onUp);
        });
      }
    })();
    """

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

        let mermaidBlock = mermaidJS.isEmpty ? "" : """
            <script>\(mermaidJS)</script>
            <script>
              if (window.mermaid) {
                mermaid.initialize({ startOnLoad: false, securityLevel: 'strict', theme: 'neutral' });
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
            </script>
        """

        let tocMarkup = isMarkdown ? """
            <div id="toc-container">
              <button id="toc-toggle" title="Toggle contents">&#9776;</button>
              <nav id="toc-nav">
                <div id="toc-header">Contents</div>
                <div id="toc-tree"></div>
              </nav>
              <div id="toc-resize"></div>
            </div>
        """ : ""

        let tocBlock = isMarkdown ? "<script>\(tocScript)</script>" : ""

        return """
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
              /* TOC sidebar */
              #layout { height: 100vh; }
              #layout.has-toc { display: flex; overflow: hidden; }
              #layout.has-toc .markdown-body { flex: 1; overflow-y: auto; height: 100vh; }
              #toc-container {
                position: relative;
                width: 220px; min-width: 100px; max-width: 50vw;
                height: 100vh;
                border-right: 1px solid #d0d7de;
                background: #f6f8fa;
                font-size: 13px;
                display: flex; flex-direction: column;
              }
              #toc-container.hidden { display: none; }
              #toc-container.collapsed { width: 36px !important; min-width: 36px; overflow: hidden; }
              #toc-container.collapsed #toc-nav { display: none; }
              #toc-container.collapsed #toc-resize { display: none; }
              #toc-resize {
                position: absolute; top: 0; right: -3px; width: 6px; height: 100%;
                cursor: col-resize; z-index: 10;
              }
              #toc-resize:hover, #toc-resize.dragging { background: rgba(9,105,218,0.3); }
              #toc-toggle {
                background: none; border: none; cursor: pointer;
                font-size: 18px; padding: 6px 8px; text-align: left;
                color: #656d76; flex-shrink: 0;
              }
              #toc-toggle:hover { color: #1f2328; }
              #toc-header {
                font-weight: 600; padding: 4px 10px 8px; font-size: 12px;
                text-transform: uppercase; letter-spacing: 0.5px; color: #656d76;
              }
              #toc-tree { flex: 1; overflow-y: auto; }
              .toc-item {
                display: flex; align-items: center;
                padding: 3px 8px; cursor: pointer;
                border-left: 3px solid transparent;
              }
              .toc-item:hover { background: #e8e8e8; }
              .toc-item.active { border-left-color: #0969da; background: #dbeafe; }
              .toc-toggle {
                font-size: 8px; width: 14px; text-align: center;
                flex-shrink: 0; transition: transform 0.15s; cursor: pointer;
                user-select: none; color: #656d76;
              }
              .toc-toggle.no-children { visibility: hidden; }
              .toc-item.collapsed .toc-toggle { transform: rotate(0deg); }
              .toc-item:not(.collapsed) .toc-toggle:not(.no-children) { transform: rotate(90deg); }
              .toc-label {
                overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
                flex: 1; padding-left: 4px;
              }
              body.toc-resizing { cursor: col-resize; user-select: none; }
              @media (prefers-color-scheme: dark) {
                #toc-container { background: #252526; border-right-color: #444c56; }
                #toc-toggle { color: #999; }
                #toc-toggle:hover { color: #d4d4d4; }
                #toc-header { color: #999; }
                .toc-item:hover { background: #2d2d2d; }
                .toc-item.active { background: #264f78; border-left-color: #58a6ff; }
                .toc-toggle { color: #999; }
                #toc-resize:hover, #toc-resize.dragging { background: rgba(88,166,255,0.3); }
              }
            </style>
          </head>
          <body>
            <div id="layout">\(tocMarkup)<article class="markdown-body">\(body)</article></div>
            \(highlightBlock)
            \(mermaidBlock)
            \(tocBlock)
          </body>
        </html>
        """
    }
}
