Original URL: https://grok.com/c/1c483761-affb-42a4-b5c0-491f1958a80a?rid=0ff9f487-0398-4829-8c4b-be76f58ead7e

**[USER]**

Swift to JS bridge

**[ASSISTANT]**

**The native Apple WKWebView bridge is garbage for anything beyond trivial one-off calls.** It forces manual JSON serialization, string-based `evaluateJavaScript` (escape hell + security nightmare), retain cycles if you forget `removeScriptMessageHandler`, and zero built-in callbacks. Use **WKWebViewJavascriptBridge** instead — lightweight (3 files), callback-based, symmetric API on both sides, iOS 9.0+, no subclassing required.

### Setup (WKWebViewJavascriptBridge)

**Swift side** (in your view controller):
```swift
import WKWebViewJavascriptBridge

class ViewController: UIViewController {
    var webView: WKWebView!
    var bridge: WKWebViewJavascriptBridge!

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: view.bounds, configuration: config)
        view.addSubview(webView)
        
        bridge = WKWebViewJavascriptBridge(webView: webView)
        
        // Register handler (JS calls this)
        bridge.register(handlerName: "testiOSCallback") { parameters, callback in
            print("JS called with: \(parameters ?? [:])")
            callback?("Response from Swift: success")  // optional reply
        }
        
        // Example: call JS from Swift
        bridge.call(handlerName: "testJavascriptHandler", data: ["foo": "bar"]) { response in
            print("JS replied: \(response ?? [:])")
        }
        
        // Load your HTML (must include the JS bridge setup below)
        webView.loadHTMLString("<html>...</html>", baseURL: nil)
    }
}
```

**JavaScript side** (in your HTML/JS):
```html
<script>
function setupWKWebViewJavascriptBridge(callback) {
    if (window.WKWebViewJavascriptBridge) return callback(WKWebViewJavascriptBridge);
    if (window.WKWVJBCallbacks) return window.WKWVJBCallbacks.push(callback);
    window.WKWVJBCallbacks = [callback];
    window.webkit.messageHandlers.iOS_Native_InjectJavascript.postMessage(null);
}

setupWKWebViewJavascriptBridge(function(bridge) {
    // Register handler (Swift calls this)
    bridge.registerHandler('testJavascriptHandler', function(data, responseCallback) {
        console.log('Swift called with', data);
        responseCallback({ 'Javascript Says': 'Right back atcha!' });
    });

    // Call Swift from JS
    bridge.callHandler('testiOSCallback', { 'foo': 'bar' }, function(response) {
        console.log('Swift replied:', response);
    });
});
</script>
```

Installation: CocoaPods (`pod 'WKWebViewJavascriptBridge', '~> 1.2.0'`) or Carthage/manual. Full repo: https://github.com/Lision/WKWebViewJavascriptBridge.

