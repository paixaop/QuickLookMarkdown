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

    func load(from url: URL) {
        Self.log("load(from: \(url.path))")
        do {
            let content = try String(contentsOf: url, encoding: .utf8)
            Self.log("Read \(content.count) chars from file")
            let result = try Self.htmlBody(for: url)
            Self.log("Produced \(result.html.count) chars of HTML")
            html = Self.wrapHTML(result.html, isMarkdown: result.isMarkdown)
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
    """

    static let mermaidZoomScript = """
    (function() {
      var scale, panX, panY, overlay, content, zoomLabel, fitScale;
      var dragging = false, didDrag = false, startX, startY, startPanX, startPanY;
      function updateTransform() {
        content.style.transform = 'translate(' + panX + 'px,' + panY + 'px) scale(' + scale + ')';
        if (zoomLabel) zoomLabel.textContent = Math.round(scale * 100) + '%';
      }
      function setScale(s) { scale = Math.min(Math.max(s, 0.1), 10); updateTransform(); }
      function closeOverlay() {
        if (overlay) { overlay.remove(); overlay = null; }
      }
      function fitToScreen() {
        if (!content || !overlay) return;
        var svg = content.querySelector('svg');
        if (!svg) return;
        var vw = overlay.clientWidth * 0.85, vh = overlay.clientHeight * 0.85;
        var sw = svg.width.baseVal.value || svg.getBoundingClientRect().width;
        var sh = svg.height.baseVal.value || svg.getBoundingClientRect().height;
        if (sw > 0 && sh > 0) { fitScale = Math.min(vw / (sw + 48), vh / (sh + 48), 3); }
        else { fitScale = 1; }
        scale = fitScale; panX = 0; panY = 0; updateTransform();
      }
      document.addEventListener('click', function(e) {
        var mermaidDiv = e.target.closest('.mermaid');
        if (!mermaidDiv) return;
        var svg = mermaidDiv.querySelector('svg');
        if (!svg) return;
        scale = 1; panX = 0; panY = 0; fitScale = 1;
        overlay = document.createElement('div');
        overlay.className = 'mermaid-overlay';
        var controls = document.createElement('div');
        controls.className = 'mermaid-overlay-controls';
        var btnPlus = document.createElement('button');
        btnPlus.textContent = '+';
        btnPlus.title = 'Zoom in (+)';
        btnPlus.addEventListener('click', function(ev) { ev.stopPropagation(); setScale(scale + 0.25); });
        var btnMinus = document.createElement('button');
        btnMinus.textContent = '\\u2212';
        btnMinus.title = 'Zoom out (\\u2212)';
        btnMinus.addEventListener('click', function(ev) { ev.stopPropagation(); setScale(scale - 0.25); });
        zoomLabel = document.createElement('span');
        zoomLabel.className = 'mermaid-overlay-zoom-label';
        zoomLabel.textContent = '100%';
        zoomLabel.title = 'Reset zoom';
        zoomLabel.addEventListener('click', function(ev) {
          ev.stopPropagation(); scale = 1; panX = 0; panY = 0; updateTransform();
        });
        var btnClose = document.createElement('button');
        btnClose.textContent = '\\u00D7';
        btnClose.title = 'Close (Esc)';
        btnClose.addEventListener('click', function(ev) { ev.stopPropagation(); closeOverlay(); });
        controls.appendChild(btnPlus);
        controls.appendChild(btnMinus);
        controls.appendChild(zoomLabel);
        controls.appendChild(btnClose);
        content = document.createElement('div');
        content.className = 'mermaid-overlay-content';
        content.appendChild(svg.cloneNode(true));
        content.addEventListener('click', function(ev) { ev.stopPropagation(); });
        content.addEventListener('dblclick', function(ev) {
          ev.stopPropagation();
          if (Math.abs(scale - 1) < 0.01 && panX === 0 && panY === 0) { fitToScreen(); }
          else { scale = 1; panX = 0; panY = 0; updateTransform(); }
        });
        content.addEventListener('mousedown', function(ev) {
          ev.preventDefault(); ev.stopPropagation();
          dragging = true; didDrag = false;
          startX = ev.clientX; startY = ev.clientY;
          startPanX = panX; startPanY = panY;
          content.style.cursor = 'grabbing';
        });
        var viewport = document.createElement('div');
        viewport.className = 'mermaid-overlay-viewport';
        viewport.appendChild(content);
        viewport.addEventListener('click', function(ev) { if (!didDrag) closeOverlay(); });
        overlay.appendChild(controls);
        overlay.appendChild(viewport);
        document.body.appendChild(overlay);
      });
      document.addEventListener('mousemove', function(e) {
        if (!dragging) return;
        var dx = e.clientX - startX, dy = e.clientY - startY;
        if (Math.abs(dx) > 3 || Math.abs(dy) > 3) didDrag = true;
        panX = startPanX + dx; panY = startPanY + dy;
        updateTransform();
      });
      document.addEventListener('mouseup', function() {
        if (dragging) { dragging = false; if (content) content.style.cursor = 'grab'; }
      });
      document.addEventListener('wheel', function(e) {
        if (!overlay) return;
        e.preventDefault();
        var delta = e.deltaY > 0 ? -0.1 : 0.1;
        var rect = overlay.getBoundingClientRect();
        var cx = e.clientX - rect.left - rect.width / 2;
        var cy = e.clientY - rect.top - rect.height / 2;
        var oldScale = scale;
        setScale(scale + delta);
        var ratio = scale / oldScale;
        panX = cx - ratio * (cx - panX); panY = cy - ratio * (cy - panY);
        updateTransform();
      }, { passive: false });
      document.addEventListener('keydown', function(e) {
        if (!overlay) return;
        var step = 40;
        if (e.key === 'Escape') { closeOverlay(); }
        else if (e.key === '+' || e.key === '=') { setScale(scale + 0.25); }
        else if (e.key === '-' || e.key === '_') { setScale(scale - 0.25); }
        else if (e.key === '0') { scale = 1; panX = 0; panY = 0; updateTransform(); }
        else if (e.key === 'ArrowLeft') { panX += step; updateTransform(); }
        else if (e.key === 'ArrowRight') { panX -= step; updateTransform(); }
        else if (e.key === 'ArrowUp') { panY += step; updateTransform(); }
        else if (e.key === 'ArrowDown') { panY -= step; updateTransform(); }
      });
    })();
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

    static let tocScript = """
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
      // Assign IDs (GitHub-style slugs)
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
      // Build tree
      var tree = document.getElementById('toc-tree');
      var items = [];
      headings.forEach(function(h) {
        var level = parseInt(h.tagName.charAt(1));
        var item = { el: h, level: level, children: [] };
        items.push(item);
      });
      // Render flat list with indentation
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
            // Toggle visibility of child items
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
      // Active heading tracking
      var tocItems = tree.querySelectorAll('.toc-item');
      var observer = new IntersectionObserver(function(entries) {
        entries.forEach(function(entry) {
          if (entry.isIntersecting) {
            tocItems.forEach(function(ti) { ti.classList.remove('active'); });
            var id = entry.target.id;
            var match = tree.querySelector('.toc-item[data-heading-id=\"' + id + '\"]');
            if (match) match.classList.add('active');
          }
        });
      }, { root: content, rootMargin: '0px 0px -70% 0px', threshold: 0.1 });
      headings.forEach(function(h) { observer.observe(h); });
      // Toggle button
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
          </body>
        </html>
        """
    }
}
