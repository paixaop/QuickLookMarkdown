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
            var html = HTMLFormatter.format(body)
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

    // MARK: - Scripts

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

    // MARK: - Emoji Shortcodes

    private static let emojiScript = """
    (function() {
      var map = {
        '+1':'\\uD83D\\uDC4D','-1':'\\uD83D\\uDC4E','100':'\\uD83D\\uDCAF',
        'smile':'\\uD83D\\uDE04','laughing':'\\uD83D\\uDE06','blush':'\\uD83D\\uDE0A','smiley':'\\uD83D\\uDE03',
        'wink':'\\uD83D\\uDE09','heart_eyes':'\\uD83D\\uDE0D','sunglasses':'\\uD83D\\uDE0E',
        'joy':'\\uD83D\\uDE02','cry':'\\uD83D\\uDE22','sob':'\\uD83D\\uDE2D',
        'angry':'\\uD83D\\uDE20','rage':'\\uD83D\\uDE21','thinking':'\\uD83E\\uDD14',
        'heart':'\\u2764\\uFE0F','star':'\\u2B50','sparkles':'\\u2728',
        'fire':'\\uD83D\\uDD25','zap':'\\u26A1','rocket':'\\uD83D\\uDE80',
        'thumbsup':'\\uD83D\\uDC4D','thumbsdown':'\\uD83D\\uDC4E','ok_hand':'\\uD83D\\uDC4C',
        'wave':'\\uD83D\\uDC4B','clap':'\\uD83D\\uDC4F','muscle':'\\uD83D\\uDCAA',
        'tada':'\\uD83C\\uDF89','warning':'\\u26A0\\uFE0F','x':'\\u274C',
        'white_check_mark':'\\u2705','heavy_check_mark':'\\u2714\\uFE0F',
        'bug':'\\uD83D\\uDC1B','memo':'\\uD83D\\uDCDD','book':'\\uD83D\\uDCD6',
        'link':'\\uD83D\\uDD17','lock':'\\uD83D\\uDD12','key':'\\uD83D\\uDD11',
        'bulb':'\\uD83D\\uDCA1','computer':'\\uD83D\\uDCBB','eyes':'\\uD83D\\uDC40',
        'skull':'\\uD83D\\uDC80','boom':'\\uD83D\\uDCA5','gem':'\\uD83D\\uDC8E',
        'coffee':'\\u2615','pizza':'\\uD83C\\uDF55','beer':'\\uD83C\\uDF7A',
        'trophy':'\\uD83C\\uDFC6','crown':'\\uD83D\\uDC51','rainbow':'\\uD83C\\uDF08',
        'sunny':'\\u2600\\uFE0F','cloud':'\\u2601\\uFE0F','snowflake':'\\u2744\\uFE0F',
        'dog':'\\uD83D\\uDC36','cat':'\\uD83D\\uDC31','penguin':'\\uD83D\\uDC27',
        'arrow_up':'\\u2B06\\uFE0F','arrow_down':'\\u2B07\\uFE0F',
        'arrow_left':'\\u2B05\\uFE0F','arrow_right':'\\u27A1\\uFE0F',
        'question':'\\u2753','exclamation':'\\u2757','no_entry':'\\u26D4',
        'recycle':'\\u267B\\uFE0F','copyright':'\\u00A9\\uFE0F','tm':'\\u2122\\uFE0F'
      };
      var re = /:([a-z0-9_+-]+):/g;
      var body = document.querySelector('.markdown-body') || document.body;
      var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, {
        acceptNode: function(node) {
          var p = node.parentNode;
          while (p && p !== body) {
            var tag = p.tagName;
            if (tag === 'PRE' || tag === 'CODE' || tag === 'SCRIPT' || tag === 'STYLE') return NodeFilter.FILTER_REJECT;
            p = p.parentNode;
          }
          return NodeFilter.FILTER_ACCEPT;
        }
      });
      var nodes = [];
      while (walker.nextNode()) nodes.push(walker.currentNode);
      nodes.forEach(function(node) {
        var text = node.textContent;
        if (!re.test(text)) return;
        re.lastIndex = 0;
        var newText = text.replace(re, function(match, code) {
          return map[code] || match;
        });
        if (newText !== text) node.textContent = newText;
      });
    })();
    """

    // MARK: - Footnotes

    private static let footnotesScript = """
    (function() {
      var body = document.querySelector('.markdown-body');
      if (!body) return;
      var defs = {};
      var paras = body.querySelectorAll('p');
      var defParas = [];
      paras.forEach(function(p) {
        var text = p.textContent || '';
        var m = text.match(/^\\[\\^([^\\]]+)\\]:\\s*(.*)/s);
        if (m) {
          defs[m[1]] = m[2].trim();
          defParas.push(p);
        }
      });
      if (Object.keys(defs).length === 0) return;
      var refCount = 0;
      var refMap = {};
      function processNode(node) {
        var walker = document.createTreeWalker(node, NodeFilter.SHOW_TEXT, {
          acceptNode: function(n) {
            var p = n.parentNode;
            if (p.tagName === 'PRE' || p.tagName === 'CODE' || p.tagName === 'A') return NodeFilter.FILTER_REJECT;
            return NodeFilter.FILTER_ACCEPT;
          }
        });
        var textNodes = [];
        while (walker.nextNode()) textNodes.push(walker.currentNode);
        textNodes.forEach(function(tn) {
          var text = tn.textContent;
          if (text.indexOf('[^') === -1) return;
          var parts = text.split(/(\\[\\^[^\\]]+\\])/);
          if (parts.length <= 1) return;
          var frag = document.createDocumentFragment();
          parts.forEach(function(part) {
            var rm = part.match(/^\\[\\^([^\\]]+)\\]$/);
            if (rm && defs[rm[1]] !== undefined) {
              var id = rm[1];
              if (!refMap[id]) { refCount++; refMap[id] = refCount; }
              var num = refMap[id];
              var sup = document.createElement('sup');
              sup.className = 'footnote-ref';
              var a = document.createElement('a');
              a.href = '#fn-' + id;
              a.id = 'fnref-' + id;
              a.textContent = num;
              sup.appendChild(a);
              frag.appendChild(sup);
            } else {
              frag.appendChild(document.createTextNode(part));
            }
          });
          tn.parentNode.replaceChild(frag, tn);
        });
      }
      processNode(body);
      defParas.forEach(function(p) { p.remove(); });
      var section = document.createElement('section');
      section.className = 'footnotes';
      var hr = document.createElement('hr');
      section.appendChild(hr);
      var ol = document.createElement('ol');
      var keys = Object.keys(refMap).sort(function(a, b) { return refMap[a] - refMap[b]; });
      keys.forEach(function(id) {
        var li = document.createElement('li');
        li.id = 'fn-' + id;
        var textSpan = document.createElement('span');
        textSpan.textContent = defs[id] + ' ';
        li.appendChild(textSpan);
        var backref = document.createElement('a');
        backref.href = '#fnref-' + id;
        backref.className = 'footnote-backref';
        backref.textContent = '\\u21A9';
        li.appendChild(backref);
        ol.appendChild(li);
      });
      section.appendChild(ol);
      body.appendChild(section);
    })();
    """

    // MARK: - Frontmatter

    private static let frontmatterScript = """
    (function() {
      var el = document.getElementById('frontmatter-data');
      if (!el) return;
      var raw = el.textContent;
      if (!raw || !window.jsyaml) return;
      try {
        var data = jsyaml.load(raw);
        if (!data || typeof data !== 'object') return;
        var banner = document.createElement('div');
        banner.className = 'frontmatter-banner';
        if (data.title) {
          var t = document.createElement('div');
          t.className = 'frontmatter-title';
          t.textContent = data.title;
          banner.appendChild(t);
        }
        var meta = [];
        if (data.author) meta.push(data.author);
        if (data.date) meta.push(String(data.date));
        if (meta.length > 0) {
          var m = document.createElement('div');
          m.className = 'frontmatter-meta';
          m.textContent = meta.join(' \\u00B7 ');
          banner.appendChild(m);
        }
        if (data.tags && Array.isArray(data.tags)) {
          var tagsDiv = document.createElement('div');
          tagsDiv.className = 'frontmatter-tags';
          data.tags.forEach(function(tag) {
            var pill = document.createElement('span');
            pill.className = 'frontmatter-tag';
            pill.textContent = tag;
            tagsDiv.appendChild(pill);
          });
          banner.appendChild(tagsDiv);
        }
        var body = document.querySelector('.markdown-body');
        if (body) {
          var stats = body.querySelector('.reading-stats');
          if (stats) body.insertBefore(banner, stats);
          else body.insertBefore(banner, body.firstChild);
        }
      } catch(e) {}
    })();
    """

    // MARK: - Anchor Links

    private static let anchorLinksScript = """
    (function() {
      var body = document.querySelector('.markdown-body');
      if (!body) return;
      body.querySelectorAll('h1, h2, h3, h4, h5, h6').forEach(function(h) {
        if (!h.id) return;
        var a = document.createElement('a');
        a.className = 'heading-anchor';
        a.href = '#' + h.id;
        a.textContent = '#';
        a.addEventListener('click', function(e) { e.stopPropagation(); });
        h.insertBefore(a, h.firstChild);
      });
    })();
    """

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

        let lineNumbersBlock = """
            <script>
            (function() {
              var pref = false; try { pref = localStorage.getItem('line-numbers') === 'true'; } catch(e) {}
              document.querySelectorAll('pre > code').forEach(function(code) {
                if (code.classList.contains('language-mermaid') || code.classList.contains('language-dot') || code.classList.contains('language-graphviz')) return;
                var text = code.innerHTML;
                var lines = text.split('\\n');
                if (lines.length > 0 && lines[lines.length - 1] === '') lines.pop();
                code.innerHTML = lines.map(function(l) { return '<span class="code-line">' + l + '<\\/span>'; }).join('');
                if (pref) code.classList.add('has-line-numbers');
              });
              document.addEventListener('keydown', function(e) {
                if (e.metaKey && e.key === 'l') {
                  e.preventDefault();
                  var on = !document.querySelector('pre > code.has-line-numbers');
                  document.querySelectorAll('pre > code').forEach(function(code) {
                    if (code.classList.contains('language-mermaid') || code.classList.contains('language-dot') || code.classList.contains('language-graphviz')) return;
                    if (on) code.classList.add('has-line-numbers');
                    else code.classList.remove('has-line-numbers');
                  });
                  try { localStorage.setItem('line-numbers', on ? 'true' : 'false'); } catch(e) {}
                }
              });
            })();
            </script>
        """

        let copyButtonBlock = """
            <script>
            (function() {
              document.querySelectorAll('pre > code').forEach(function(code) {
                if (code.classList.contains('language-mermaid')) return;
                var pre = code.parentElement;
                if (!pre || pre.querySelector('.copy-btn')) return;
                pre.style.position = 'relative';
                var btn = document.createElement('button');
                btn.className = 'copy-btn';
                btn.textContent = 'Copy';
                btn.addEventListener('click', function(e) {
                  e.preventDefault();
                  e.stopPropagation();
                  var text = code.textContent || '';
                  if (navigator.clipboard && navigator.clipboard.writeText) {
                    navigator.clipboard.writeText(text).then(function() {
                      btn.textContent = 'Copied!';
                      setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
                    }).catch(function() { fallbackCopy(text, btn); });
                  } else {
                    fallbackCopy(text, btn);
                  }
                });
                pre.appendChild(btn);
              });
              function fallbackCopy(text, btn) {
                var ta = document.createElement('textarea');
                ta.value = text;
                ta.style.position = 'fixed';
                ta.style.left = '-9999px';
                document.body.appendChild(ta);
                ta.select();
                try {
                  document.execCommand('copy');
                  btn.textContent = 'Copied!';
                  setTimeout(function() { btn.textContent = 'Copy'; }, 1500);
                } catch(e) {}
                document.body.removeChild(ta);
              }
            })();
            </script>
        """

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

        let zoomOverlayBlock = """
            <script>
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
                var el = content.querySelector('svg') || content.querySelector('img');
                if (!el) return;
                var vw = overlay.clientWidth * 0.85, vh = overlay.clientHeight * 0.85;
                var sw, sh;
                if (el.tagName === 'IMG') { sw = el.naturalWidth || el.width; sh = el.naturalHeight || el.height; }
                else { sw = el.width.baseVal.value || el.getBoundingClientRect().width; sh = el.height.baseVal.value || el.getBoundingClientRect().height; }
                if (sw > 0 && sh > 0) { fitScale = Math.min(vw / (sw + 48), vh / (sh + 48), 3); }
                else { fitScale = 1; }
                scale = fitScale; panX = 0; panY = 0; updateTransform();
              }
              function openOverlay(cloneEl) {
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
                content.appendChild(cloneEl);
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
                setTimeout(fitToScreen, 50);
              }
              document.addEventListener('click', function(e) {
                var mermaidDiv = e.target.closest('.mermaid');
                if (mermaidDiv) {
                  var svg = mermaidDiv.querySelector('svg');
                  if (svg) openOverlay(svg.cloneNode(true));
                  return;
                }
                var img = e.target.closest('.markdown-body img');
                if (img) {
                  var clone = img.cloneNode(true);
                  clone.style.maxWidth = '85vw';
                  clone.style.maxHeight = '80vh';
                  clone.style.display = 'block';
                  openOverlay(clone);
                }
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
            </script>
        """

        let readingStatsBlock = """
            <script>
            (function() {
              if (document.documentElement.getAttribute('data-filetype') !== 'markdown') return;
              var body = document.querySelector('.markdown-body');
              if (!body) return;
              var text = body.textContent || '';
              var words = text.trim().split(/\\s+/).filter(function(w) { return w.length > 0; }).length;
              var minutes = Math.max(1, Math.round(words / 200));
              var stats = document.createElement('div');
              stats.className = 'reading-stats';
              stats.textContent = words.toLocaleString() + ' words \\u00B7 ' + minutes + ' min read';
              body.insertBefore(stats, body.firstChild);
            })();
            </script>
        """

        let fontSizeBlock = """
            <script>
            (function() {
              var root = document.documentElement;
              var current = 16;
              var min = 10, max = 32, step = 2;
              document.addEventListener('keydown', function(e) {
                if (!e.metaKey) return;
                if (e.key === '=' || e.key === '+') {
                  e.preventDefault();
                  current = Math.min(current + step, max);
                  root.style.fontSize = current + 'px';
                } else if (e.key === '-') {
                  e.preventDefault();
                  current = Math.max(current - step, min);
                  root.style.fontSize = current + 'px';
                } else if (e.key === '0') {
                  e.preventDefault();
                  current = 16;
                  root.style.fontSize = '';
                }
              });
            })();
            </script>
        """

        let jumpToLineBlock = """
            <script>
            (function() {
              var bar = null;
              function close() { if (bar) { bar.remove(); bar = null; } }
              document.addEventListener('keydown', function(e) {
                if (e.metaKey && e.key === 'g') {
                  e.preventDefault();
                  if (bar) { close(); return; }
                  bar = document.createElement('div');
                  bar.id = 'jump-bar';
                  var inp = document.createElement('input');
                  inp.type = 'number';
                  inp.min = '1';
                  inp.placeholder = 'Line #';
                  bar.appendChild(inp);
                  document.body.appendChild(bar);
                  inp.focus();
                  inp.addEventListener('keydown', function(ev) {
                    if (ev.key === 'Escape') { close(); return; }
                    if (ev.key === 'Enter') {
                      var n = parseInt(inp.value);
                      if (!n || n < 1) return;
                      var lines = document.querySelectorAll('.code-line');
                      if (n > lines.length) n = lines.length;
                      var target = lines[n - 1];
                      if (target) {
                        target.scrollIntoView({ behavior: 'smooth', block: 'center' });
                        target.classList.add('line-flash');
                        setTimeout(function() { target.classList.remove('line-flash'); }, 1000);
                      }
                      close();
                    }
                  });
                }
              });
            })();
            </script>
        """

        let findBlock = """
            <script>
            (function() {
              var bar, input, counter, highlights = [], currentIdx = -1;
              function clearHighlights() {
                highlights.forEach(function(span) {
                  var parent = span.parentNode;
                  if (parent) { parent.replaceChild(document.createTextNode(span.textContent), span); parent.normalize(); }
                });
                highlights = []; currentIdx = -1;
              }
              function updateCounter() {
                if (!counter) return;
                if (highlights.length === 0) { counter.textContent = ''; return; }
                counter.textContent = (currentIdx + 1) + '/' + highlights.length;
              }
              function scrollToCurrent() {
                highlights.forEach(function(h) { h.className = 'find-highlight'; });
                if (currentIdx >= 0 && currentIdx < highlights.length) {
                  highlights[currentIdx].className = 'find-highlight find-highlight-active';
                  highlights[currentIdx].scrollIntoView({ behavior: 'smooth', block: 'center' });
                }
                updateCounter();
              }
              function doSearch(query) {
                clearHighlights();
                if (!query) { updateCounter(); return; }
                var body = document.querySelector('.markdown-body') || document.body;
                var walker = document.createTreeWalker(body, NodeFilter.SHOW_TEXT, null);
                var textNodes = [];
                while (walker.nextNode()) textNodes.push(walker.currentNode);
                var lowerQ = query.toLowerCase();
                textNodes.forEach(function(node) {
                  var text = node.textContent;
                  var lower = text.toLowerCase();
                  var idx = lower.indexOf(lowerQ);
                  if (idx === -1) return;
                  var frag = document.createDocumentFragment();
                  var pos = 0;
                  while (idx !== -1) {
                    if (idx > pos) frag.appendChild(document.createTextNode(text.substring(pos, idx)));
                    var span = document.createElement('span');
                    span.className = 'find-highlight';
                    span.textContent = text.substring(idx, idx + query.length);
                    frag.appendChild(span);
                    highlights.push(span);
                    pos = idx + query.length;
                    idx = lower.indexOf(lowerQ, pos);
                  }
                  if (pos < text.length) frag.appendChild(document.createTextNode(text.substring(pos)));
                  node.parentNode.replaceChild(frag, node);
                });
                if (highlights.length > 0) { currentIdx = 0; scrollToCurrent(); }
                else { updateCounter(); }
              }
              function openBar() {
                if (bar) { input.focus(); input.select(); return; }
                bar = document.createElement('div');
                bar.id = 'find-bar';
                input = document.createElement('input');
                input.type = 'text';
                input.placeholder = 'Find...';
                counter = document.createElement('span');
                counter.className = 'find-counter';
                var closeBtn = document.createElement('button');
                closeBtn.textContent = '\\u00D7';
                closeBtn.addEventListener('click', function() { closeBar(); });
                bar.appendChild(input);
                bar.appendChild(counter);
                bar.appendChild(closeBtn);
                document.body.appendChild(bar);
                input.focus();
                var debounce;
                input.addEventListener('input', function() {
                  clearTimeout(debounce);
                  debounce = setTimeout(function() { doSearch(input.value); }, 150);
                });
                input.addEventListener('keydown', function(ev) {
                  if (ev.key === 'Escape') { closeBar(); return; }
                  if (ev.key === 'Enter') {
                    if (highlights.length === 0) return;
                    if (ev.shiftKey) { currentIdx = (currentIdx - 1 + highlights.length) % highlights.length; }
                    else { currentIdx = (currentIdx + 1) % highlights.length; }
                    scrollToCurrent();
                  }
                });
              }
              function closeBar() {
                clearHighlights();
                if (bar) { bar.remove(); bar = null; }
              }
              document.addEventListener('keydown', function(e) {
                if (e.metaKey && e.key === 'f') {
                  e.preventDefault();
                  openBar();
                }
              });
            })();
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
              #layout.has-toc { display: flex; overflow: hidden; }
              #layout.has-toc .markdown-body { flex: 1; overflow-y: auto; min-height: 0; }
              html:has(#layout.has-toc), body:has(#layout.has-toc) { height: 100vh; overflow: hidden; }
              #toc-container {
                position: relative; width: 220px; min-width: 100px; max-width: 50vw;
                height: 100vh; border-right: 1px solid #d0d7de; background: #f6f8fa;
                font-size: 13px; display: flex; flex-direction: column;
              }
              #toc-container.hidden { display: none; }
              #toc-container.collapsed { width: 36px !important; min-width: 36px; overflow: hidden; }
              #toc-nav { flex: 1; overflow: hidden; display: flex; flex-direction: column; }
              #toc-container.collapsed #toc-nav { display: none; }
              #toc-container.collapsed #toc-resize { display: none; }
              #toc-resize { position: absolute; top: 0; right: -3px; width: 6px; height: 100%; cursor: col-resize; z-index: 10; }
              #toc-resize:hover, #toc-resize.dragging { background: rgba(9,105,218,0.3); }
              #toc-toggle { background: none; border: none; cursor: pointer; font-size: 18px; padding: 6px 8px; text-align: left; color: #656d76; flex-shrink: 0; }
              #toc-toggle:hover { color: #1f2328; }
              #toc-header { font-weight: 600; padding: 4px 10px 8px; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; color: #656d76; }
              #toc-tree { flex: 1; overflow-y: auto; }
              .toc-item { display: flex; align-items: center; padding: 3px 8px; cursor: pointer; border-left: 3px solid transparent; }
              .toc-item:hover { background: #e8e8e8; }
              .toc-item.active { border-left-color: #0969da; background: #dbeafe; }
              .toc-toggle { font-size: 8px; width: 14px; text-align: center; flex-shrink: 0; transition: transform 0.15s; cursor: pointer; user-select: none; color: #656d76; }
              .toc-toggle.no-children { visibility: hidden; }
              .toc-item.collapsed .toc-toggle { transform: rotate(0deg); }
              .toc-item:not(.collapsed) .toc-toggle:not(.no-children) { transform: rotate(90deg); }
              .toc-label { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; flex: 1; padding-left: 4px; }
              body.toc-resizing { cursor: col-resize; user-select: none; }
              @media (prefers-color-scheme: dark) {
                #toc-container { background: #252526; border-right-color: #444c56; }
                #toc-toggle { color: #999; } #toc-toggle:hover { color: #d4d4d4; }
                #toc-header { color: #999; }
                .toc-item:hover { background: #2d2d2d; }
                .toc-item.active { background: #264f78; border-left-color: #58a6ff; }
                .toc-toggle { color: #999; }
                #toc-resize:hover, #toc-resize.dragging { background: rgba(88,166,255,0.3); }
              }
              html[data-theme="dark"] #toc-container { background: #252526; border-right-color: #444c56; }
              html[data-theme="dark"] #toc-toggle { color: #999; }
              html[data-theme="dark"] #toc-toggle:hover { color: #d4d4d4; }
              html[data-theme="dark"] #toc-header { color: #999; }
              html[data-theme="dark"] .toc-item:hover { background: #2d2d2d; }
              html[data-theme="dark"] .toc-item.active { background: #264f78; border-left-color: #58a6ff; }
              html[data-theme="dark"] .toc-toggle { color: #999; }
              html[data-theme="dark"] #toc-resize:hover,
              html[data-theme="dark"] #toc-resize.dragging { background: rgba(88,166,255,0.3); }
              html[data-theme="light"] #toc-container { background: #f6f8fa; border-right-color: #d0d7de; }
              html[data-theme="light"] #toc-toggle { color: #656d76; }
              html[data-theme="light"] #toc-toggle:hover { color: #1f2328; }
              html[data-theme="light"] #toc-header { color: #656d76; }
              html[data-theme="light"] .toc-item:hover { background: #e8e8e8; }
              html[data-theme="light"] .toc-item.active { background: #dbeafe; border-left-color: #0969da; }
              html[data-theme="light"] .toc-toggle { color: #656d76; }
              html[data-theme="light"] #toc-resize:hover,
              html[data-theme="light"] #toc-resize.dragging { background: rgba(9,105,218,0.3); }
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
                #toc-container, .copy-btn, #find-bar, #jump-bar,
                .reading-stats, .mermaid-overlay { display: none !important; }
                body { background: white !important; color: black !important; }
                .markdown-body { padding: 0 !important; }
                #layout { display: block !important; height: auto !important; }
                #layout.has-toc .markdown-body { overflow: visible !important; }
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
            </style>
          </head>
          <body>
            <div id="layout">\(tocMarkup)<article class="markdown-body">\(body)</article></div>
            \(highlightBlock)
            \(lineNumbersBlock)
            \(copyButtonBlock)
            \(katexBlock)
            \(mermaidBlock)
            \(graphvizBlock)
            \(zoomOverlayBlock)
            \(readingStatsBlock)
            \(tocBlock)
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