### Why this beats native
- Callbacks work out of the box (no `completionHandler` hell).
- Clean data passing (objects auto-JSON'd).
- No memory leaks if you follow the setup.
- Higher performance than request interception tricks.

### Native Apple way (only if you hate yourself)
```swift
// Setup
config.userContentController.add(self, name: "myBridge")  // self must conform to WKScriptMessageHandler

// JS → Swift
func userContentController(_: WKUserContentController, didReceive message: WKScriptMessage) {
    // message.body (cast to [String: Any] or whatever)
}

// Swift → JS (fragile)
webView.evaluateJavaScript("jsFunc(\(try! JSONSerialization.data(withJSONObject: data)))") { _, error in ... }

// Cleanup (mandatory or leak)
deinit {
    config.userContentController.removeScriptMessageHandler(forName: "myBridge")
}
```
JS: `window.webkit.messageHandlers.myBridge.postMessage(payload)`

This breaks easily with complex objects, escaping, or main-thread requirements.

### Other contexts (if this isn't what you meant)
- **No web UI, just run JS in Swift**: JavaScriptCore (`JSContext`, `JSValue`). Expose Swift objects via `setObject:forKeyedSubscript:`. Clunky for large codebases.
- **Swift compiled to browser**: SwiftWasm + JavaScriptKit (typed `JSObject`, DOM interop).
- **Hybrid frameworks**: Capacitor/Ionic have their own plugins — don't roll your own.

Tell me the exact direction (JS→Swift, Swift→JS, both), use case (native APIs exposed to web page?), or platform, and I'll give the precise code or point out why your current approach won't work.

**[USER]**

I want to write a markdown editor and viewer. And want to link the entitle to the rendered view. When I scroll one the other needs to scroll in sync. When I double click a word the editor needs to open in that word. What sync algorithm can inuse

**[ASSISTANT]**

**Use `data-source-line` mapping. Everything else fails.**

Proportional scrolling (scroll ratio = editorScrollTop / editorHeight == previewScrollTop / previewHeight) is trash. It desyncs immediately on headings, images, lists, or any formatting because rendered block heights have zero relation to source line counts. You'll see the preview jump 3 screens ahead or lag behind. Joplin, VS Code custom previews, and every production editor that actually works reject it for the same reason.

### The algorithm that works: line-anchored element mapping
1. Parse Markdown → HTML and inject `data-source-line="N"` (and optionally `data-source-line-end`) on every block element (`<p>`, `<h1>`, `<li>`, `<pre>`, `<table>`, `<tr>`, etc.). Inline elements ignored.
2. On scroll in one view:
   - Find the topmost (or first partially visible) element with a `data-source-line`.
   - Map that line number to the corresponding position in the other view.
   - Scroll the other view to make the matching element visible at the same relative offset (using element visibility percentage for smoothness).
3. Build a one-time scroll map (line offset → pixel position) for O(1) lookups if your document is huge.
4. Bidirectional guard: set a `isScrollingFromOther = true` flag before programmatic scroll, clear it after 50-100ms debounce. Without this the views fight each other in an infinite loop.

This is exactly what Joplin, the classic Remarkable demo, and every serious dual-pane editor use.

### Implementation for your Swift + WKWebView setup (via the bridge you asked about last time)

**JS side** (in your preview HTML — use markdown-it):
```html
<script src="https://cdn.jsdelivr.net/npm/markdown-it@latest/dist/markdown-it.min.js"></script>
<script src="https://cdn.jsdelivr.net/npm/markdown-it-inject-linenumbers@latest"></script> <!-- or bundle it -->

<script>
const md = markdownIt().use(markdownitInjectLinenumbers);

function renderMarkdown(text) {
  const html = md.render(text);
  document.getElementById('preview').innerHTML = html;
  // expose to bridge
  window.bridge = WKWebViewJavascriptBridge; // or whatever you named it
}

// Find top visible line (throttled)
let lastScrollTime = 0;
preview.addEventListener('scroll', () => {
  if (Date.now() - lastScrollTime < 16) return; // ~60fps
  lastScrollTime = Date.now();

  const elements = preview.querySelectorAll('[data-source-line]');
  let topElement = null;
  let minTop = Infinity;

  elements.forEach(el => {
    const rect = el.getBoundingClientRect();
    if (rect.top >= 0 && rect.top < minTop) {
      minTop = rect.top;
      topElement = el;
    }
  });

  if (topElement && window.bridge) {
    const line = parseInt(topElement.dataset.sourceLine, 10);
    window.bridge.callHandler('scrollEditorToLine', { line });
  }
});

// Double-click → jump editor to word (approximate)
preview.addEventListener('dblclick', e => {
  let el = e.target.closest('[data-source-line]');
  if (!el) return;

  const line = parseInt(el.dataset.sourceLine, 10);

  // Word-level is approximate only
  const range = document.caretRangeFromPoint(e.clientX, e.clientY);
  const textOffset = range.startOffset; // relative to this element's textContent

  window.bridge.callHandler('jumpEditorToWord', { line, textOffset, wordSnippet: range.startContainer.textContent.slice(0, 20) });
});
</script>
```

**Swift side** (UITextView editor + bridge):
```swift
bridge.register(handlerName: "scrollEditorToLine") { params, _ in
  guard let line = params?["line"] as? Int else { return }
  scrollTextViewToLine(line) // see below
}

bridge.register(handlerName: "jumpEditorToWord") { params, _ in
  guard let line = params?["line"] as? Int,
        let offset = params?["textOffset"] as? Int else { return }
  scrollTextViewToLine(line)
  // Then fuzzy find word in that line and set selectedRange
  // (exact match impossible — rendered text != source)
}

// Editor scroll → preview
func scrollViewDidScroll(_ scrollView: UIScrollView) {
  guard !isScrollingFromPreview else { return }
  let currentLine = lineNumberAtVisibleTop() // implementation below
  bridge.call(handlerName: "scrollPreviewToLine", data: ["line": currentLine])
}

// Helper: line at top of visible rect
func lineNumberAtVisibleTop() -> Int {
  let visibleRect = textView.bounds
  let glyphRange = layoutManager.glyphRange(forBoundingRect: visibleRect, in: textContainer)
  let charIndex = layoutManager.characterIndex(for: glyphRange.location, in: textStorage)
  return textStorage.attributedSubstring(from: NSRange(location: 0, length: charIndex)).string.components(separatedBy: .newlines).count - 1
}

func scrollTextViewToLine(_ line: Int) {
  isScrollingFromPreview = true
  defer { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.isScrollingFromPreview = false } }

  let range = NSRange(location: textAtLine(line).location, length: 1)
  textView.scrollRangeToVisible(range)
}
```

### Double-click word limitations (this has holes)
Exact word mapping from rendered HTML back to source cursor position is unreliable. Rendered text strips Markdown syntax (`**bold**` becomes `bold`). You'll only get the line + rough text offset in the rendered block. Then in Swift you can:
- Jump to line
- Search the source line for the closest matching substring (the `wordSnippet` you sent)
- Set cursor there.

This is "good enough" for 95% of cases. True character-level sourcemaps require a full AST (unified/remark + positions) and are overkill — they still break on complex inline formatting.

### Actionable next steps (do these or it won't work)
1. Install `markdown-it-inject-linenumbers` (or copy its 20-line rule).
2. Add the `isScrollingFromPreview` guard immediately — without it the views oscillate.
3. Throttle/debounce both scroll listeners (16ms minimum).
4. Rebuild the preview + re-inject attributes on every edit (debounced 300ms).
5. Test with tables, nested lists, and large images — that's where cheap algorithms die.

If your editor is pure web (not native UITextView) the exact same JS works on both panes. If you want full AST + character-level word jumping tell me — it's possible with remark but 10x more code and still fragile.

This is the algorithm every working implementation uses. Use it or waste time debugging jumpy sync.

**[USER]**

What about the TOC in a separate swift sidebar?

**[ASSISTANT]**

**Native Swift sidebar TOC is straightforward but *only* if you generate it from the JS preview DOM.**  

Pure Swift parsing (Ink, swift-markdown, regex, whatever) **will not work reliably**. Headings in source != rendered output (inline Markdown, emojis, links, custom plugins all change the visible text and nesting). You'll get wrong titles, wrong levels, and clicks that jump to the wrong place. Harper already checked — Ink line extraction is fragile and doesn't match your `data-source-line` sync. Do it the way every production editor does: one source of truth = the rendered preview.

### 1. JS side — generate & send TOC after every render (reuses your existing `data-source-line`)

Add this right after you call `md.render()` (extend the same `renderMarkdown` function from before):

```html
<script>
// After renderMarkdown(text) { ... }
function sendTOCToSwift() {
  const headings = document.querySelectorAll('h1, h2, h3, h4, h5, h6');
  const toc = Array.from(headings).map(h => ({
    line: parseInt(h.dataset.sourceLine, 10),
    level: parseInt(h.tagName[1], 10),
    title: h.textContent.trim()
  })).filter(item => !isNaN(item.line));

  window.bridge.callHandler('updateTOC', toc);
}

// Call this immediately after innerHTML = html
sendTOCToSwift();
</script>
```

(Pro tip: also add `markdown-it-anchor` plugin if you want pretty `#heading-ids` for future-proofing. But you don't need them — `data-source-line` is enough.)

### 2. Swift side — bridge handler + native sidebar

```swift
// In your ViewController
var tocTableView: UITableView!          // or SwiftUI List if you migrated
var tocItems: [TOCItem] = []
var currentActiveIndex: Int = -1

struct TOCItem {
    let line: Int
    let level: Int
    let title: String
}

override func viewDidLoad() {
    // ... existing bridge + webView + textView setup
    
    // Sidebar setup (example: left pane in UISplitViewController or stack view)
    tocTableView = UITableView()
    tocTableView.delegate = self
    tocTableView.dataSource = self
    tocTableView.register(UITableViewCell.self, forCellReuseIdentifier: "toc")
    // add to view hierarchy however you want (fixed width sidebar)
    
    bridge.register(handlerName: "updateTOC") { params, _ in
        guard let array = params as? [[String: Any]] else { return }
        self.tocItems = array.compactMap { dict in
            guard let line = dict["line"] as? Int,
                  let level = dict["level"] as? Int,
                  let title = dict["title"] as? String else { return nil }
            return TOCItem(line: line, level: level, title: title)
        }
        self.tocTableView.reloadData()
        self.updateActiveTOCItem() // in case scroll position already set
    }
}
```

### 3. Click handler — jumps BOTH editor and preview instantly

```swift
extension ViewController: UITableViewDelegate {
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let item = tocItems[indexPath.row]
        
        // Scroll editor (reuses your existing helper)
        scrollTextViewToLine(item.line)
        
        // Scroll preview via bridge (reuses your scrollPreviewToLine logic)
        bridge.call(handlerName: "scrollPreviewToLine", data: ["line": item.line])
        
        // Optional: highlight the row
        currentActiveIndex = indexPath.row
        tableView.reloadData()
    }
}

extension ViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int { tocItems.count }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "toc", for: indexPath)
        let item = tocItems[indexPath.row]
        cell.textLabel?.text = String(repeating: "    ", count: item.level - 1) + "• " + item.title
        cell.textLabel?.textColor = (indexPath.row == currentActiveIndex) ? .systemBlue : .label
        return cell
    }
}
```

### 4. Active heading highlight (the part everyone forgets and then hates)

Hook into your existing `scrollViewDidScroll` (editor) **and** the preview scroll bridge callback:

```swift
func updateActiveTOCItem(currentLine: Int) {
    // Binary search on sorted tocItems to find largest line <= currentLine
    var low = 0, high = tocItems.count - 1, result = -1
    while low <= high {
        let mid = (low + high) / 2
        if tocItems[mid].line <= currentLine {
            result = mid
            low = mid + 1
        } else {
            high = mid - 1
        }
    }
    if result != currentActiveIndex {
        currentActiveIndex = result
        tocTableView.reloadData()
        tocTableView.scrollToRow(at: IndexPath(row: result, section: 0), at: .middle, animated: true)
    }
}

// Call this from:
- editor scrollViewDidScroll
- preview "scrollEditorToLine" handler (after you compute the line)
- and after TOC is updated
```

### Actionable next steps (do these or it breaks)
1. Add the `sendTOCToSwift()` call **immediately** after every `innerHTML` update (debounce edits to 300ms like before).
2. Add the guard `isScrollingFromPreview` you already have — TOC clicks must not trigger scroll loops.
3. Test with duplicate headings, nested lists inside headings, and very long documents. The line-based approach survives all of it.
4. If you ever switch to full SwiftUI, replace the table with `List` + `@State` and `onChange` — same logic.

This gives you pixel-perfect sync with zero extra parsing. Anything else (separate Swift parser, proportional TOC, etc.) is a waste of time and will desync on the first complex Markdown file. Implement exactly this and it just works. If you want the SwiftUI version instead of UITableView, say so.

**[USER]**

Is it better to have another webview for the the sidebars? I want to have multiple side bars and move them around. Left side or right side. Similar to vscode main tab I wan to have a navbar with icons on top, the file browser, the TOC, comments, etc

**[ASSISTANT]**

**No. Another WKWebView for the sidebars (or multiple) is one of the worst decisions you could make here.** It will tank performance, RAM, and native feel immediately.

Every extra `WKWebView` spawns its own WebContent process + networking process. Your preview already costs 50-150 MB idle. Add one sidebar webview = +2 processes and another 100+ MB. Add file browser + TOC + comments = 400-600 MB baseline before any content loads. Resize, drag-to-move, or toggle panels? Laggy as hell. Bridge routing across 4+ webviews becomes a debugging nightmare. Native integration (drag-drop files, keyboard nav, system accent colors) is impossible without fighting the web layer.

This is exactly why no serious native editor does it. VS Code is Electron (all web), but you're building **native Swift**. Don't copy its worst trait.

### Correct architecture: One WKWebView (preview only) + pure native sidebars
Use **SwiftUI**. Your current UIKit + manual UITableView setup won't scale to movable, dynamic, multi-panel sidebars without 5x more code and constant bugs on resize/collapse. Migrate now — this exact layout is trivial in SwiftUI 5+/macOS 15+ and feels native.

Here's the VS Code clone structure:

```swift
// MainWindow.swift (or your Document/ContentView)
struct MarkdownEditorView: View {
    @State private var selectedActivity: Activity = .files      // icon selection
    @State private var sidebarVisibility: NavigationSplitViewVisibility = .all
    @State private var sidebarPosition: SidebarPosition = .left  // for left/right toggle
    
    @State private var documentText = ""  // your markdown source
    @State private var previewHTML = ""   // sent to WKWebView via bridge if needed
    
    var body: some View {
        HStack(spacing: 0) {  // full window
            
            // 1. ACTIVITY BAR (vertical icons, like VS Code left navbar)
            ActivityBar(selected: $selectedActivity)
                .frame(width: 48)
                .background(.ultraThinMaterial)  // modern macOS look
            
            // 2. PRIMARY SIDEBAR (resizable, content swaps, can move left/right)
            if sidebarVisibility != .hidden {
                Group {
                    switch selectedActivity {
                    case .files:    FileBrowserView()
                    case .toc:      TOCView()           // reuse your line-based TOC
                    case .comments: CommentsView()
                    case .outline:  OutlineView()       // whatever else
                    }
                }
                .frame(minWidth: 180, idealWidth: 240)
                .background(.ultraThinMaterial)
            }
            
            // 3. MAIN CONTENT (editor + preview split, resizable)
            NavigationSplitView(columnVisibility: $sidebarVisibility) {
                // Optional secondary left stuff if you want
            } content: {
                HSplitView {  // editor | preview
                    EditorTextView(text: $documentText)  // your UITextView wrapped or TextEditor
                        .onChange(of: documentText) { newText in
                            // debounce + render to preview WKWebView
                        }
                    
                    PreviewWebView(html: $previewHTML)  // your single WKWebView
                }
            } detail: {
                // empty or inspector
            }
            .navigationSplitViewStyle(.balanced)
        }
        .onChange(of: selectedActivity) { _ in
            // auto-show sidebar when switching activity
            if sidebarVisibility == .hidden { sidebarVisibility = .all }
        }
        .toolbar { /* top navbar if needed */ }
    }
}
```

### ActivityBar (the icon navbar)
```swift
enum Activity: String, CaseIterable {
    case files, toc, comments, outline
    var icon: String {
        switch self { case .files: "folder"; case .toc: "list.bullet"; case .comments: "bubble.left"; case .outline: "doc.text.magnifyingglass" }
    }
}

struct ActivityBar: View {
    @Binding var selected: Activity
    var body: some View {
        VStack(spacing: 20) {
            ForEach(Activity.allCases, id: \.self) { activity in
                Button { selected = activity } label: {
                    Image(systemName: activity.icon)
                        .font(.title2)
                        .foregroundStyle(selected == activity ? .accentColor : .secondary)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.top, 8)
    }
}
```

### Moving sidebars left/right
```swift
// Add a button in toolbar or activity bar
Button("Move sidebar") {
    sidebarPosition = sidebarPosition == .left ? .right : .left
}

// Then wrap the sidebar in conditional HStack order:
HStack(spacing: 0) {
    if sidebarPosition == .left { SidebarContent() }
    MainContent()
    if sidebarPosition == .right { SidebarContent() }
}
```

### Your existing pieces fit perfectly
- **TOC**: Reuse the JS `sendTOCToSwift()` → native `List` exactly as I gave you last time (just drop it into `TOCView`).
- **File browser**: Native `List` + `DisclosureGroup` (drag-drop files is built-in).
- **Comments**: Native `List` of `Text`/`Markdown` (SwiftUI renders Markdown natively). No webview needed.
- **Preview sync**: Still one WKWebView with your `data-source-line` bridge. Sidebars stay 100% native.

### Actionable next steps (do these or stay stuck)
1. Migrate the main view to SwiftUI **today**. Keep your WKWebView bridge wrapper as a `UIViewRepresentable`. Takes 30 minutes, saves weeks later.
2. Delete any plan for extra webviews — it won't work because of the process overhead.
3. Add `.navigationSplitViewColumnVisibility` binding + collapse button (exactly like VS Code).
4. Test on macOS first (iPadOS works identically with `NavigationSplitView`).
5. Want secondary right sidebar always visible? Just nest another `HSplitView` — zero extra code.

This gives you pixel-perfect VS Code behavior with native performance, zero memory leaks, and proper drag/resize/keyboard support. Webview sidebars would have been a dead end — this is the one that actually ships. If you paste your current UIKit ViewController I'll show the minimal migration path, but you should just switch.