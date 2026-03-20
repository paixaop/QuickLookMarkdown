import XCTest
import WebKit
@testable import QuickMD

/// True E2E tests that run JS inside a real WKWebView.
/// Tests the full pipeline: markdown → HTML → WKWebView → JS selection → source line mapping → Swift algorithm.
final class EditorRendererSyncE2ETests: XCTestCase {

    private var webView: WKWebView!

    override func setUp() {
        super.setUp()
        let config = WKWebViewConfiguration()
        webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600), configuration: config)
    }

    /// Snapshot output directory — set via SNAPSHOT_DIR env var or defaults to QuickMDTests/Snapshots.
    private static let snapshotDir: String = {
        if let env = ProcessInfo.processInfo.environment["SNAPSHOT_DIR"], !env.isEmpty { return env }
        // Fallback: project source tree (works when running from Xcode or CLI)
        return (ProcessInfo.processInfo.environment["SRCROOT"] ?? "/Users/pedro/code/QuickLookMarkdown")
            + "/QuickMDTests/Snapshots"
    }()

    override func tearDown() {
        // Take a snapshot of the WebView at the end of every E2E test
        if let webView = webView {
            saveSnapshot(webView: webView, testName: name)
        }
        webView = nil
        super.tearDown()
    }

    // MARK: - Helpers

    /// Capture a PNG screenshot of the WebView and save to the snapshots directory.
    private func saveSnapshot(webView: WKWebView, testName: String) {
        let sanitized = testName
            .replacingOccurrences(of: "[", with: "")
            .replacingOccurrences(of: "]", with: "")
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: ".", with: "_")

        let dir = Self.snapshotDir
        try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

        let exp = expectation(description: "Snapshot \(sanitized)")
        let config = WKSnapshotConfiguration()
        let scale = NSScreen.main?.backingScaleFactor ?? 2.0
        config.snapshotWidth = NSNumber(value: 800.0 / scale)
        webView.takeSnapshot(with: config) { image, error in
            defer { exp.fulfill() }
            guard let image = image,
                  let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let png = rep.representation(using: .png, properties: [:]) else { return }
            let path = "\(dir)/\(sanitized).png"
            try? png.write(to: URL(fileURLWithPath: path))
        }
        wait(for: [exp], timeout: 5.0)
    }

    private func writeTempFile(_ content: String, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Core scripts injected via WKUserScript in the same order as makeNSView.
    /// Excludes large bundled libraries (highlight.js ~127KB, js-yaml ~39KB, mermaid ~2.9MB,
    /// katex, graphviz) which can fail to load in test environments. These aren't needed
    /// for DOM structure, interaction, and navigation E2E tests.
    private static let coreScripts: [String] = [
        MarkdownDocumentModel.utilsScript,
        MarkdownDocumentModel.themeScript,
        MarkdownDocumentModel.highlightRenderScript,
        MarkdownDocumentModel.lineNumbersScript,
        MarkdownDocumentModel.copyButtonScript,
        MarkdownDocumentModel.zoomOverlayScript,
        MarkdownDocumentModel.readingStatsScript,
        MarkdownDocumentModel.headingDataScript,
        MarkdownDocumentModel.fontSizeScript,
        MarkdownDocumentModel.jumpToLineScript,
        MarkdownDocumentModel.findScript,
        MarkdownDocumentModel.speakScript,
        MarkdownDocumentModel.emojiScript,
        MarkdownDocumentModel.footnotesScript,
        MarkdownDocumentModel.frontmatterScript,
        MarkdownDocumentModel.wordWrapScript,
        MarkdownDocumentModel.anchorLinksScript,
        MarkdownDocumentModel.presentationScript,
        MarkdownDocumentModel.linkClickScript,
        MarkdownDocumentModel.linkHoverScript,
        MarkdownDocumentModel.checkboxToggleScript,
        MarkdownDocumentModel.editorSyncScript,
        MarkdownDocumentModel.commentScript,
        MarkdownDocumentModel.contentUpdateScript,
    ]

    /// Load markdown into a real WKWebView with all scripts injected, wait for it to finish.
    /// Scripts are injected via evaluateJavaScript after page load (WKUserScript has issues
    /// with IntersectionObserver and other APIs in headless test WKWebViews).
    /// Each script is wrapped in try-catch to prevent one failure from blocking the rest.
    private func loadMarkdown(_ markdown: String) throws -> (html: String, model: MarkdownDocumentModel) {
        let url = writeTempFile(markdown, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        let loadExpectation = expectation(description: "WebView loaded")
        webView.loadHTMLString(html, baseURL: nil)

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Inject scripts sequentially via evaluateJavaScript.
            // Each wrapped in try-catch so one failure doesn't block the rest.
            var remaining = Self.coreScripts
            func injectNext() {
                guard !remaining.isEmpty else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        loadExpectation.fulfill()
                    }
                    return
                }
                let script = remaining.removeFirst()
                let wrapped = "try { \(script) } catch(e) {}"
                self.webView.evaluateJavaScript(wrapped) { _, _ in
                    injectNext()
                }
            }
            injectNext()
        }
        wait(for: [loadExpectation], timeout: 5.0)
        return (html, model)
    }

    /// Evaluate JS and return the result synchronously via expectation.
    private func evalJS(_ js: String) -> Any? {
        let exp = expectation(description: "JS eval")
        var result: Any?
        webView.evaluateJavaScript(js) { value, error in
            result = value
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        return result
    }

    /// Select text in the WKWebView using JS window.find() and return selection info.
    /// Uses window.find() to locate and select the nth occurrence of text.
    private func selectText(_ text: String, occurrence: Int = 1) -> Bool {
        // Clear any existing selection first
        _ = evalJS("window.getSelection().removeAllRanges()")

        // Use window.find() to select the nth occurrence
        // window.find() selects the next occurrence from the current selection/cursor position
        let js = """
        (function() {
            window.getSelection().removeAllRanges();
            // Move to start of document
            var range = document.createRange();
            var article = document.querySelector('article.markdown-body');
            if (!article) return false;
            range.setStart(article, 0);
            range.collapse(true);
            window.getSelection().addRange(range);

            // Find the nth occurrence
            for (var i = 0; i < \(occurrence); i++) {
                if (!window.find('\(text.replacingOccurrences(of: "'", with: "\\'"))', false, false, true)) return false;
            }
            return !window.getSelection().isCollapsed;
        })()
        """
        return evalJS(js) as? Bool ?? false
    }

    /// Get the source line info for the current selection using __getSelectionSourceInfo.
    private func getSelectionSourceInfo() -> (sourceLine: Int, offsetInBlock: Int, endOffsetInBlock: Int, text: String)? {
        let js = "window.__getSelectionSourceInfo ? JSON.stringify(__getSelectionSourceInfo()) : null"
        guard let jsonStr = evalJS(js) as? String,
              let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (
            sourceLine: dict["sourceLine"] as? Int ?? -1,
            offsetInBlock: dict["offsetInBlock"] as? Int ?? -1,
            endOffsetInBlock: dict["endOffsetInBlock"] as? Int ?? -1,
            text: dict["text"] as? String ?? ""
        )
    }

    /// Simulate a double-click by selecting a word and reading source mapping in one JS turn.
    /// (Splitting find + read across two `evaluateJavaScript` calls can lose the selection in WKWebView.)
    private func simulateDoubleClick(selectingWord word: String, occurrence: Int = 1) -> (sourceLine: Int, sourceCol: Int, offsetInBlock: Int, endOffsetInBlock: Int)? {
        let escaped = word.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
        let js = """
        (function() {
            window.getSelection().removeAllRanges();
            var range = document.createRange();
            var article = document.querySelector('article.markdown-body');
            if (!article) return null;
            range.setStart(article, 0);
            range.collapse(true);
            window.getSelection().addRange(range);
            for (var i = 0; i < \(occurrence); i++) {
                if (!window.find('\(escaped)', false, false, true)) return null;
            }
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0 || sel.isCollapsed) return null;
            var w = sel.toString().trim();
            if (!w) return null;

            var el = sel.anchorNode;
            while (el && el !== document.body) {
                if (el.nodeType === 1 && el.hasAttribute('data-source-line')) break;
                el = el.parentNode;
            }
            if (!el || !el.hasAttribute || !el.hasAttribute('data-source-line')) return null;

            var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
            var sourceCol = parseInt(el.getAttribute('data-source-col') || '1', 10);
            var offsetInBlock = -1;
            var endOffsetInBlock = -1;
            try {
                var r = sel.getRangeAt(0);
                // Compute offset excluding heading anchor text (injected "#" not in source)
                var anchorLen = 0;
                var anchors = el.querySelectorAll('.heading-anchor');
                for (var j = 0; j < anchors.length; j++) {
                    var aRange = document.createRange();
                    aRange.selectNode(anchors[j]);
                    if (aRange.compareBoundaryPoints(Range.END_TO_START, r) <= 0) {
                        anchorLen += anchors[j].textContent.length;
                    }
                }
                var preRange = document.createRange();
                preRange.setStart(el, 0);
                preRange.setEnd(r.startContainer, r.startOffset);
                offsetInBlock = Math.max(0, preRange.toString().length - anchorLen);
                var endRange = document.createRange();
                endRange.setStart(el, 0);
                endRange.setEnd(r.endContainer, r.endOffset);
                endOffsetInBlock = Math.max(0, endRange.toString().length - anchorLen);
            } catch(ex) {}

            return JSON.stringify({sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock, endOffsetInBlock: endOffsetInBlock});
        })()
        """
        guard let jsonStr = evalJS(js) as? String,
              let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (
            sourceLine: dict["sourceLine"] as? Int ?? -1,
            sourceCol: dict["sourceCol"] as? Int ?? -1,
            offsetInBlock: dict["offsetInBlock"] as? Int ?? -1,
            endOffsetInBlock: dict["endOffsetInBlock"] as? Int ?? -1
        )
    }

    // =========================================================================
    // MARK: - E2E: data-source-line attributes present in rendered HTML
    // =========================================================================

    func testRenderedHTMLHasSourceLineAttributes() throws {
        let (html, _) = try loadMarkdown("# Heading\n\nParagraph text.\n\n## Subheading")
        XCTAssertTrue(html.contains("data-source-line=\"1\""), "H1 should have source line 1")
        XCTAssertTrue(html.contains("data-source-line=\"3\""), "Paragraph should have source line 3")
        XCTAssertTrue(html.contains("data-source-line=\"5\""), "H2 should have source line 5")
    }

    func testRenderedListItemsHaveSourceLines() throws {
        let (html, _) = try loadMarkdown("- Apple\n- Banana\n- Cherry")
        XCTAssertTrue(html.contains("<li data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"2\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"3\""))
    }

    func testRenderedTableCellsHaveSourceLines() throws {
        let (html, _) = try loadMarkdown("| A | B |\n|---|---|\n| x | y |")
        XCTAssertTrue(html.contains("<table data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<th data-source-line="))
        XCTAssertTrue(html.contains("<td data-source-line="))
    }

    func testRenderedBlockquoteHasSourceLine() throws {
        let (html, _) = try loadMarkdown("Text.\n\n> Quote here.")
        XCTAssertTrue(html.contains("<blockquote data-source-line=\"3\""))
    }

    func testRenderedCodeBlockHasSourceLine() throws {
        let (html, _) = try loadMarkdown("Text.\n\n```python\nx = 1\n```")
        XCTAssertTrue(html.contains("<pre data-source-line=\"3\""))
    }

    // =========================================================================
    // MARK: - E2E: JS selection + source info retrieval
    // =========================================================================

    func testSelectTextReturnsSourceInfo() throws {
        let (_, _) = try loadMarkdown("# Hello World\n\nSome paragraph text.")
        guard selectText("paragraph") else {
            XCTFail("Should be able to select 'paragraph'"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info, "Should get source info for selected text")
        XCTAssertEqual(info?.sourceLine, 3, "Paragraph is at source line 3")
        XCTAssertEqual(info?.text, "paragraph")
    }

    func testSelectWordInHeading() throws {
        let (_, _) = try loadMarkdown("# Important Title\n\nBody text.")
        guard selectText("Important") else {
            XCTFail("Should select 'Important'"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.sourceLine, 1, "Heading is at source line 1")
    }

    func testSelectWordInListItem() throws {
        let (_, _) = try loadMarkdown("- first item\n- second item\n- third item")
        guard selectText("second") else {
            XCTFail("Should select 'second'"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.sourceLine, 2, "Second list item is at source line 2")
    }

    func testSelectWordInBlockquote() throws {
        let (_, _) = try loadMarkdown("Normal text.\n\n> Quoted content here.")
        guard selectText("Quoted") else {
            XCTFail("Should select 'Quoted'"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info)
        // The blockquote's <p> inside <blockquote> may have its own source line
        XCTAssertGreaterThanOrEqual(info?.sourceLine ?? 0, 3)
    }

    // =========================================================================
    // MARK: - E2E: duplicate word disambiguation via source line
    // =========================================================================

    func testDuplicateWordDifferentParagraphsE2E() throws {
        let md = "The word apple is here.\n\nThe word apple is there.\n\nThe word apple is everywhere."
        let (_, model) = try loadMarkdown(md)

        // Select first "apple" (occurrence 1)
        let info1 = simulateDoubleClick(selectingWord: "apple", occurrence: 1)
        XCTAssertNotNil(info1, "Should get info for first apple")
        XCTAssertEqual(info1?.sourceLine, 1, "First apple is in paragraph at line 1")

        // Select second "apple" (occurrence 2)
        let info2 = simulateDoubleClick(selectingWord: "apple", occurrence: 2)
        XCTAssertNotNil(info2, "Should get info for second apple")
        XCTAssertEqual(info2?.sourceLine, 3, "Second apple is in paragraph at line 3")

        // Select third "apple" (occurrence 3)
        let info3 = simulateDoubleClick(selectingWord: "apple", occurrence: 3)
        XCTAssertNotNil(info3, "Should get info for third apple")
        XCTAssertEqual(info3?.sourceLine, 5, "Third apple is in paragraph at line 5")

        // Now verify the Swift algorithm picks the right range for each
        if let info1 = info1 {
            let range1 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info1.sourceLine, offsetInBlock: info1.offsetInBlock, endOffsetInBlock: info1.endOffsetInBlock, frontmatterLineCount: model.frontmatterLineCount, source: model.rawContent)
            XCTAssertNotNil(range1)
            XCTAssertLessThan(range1!.location, 25, "First apple should be in first paragraph")
        }
        if let info2 = info2 {
            let range2 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info2.sourceLine, offsetInBlock: info2.offsetInBlock, endOffsetInBlock: info2.endOffsetInBlock, frontmatterLineCount: model.frontmatterLineCount, source: model.rawContent)
            XCTAssertNotNil(range2)
            XCTAssertGreaterThan(range2!.location, 25, "Second apple should be past first paragraph")
        }
        if let info3 = info3 {
            let range3 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info3.sourceLine, offsetInBlock: info3.offsetInBlock, endOffsetInBlock: info3.endOffsetInBlock, frontmatterLineCount: model.frontmatterLineCount, source: model.rawContent)
            XCTAssertNotNil(range3)
            XCTAssertGreaterThan(range3!.location, 50, "Third apple should be in last paragraph")
        }
    }

    func testDuplicateWordInHeadingsE2E() throws {
        let md = "# Section\n\nContent one.\n\n## Section\n\nContent two.\n\n### Section\n\nContent three."
        let (_, model) = try loadMarkdown(md)

        let info1 = simulateDoubleClick(selectingWord: "Section", occurrence: 1)
        let info2 = simulateDoubleClick(selectingWord: "Section", occurrence: 2)
        let info3 = simulateDoubleClick(selectingWord: "Section", occurrence: 3)

        XCTAssertNotNil(info1)
        XCTAssertNotNil(info2)
        XCTAssertNotNil(info3)

        // Each should have different source lines
        if let i1 = info1, let i2 = info2, let i3 = info3 {
            XCTAssertLessThan(i1.sourceLine, i2.sourceLine, "H1 should be before H2")
            XCTAssertLessThan(i2.sourceLine, i3.sourceLine, "H2 should be before H3")

            let r1 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: i1.sourceLine, offsetInBlock: i1.offsetInBlock, endOffsetInBlock: i1.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            let r2 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: i2.sourceLine, offsetInBlock: i2.offsetInBlock, endOffsetInBlock: i2.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            let r3 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: i3.sourceLine, offsetInBlock: i3.offsetInBlock, endOffsetInBlock: i3.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            XCTAssertNotNil(r1)
            XCTAssertNotNil(r2)
            XCTAssertNotNil(r3)
            XCTAssertLessThan(r1!.location, r2!.location)
            XCTAssertLessThan(r2!.location, r3!.location)
        }
    }

    func testDuplicateWordInMixedElements() throws {
        let md = "# data\n\nThe data is here.\n\n- data in list\n\n> data in quote"
        let (_, model) = try loadMarkdown(md)

        let info1 = simulateDoubleClick(selectingWord: "data", occurrence: 1) // heading
        let info2 = simulateDoubleClick(selectingWord: "data", occurrence: 2) // paragraph
        let info3 = simulateDoubleClick(selectingWord: "data", occurrence: 3) // list
        let info4 = simulateDoubleClick(selectingWord: "data", occurrence: 4) // blockquote

        // All should have different source lines
        let lines = [info1?.sourceLine, info2?.sourceLine, info3?.sourceLine, info4?.sourceLine].compactMap { $0 }
        XCTAssertGreaterThanOrEqual(lines.count, 3, "Should find data in at least 3 locations")

        // Verify Swift algorithm disambiguates correctly
        for info in [info1, info2, info3, info4].compactMap({ $0 }) {
            let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, endOffsetInBlock: info.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            XCTAssertNotNil(range, "Should find range for data at line \(info.sourceLine)")
        }
    }

    // =========================================================================
    // MARK: - E2E: offsetInBlock correctness
    // =========================================================================

    func testOffsetInBlockIsNonNegative() throws {
        let (_, _) = try loadMarkdown("This is a test paragraph with several words.")
        guard selectText("test") else { XCTFail("Should select"); return }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info)
        XCTAssertGreaterThanOrEqual(info?.offsetInBlock ?? -1, 0, "offsetInBlock should be non-negative")
    }

    func testOffsetInBlockDiffersForDifferentWords() throws {
        let (_, _) = try loadMarkdown("First middle last in one paragraph.")
        let info1: (sourceLine: Int, offsetInBlock: Int, endOffsetInBlock: Int, text: String)? = {
            guard selectText("First") else { return nil }
            return getSelectionSourceInfo()
        }()
        let info2: (sourceLine: Int, offsetInBlock: Int, endOffsetInBlock: Int, text: String)? = {
            guard selectText("last") else { return nil }
            return getSelectionSourceInfo()
        }()
        XCTAssertNotNil(info1)
        XCTAssertNotNil(info2)
        if let i1 = info1, let i2 = info2 {
            XCTAssertLessThan(i1.offsetInBlock, i2.offsetInBlock, "First word should have smaller offset than last")
        }
    }

    // =========================================================================
    // MARK: - E2E: comment annotations interaction
    // =========================================================================

    func testCommentAnnotationSourceInfo() throws {
        let md = "Normal text.\n\nSome <!-- COMMENT: note -->annotated<!-- /COMMENT --> word.\n\nMore text."
        let (_, _) = try loadMarkdown(md)

        // The word "annotated" should still have source info from its parent block
        guard selectText("annotated") else { XCTFail("Should select annotated"); return }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info, "Should get source info even for text inside comment marks")
        // The paragraph containing the comment is at line 3
        XCTAssertEqual(info?.sourceLine, 3)
    }

    func testCommentAtPointHelper() throws {
        let md = "Some <!-- COMMENT: test note -->annotated text<!-- /COMMENT --> here."
        let (_, _) = try loadMarkdown(md)

        // __setupComments should have run — verify marks exist
        let markCount = evalJS("document.querySelectorAll('.qmd-comment').length") as? Int ?? 0
        XCTAssertEqual(markCount, 1, "Should have one comment mark")

        // Verify the comment data is correct
        let commentText = evalJS("document.querySelector('.qmd-comment').getAttribute('data-comment')") as? String
        XCTAssertEqual(commentText, "test note")
    }

    // =========================================================================
    // MARK: - E2E: __getSelectionText helper
    // =========================================================================

    func testGetSelectionTextReturnsSelectedText() throws {
        let (_, _) = try loadMarkdown("Hello World paragraph.")
        guard selectText("World") else { XCTFail("Should select"); return }
        let text = evalJS("window.__getSelectionText ? __getSelectionText() : ''") as? String
        XCTAssertEqual(text, "World")
    }

    func testGetSelectionTextReturnsEmptyWhenNoSelection() throws {
        let (_, _) = try loadMarkdown("Hello World.")
        _ = evalJS("window.getSelection().removeAllRanges()")
        let text = evalJS("window.__getSelectionText ? __getSelectionText() : ''") as? String
        XCTAssertEqual(text, "")
    }

    // =========================================================================
    // MARK: - E2E: sidebar and TOC structure in DOM
    // =========================================================================

    func testSidebarNotInDOM() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.")
        let exists = evalJS("document.getElementById('sidebar-container') !== null") as? Bool
        XCTAssertFalse(exists ?? true, "Sidebar should NOT be in DOM (native SwiftUI)")
    }

    func testHeadingDataScriptAssignsIDs() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.\n\n## Sub\n\nMore.")
        let rebuildFn = evalJS("typeof window.__rebuildHeadingData") as? String
        XCTAssertEqual(rebuildFn, "function", "Heading data script should define __rebuildHeadingData")
        let h1Id = evalJS("document.querySelector('h1')?.id") as? String
        XCTAssertEqual(h1Id, "heading", "H1 should have slug ID assigned by heading data script")
    }

    // =========================================================================
    // MARK: - E2E: TOC heading IDs and navigation
    // =========================================================================

    func testTOCHeadingsHaveGitHubSlugIDs() throws {
        let md = """
        # Introduction

        Some text.

        ## Getting Started

        More text.

        ### TLS Termination

        Details here.

        ## Security & Auth

        Auth details.
        """
        let (_, _) = try loadMarkdown(md)

        // Verify all headings got slug IDs from the TOC script
        let introID = evalJS("document.querySelector('h1')?.id") as? String
        XCTAssertEqual(introID, "introduction", "H1 should have GitHub-style slug ID")

        let gettingStartedID = evalJS("document.querySelector('h2')?.id") as? String
        XCTAssertEqual(gettingStartedID, "getting-started", "H2 should have slug ID with dashes")

        let tlsID = evalJS("document.querySelector('h3')?.id") as? String
        XCTAssertEqual(tlsID, "tls-termination", "H3 should have slug ID")

        let secAuthID = evalJS("document.querySelectorAll('h2')[1]?.id") as? String
        // The & is stripped by the slug regex, leaving "security-auth" or "security--auth"
        XCTAssertNotNil(secAuthID)
        XCTAssertTrue(secAuthID!.contains("security"), "H2 with & should have slug ID containing 'security'")
    }

    func testHeadingDataScriptAssignsIDsToAllHeadings() throws {
        let md = """
        # Title

        Text.

        ## Section One

        Text.

        ## Section Two

        Text.

        ### Subsection

        Text.
        """
        let (_, _) = try loadMarkdown(md)

        // headingDataScript should assign slug IDs to all headings
        let h1Id = evalJS("document.querySelector('h1')?.id") as? String
        XCTAssertEqual(h1Id, "title", "H1 should have slug ID")
        let h2Count = evalJS("document.querySelectorAll('h2[id]').length") as? Int
        XCTAssertEqual(h2Count, 2, "Both H2s should have IDs")
        let h3Id = evalJS("document.querySelector('h3')?.id") as? String
        XCTAssertEqual(h3Id, "subsection", "H3 should have slug ID")
    }

    func testHeadingSlugIDsAreCorrect() throws {
        let md = """
        # Main Title

        Intro.

        ## First Section

        Content.
        """
        let (_, _) = try loadMarkdown(md)

        let firstID = evalJS("document.querySelector('h1')?.id") as? String
        XCTAssertEqual(firstID, "main-title", "H1 should have slug 'main-title'")

        let secondID = evalJS("document.querySelector('h2')?.id") as? String
        XCTAssertEqual(secondID, "first-section", "H2 should have slug 'first-section'")
    }

    func testAnchorLinksAddedToHeadings() throws {
        let md = "# Hello World\n\nText.\n\n## Sub Heading\n\nMore text."
        let (_, _) = try loadMarkdown(md)

        // Re-run anchor links setup — in test env script execution order isn't guaranteed
        _ = evalJS("if(window.__setupAnchorLinks) __setupAnchorLinks()")

        let anchorCount = evalJS("document.querySelectorAll('.heading-anchor').length") as? Int ?? 0
        XCTAssertEqual(anchorCount, 2, "Each heading should get an anchor link")

        let firstAnchorHref = evalJS("document.querySelector('.heading-anchor')?.getAttribute('href')") as? String
        XCTAssertEqual(firstAnchorHref, "#hello-world")
    }

    func testScrollToFragmentViaElementId() throws {
        // Build a document with multiple sections
        let md = """
        # Top Heading

        Some intro text.

        ## Target Section

        Target content here.

        ## Another Section

        More content.
        """

        let (_, _) = try loadMarkdown(md)

        // Verify the target heading exists with the right ID
        let targetID = evalJS("document.getElementById('target-section')?.id") as? String
        XCTAssertEqual(targetID, "target-section", "Target heading should have the correct slug ID")

        // Verify scrollIntoView can be called without error (same JS as our didFinish handler)
        let scrollResult = evalJS("""
            (function() {
                var el = document.getElementById('target-section');
                if (!el) return 'not-found';
                el.scrollIntoView({behavior:'auto'});
                return 'ok';
            })()
        """) as? String
        XCTAssertEqual(scrollResult, "ok", "scrollIntoView should execute without error")
    }

    func testPendingFragmentNotSetOnPlainLoad() throws {
        // Verify that loading a file without a fragment doesn't set pendingFragment
        let url = writeTempFile("# Test\n\nContent.", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        XCTAssertNil(model.pendingFragment, "Plain load should not set pendingFragment")
    }

    func testPendingFragmentSetOnNavigateTo() throws {
        let url = writeTempFile("# Test\n\nContent.", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        // Simulate navigating to a URL with fragment
        let fragmentURL = url.appendingPathComponent("").deletingLastPathComponent()
            .appendingPathComponent(url.lastPathComponent)
        var components = URLComponents(url: fragmentURL, resolvingAgainstBaseURL: false)!
        components.fragment = "test-section"
        let urlWithFragment = components.url!

        model.navigateTo(urlWithFragment)
        // pendingFragment should be set (it gets consumed by didFinish in the real app)
        // Note: navigateTo calls load which resets html, triggering didFinish in real scenario
        // Here we just verify the Swift side sets it correctly
        XCTAssertEqual(model.pendingFragment, "test-section",
                       "navigateTo with fragment URL should set pendingFragment")
    }

    func testPendingFragmentNotSetOnFileWatcherReload() throws {
        // Simulates what happens when a file watcher triggers a reload:
        // load(from:) is called with the currentURL (which may have a fragment from a previous navigation).
        // pendingFragment should NOT be set by load(from:).
        let url = writeTempFile("# Test\n\nContent.", ext: "md")
        let model = MarkdownDocumentModel()

        // First navigate to set a fragment
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.fragment = "some-heading"
        model.navigateTo(components.url!)

        // Clear it (simulating didFinish consuming it)
        model.pendingFragment = nil

        // Simulate file watcher reload — calls load(from:) directly with currentURL
        model.load(from: model.currentURL ?? url)

        XCTAssertNil(model.pendingFragment,
                     "File watcher reload (load(from:)) should NOT re-set pendingFragment")
    }

    // =========================================================================
    // MARK: - E2E: full round-trip (markdown → render → select → find range)
    // =========================================================================

    func testFullRoundTripSimple() throws {
        let md = "# Title\n\nFirst paragraph.\n\n## Subtitle\n\nSecond paragraph."
        let (_, model) = try loadMarkdown(md)

        guard selectText("paragraph", occurrence: 2) else { XCTFail("Should select second 'paragraph'"); return }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info)

        if let info = info {
            let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, endOffsetInBlock: info.endOffsetInBlock, frontmatterLineCount: model.frontmatterLineCount, source: model.rawContent)
            XCTAssertNotNil(range)
            // "Second paragraph" is in the second paragraph — verify it's past the first
            let firstParagraphEnd = (model.rawContent as NSString).range(of: "First paragraph.").location + "First paragraph.".count
            XCTAssertGreaterThan(range!.location, firstParagraphEnd, "Should find the second 'paragraph', not the first")
        }
    }

    func testFullRoundTripWithFormatting() throws {
        // Use distinctive tokens: reading-stats.js prepends "… words · … min read" to the article,
        // and window.find('word') matches the substring "word" inside "words" before real content.
        let md = "The **qmdBoldToken** is strong.\n\nThe *qmdItalicToken* is emphasis."
        let (_, model) = try loadMarkdown(md)

        let info1 = simulateDoubleClick(selectingWord: "qmdBoldToken", occurrence: 1)
        let info2 = simulateDoubleClick(selectingWord: "qmdItalicToken", occurrence: 1)

        XCTAssertNotNil(info1)
        XCTAssertNotNil(info2)

        if let i1 = info1, let i2 = info2 {
            let r1 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: i1.sourceLine, offsetInBlock: i1.offsetInBlock, endOffsetInBlock: i1.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            let r2 = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: i2.sourceLine, offsetInBlock: i2.offsetInBlock, endOffsetInBlock: i2.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
            XCTAssertNotNil(r1)
            XCTAssertNotNil(r2)
            XCTAssertNotEqual(r1!.location, r2!.location, "Should find different occurrences")
        }
    }

    func testFullRoundTripComplexDocument() throws {
        let md = """
        # Introduction

        The concept of testing is fundamental.

        ## Methods

        - Testing with unit tests
        - Testing with integration tests
        - Testing with E2E tests

        ## Results

        The testing showed good results.

        > Testing is essential for quality.

        ## Conclusion

        In conclusion, testing matters.
        """
        let (_, model) = try loadMarkdown(md)

        // "testing" appears in: paragraph (line 3), 3 list items (lines 7-9), paragraph (line 13), blockquote (line 15), paragraph (line 19)
        // Try to select each and verify disambiguation works
        var foundLines: [Int] = []
        for i in 1...5 {
            if let info = simulateDoubleClick(selectingWord: "testing", occurrence: i) {
                foundLines.append(info.sourceLine)
                let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, endOffsetInBlock: info.endOffsetInBlock, frontmatterLineCount: 0, source: model.rawContent)
                XCTAssertNotNil(range, "Should find range for occurrence \(i) at line \(info.sourceLine)")
            }
        }
        // Should have found testing in at least 4 distinct source lines
        let uniqueLines = Set(foundLines)
        XCTAssertGreaterThanOrEqual(uniqueLines.count, 4, "Should disambiguate 'testing' across at least 4 different source lines, got: \(foundLines)")
    }

    // =========================================================================
    // MARK: - E2E: Comment placement on architecture-style document
    // =========================================================================

    /// Fixture: architecture spec with HTML comment header, heading with &,
    /// bullet list with bold + inline formatting, table, and cross-references.
    private let architectureFixture = """
    <!-- Migrated from: design-overview.md on 2026-02-20 -->

    # Principles & Design Goals

    - **Reliability-first** distributed task scheduler for AI workloads
    - **Zero-downtime** deployments — rolling updates with health checks
    - **Low latency** request routing with in-memory caching on hot path
    - **Plugin-extensible** middleware via sandboxed WASM modules and declarative rules
    - **End-to-end encryption** across all internal service communication
    - **Observability** via structured logging, OpenTelemetry traces, and Prometheus metrics
    - **Configuration as code** — all settings stored in version-controlled YAML
    - **Tenant isolation** — each workspace runs in a dedicated namespace
    - **Rate limiting** with per-client token bucket and sliding window counters
    - **Backward compatible** — public API changes require deprecation cycle (minimum 2 releases)
    - **Composable pipeline** — processors consume [TypedMessage](../04-components/typed-message.md) by content type, not by transport. Adding protocols is a 1-file change.

    ## Deployment Model

    v3 uses a multi-region active-active architecture. Each region operates independently with eventual consistency. All API keys, quotas, and routing rules within a region belong to one control plane. There is no cross-region request forwarding, no shared state between regions, and no global lock coordination. Regions requiring synchronization use explicit replication streams.

    ## Team Responsibilities

    | Team | Function | Key Concern |
    |---|---|---|
    | Platform Engineers | Build and maintain the core scheduler | Request routing accuracy, failover latency, resource utilization |
    | DevOps | Deploy and operate production clusters | Zero-downtime deploys, rollback procedures, capacity planning |
    | Security | Define and enforce access policies | mTLS enforcement, secret rotation, audit trail completeness |
    | Compliance | Ensure regulatory adherence | Data residency rules, encryption at rest (AES-256), retention policies |
    | Plugin Authors | Extend functionality via WASM plugins | SDK stability, sandbox resource limits, versioned plugin registry |

    Quality attributes per team are documented in [Section 8 — Quality Model](../08-quality-model/README.md).
    """

    /// Test that each list item in the fixture gets a unique data-source-line.
    func testArchitectureFixtureListItemsHaveUniqueSourceLines() throws {
        let (html, _) = try loadMarkdown(architectureFixture)

        // Each <li> should have a data-source-line attribute
        let liPattern = try NSRegularExpression(pattern: #"<li data-source-line="(\d+)""#)
        let nsHTML = html as NSString
        let matches = liPattern.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        let liLines = matches.map { Int(nsHTML.substring(with: $0.range(at: 1)))! }

        XCTAssertEqual(liLines.count, 11, "Should have 11 list items, got \(liLines.count)")
        // All should be unique
        let uniqueLines = Set(liLines)
        XCTAssertEqual(uniqueLines.count, 11, "All 11 list items should have unique source lines")
    }

    /// Test selecting each list item's bold keyword and verifying correct source line mapping.
    func testArchitectureFixtureSelectEachListItemBoldKeyword() throws {
        let (_, model) = try loadMarkdown(architectureFixture)

        // The bold keywords in each list item (first word after **)
        let boldKeywords = [
            "Reliability-first",
            "Zero-downtime",
            "Low latency",       // two words
            "Plugin-extensible",
            "End-to-end encryption", // multi-word
            "Observability",
            "Configuration as code", // multi-word
            "Tenant isolation",
            "Rate limiting",
            "Backward compatible",
            "Composable pipeline"
        ]

        var foundSourceLines: [Int] = []

        for (i, keyword) in boldKeywords.enumerated() {
            // Select the keyword — use just the first word for reliable window.find()
            let searchWord = keyword.components(separatedBy: " ").first!
            guard selectText(searchWord, occurrence: 1) else {
                XCTFail("Failed to select '\(searchWord)' for list item \(i)")
                continue
            }
            guard let info = getSelectionSourceInfo() else {
                XCTFail("No source info for '\(searchWord)' in list item \(i)")
                continue
            }
            XCTAssertGreaterThan(info.sourceLine, 0, "List item \(i) (\(searchWord)) should have positive source line")
            foundSourceLines.append(info.sourceLine)
        }

        // All source lines should be different (each list item on its own line)
        let unique = Set(foundSourceLines)
        XCTAssertEqual(unique.count, foundSourceLines.count,
                       "Each list item should have a unique source line. Got: \(foundSourceLines)")
    }

    /// E2E: simulate adding a comment to each list item via sourceRangeFromRenderedOffsets (the same path as addCommentToSource).
    func testArchitectureFixtureCommentEachListItem() throws {
        let (_, model) = try loadMarkdown(architectureFixture)
        let source = model.rawContent

        // For each list item, select a unique word, get source info, then verify sourceRangeFromRenderedOffsets
        // picks a position INSIDE that specific list item line
        let uniqueWords = [
            "Reliability-first",
            "Zero-downtime",
            "latency",
            "Plugin-extensible",
            "End-to-end",
            "Observability",
            "Configuration",
            "Tenant",
            "limiting",
            "Backward",
            "Composable"
        ]

        let lines = source.components(separatedBy: "\n")

        for (i, word) in uniqueWords.enumerated() {
            guard selectText(word, occurrence: 1) else {
                XCTFail("Cannot select '\(word)' for item \(i)")
                continue
            }
            guard let info = getSelectionSourceInfo() else {
                XCTFail("No source info for '\(word)' at item \(i)")
                continue
            }

            // Use sourceRangeFromRenderedOffsets — same algorithm as addCommentToSource
            guard let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(
                sourceLine: info.sourceLine,
                offsetInBlock: info.offsetInBlock,
                endOffsetInBlock: info.endOffsetInBlock,
                frontmatterLineCount: model.frontmatterLineCount,
                source: source
            ) else {
                XCTFail("sourceRangeFromRenderedOffsets returned nil for '\(word)' at line \(info.sourceLine)")
                continue
            }

            // Verify the found range is actually within the correct list item line
            let matched = (source as NSString).substring(with: range)
            XCTAssertTrue(matched.lowercased().contains(word.lowercased()),
                          "Matched text '\(matched)' should contain '\(word)'")

            // Verify the range falls on a line that starts with "- " (a list item)
            let adjustedLine = info.sourceLine + model.frontmatterLineCount - 1
            if adjustedLine >= 0 && adjustedLine < lines.count {
                let line = lines[adjustedLine]
                XCTAssertTrue(line.trimmingCharacters(in: .whitespaces).hasPrefix("- "),
                              "Source line \(adjustedLine) should be a list item: '\(line)'")
                XCTAssertTrue(line.contains(word),
                              "Source line should contain '\(word)': '\(line)'")
            }

            // Verify the range location is within the line's character range in the source
            var lineStart = 0
            for j in 0..<adjustedLine { lineStart += lines[j].count + 1 }
            let lineEnd = lineStart + lines[adjustedLine].count
            XCTAssertGreaterThanOrEqual(range.location, lineStart,
                                        "'\(word)' range start \(range.location) should be >= line start \(lineStart)")
            XCTAssertLessThanOrEqual(range.location + range.length, lineEnd + 1,
                                     "'\(word)' range end \(range.location + range.length) should be <= line end \(lineEnd)")
        }
    }

    /// E2E: verify addComment actually produces correct markdown with comment markers for each list item.
    func testArchitectureFixtureAddCommentProducesCorrectMarkdown() throws {
        let (_, model) = try loadMarkdown(architectureFixture)
        var source = model.rawContent

        // Add a comment to the first list item's bold word
        guard selectText("Reliability-first", occurrence: 1) else {
            XCTFail("Cannot select Reliability-first"); return
        }
        guard let info = getSelectionSourceInfo() else {
            XCTFail("No source info"); return
        }
        guard let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: info.sourceLine,
            offsetInBlock: info.offsetInBlock,
            endOffsetInBlock: info.endOffsetInBlock,
            frontmatterLineCount: model.frontmatterLineCount,
            source: source
        ) else {
            XCTFail("sourceRangeFromRenderedOffsets returned nil"); return
        }

        let updated = MarkdownDocumentModel.addComment(around: range, comment: "needs review", in: source)
        XCTAssertTrue(updated.contains("<!-- COMMENT: needs review -->"), "Should have comment marker")
        XCTAssertTrue(updated.contains("Reliability-first"), "Should preserve the text")
        XCTAssertTrue(updated.contains("<!-- /COMMENT -->"), "Should have closing marker")

        // The comment should be on the first list item line
        let updatedLines = updated.components(separatedBy: "\n")
        let commentLine = updatedLines.first(where: { $0.contains("<!-- COMMENT: needs review -->") })
        XCTAssertNotNil(commentLine, "Should find the comment line")
        XCTAssertTrue(commentLine!.contains("- **"), "Comment should be on a list item line")
    }

    /// E2E: verify the heading with & character gets correct source line.
    func testArchitectureFixtureHeadingWithAmpersand() throws {
        let (_, _) = try loadMarkdown(architectureFixture)

        // Select "Principles" from the heading "# Principles & Design Goals"
        guard selectText("Principles", occurrence: 1) else {
            XCTFail("Cannot select 'Principles'"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info, "Should get source info for heading text")
        XCTAssertGreaterThan(info?.sourceLine ?? 0, 0, "Should have valid source line")
    }

    /// E2E: verify the HTML comment at top does NOT interfere with comment annotations.
    func testArchitectureFixtureHTMLCommentDoesNotInterfere() throws {
        let (_, _) = try loadMarkdown(architectureFixture)

        // The <!-- Migrated from: ... --> should NOT produce <mark class="qmd-comment"> elements in the DOM
        let markCount = evalJS("document.querySelectorAll('.qmd-comment').length") as? Int ?? 0
        XCTAssertEqual(markCount, 0, "HTML comment should not produce comment annotation marks in DOM")

        // Heading should still render
        let hasHeading = evalJS("document.querySelector('h1') !== null") as? Bool ?? false
        XCTAssertTrue(hasHeading, "Heading should still render")
    }

    /// E2E: verify table cells have source lines and don't confuse the comment algorithm.
    func testArchitectureFixtureTableCellsHaveSourceLines() throws {
        let (html, model) = try loadMarkdown(architectureFixture)

        XCTAssertTrue(html.contains("<td data-source-line="), "Table cells should have source lines")
        XCTAssertTrue(html.contains("<th data-source-line="), "Table headers should have source lines")

        // Select a word that appears in both the list and the table
        // "sandbox" appears in list item 4 and table row 5
        guard selectText("sandbox", occurrence: 1) else {
            XCTFail("Cannot select first 'sandbox'"); return
        }
        let info1 = getSelectionSourceInfo()

        guard selectText("sandbox", occurrence: 2) else {
            // May not have a second occurrence — that's OK
            return
        }
        let info2 = getSelectionSourceInfo()

        if let i1 = info1, let i2 = info2 {
            XCTAssertNotEqual(i1.sourceLine, i2.sourceLine,
                              "Same word in list vs table should have different source lines")
        }
    }

    /// E2E: verify cross-reference link renders and doesn't break source line mapping.
    func testArchitectureFixtureCrossReferenceLink() throws {
        let (html, _) = try loadMarkdown(architectureFixture)

        // The last list item has a [TypedMessage](url) link
        XCTAssertTrue(html.contains("TypedMessage"), "Should render link text")
        XCTAssertTrue(html.contains("typed-message.md"), "Should preserve link href")

        // Select TypedMessage — should have a valid source line
        guard selectText("TypedMessage", occurrence: 1) else {
            XCTFail("Cannot select TypedMessage"); return
        }
        let info = getSelectionSourceInfo()
        XCTAssertNotNil(info, "Should get source info for link text inside list item")
    }

    /// E2E: stress test — add comments to ALL 11 list items and verify each one lands correctly.
    func testArchitectureFixtureCommentAll11ListItems() throws {
        let (_, model) = try loadMarkdown(architectureFixture)
        let source = model.rawContent
        let lines = source.components(separatedBy: "\n")

        // Find unique words for each list item that won't match elsewhere
        let targets = [
            "Reliability-first",
            "Zero-downtime",
            "latency",
            "Plugin-extensible",
            "encryption",
            "Observability",
            "Configuration",
            "namespace",
            "limiting",
            "deprecation",
            "Composable"
        ]

        var allRanges: [(word: String, range: NSRange, sourceLine: Int)] = []

        for (i, word) in targets.enumerated() {
            guard selectText(word, occurrence: 1) else {
                XCTFail("Cannot select '\(word)' (#\(i))"); continue
            }
            guard let info = getSelectionSourceInfo() else {
                XCTFail("No source info for '\(word)' (#\(i))"); continue
            }
            guard let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(
                sourceLine: info.sourceLine,
                offsetInBlock: info.offsetInBlock,
                endOffsetInBlock: info.endOffsetInBlock,
                frontmatterLineCount: model.frontmatterLineCount,
                source: source
            ) else {
                XCTFail("sourceRangeFromRenderedOffsets nil for '\(word)' (#\(i))"); continue
            }
            allRanges.append((word: word, range: range, sourceLine: info.sourceLine))
        }

        XCTAssertEqual(allRanges.count, 11, "Should find ranges for all 11 list items")

        // Verify no two ranges overlap
        let sorted = allRanges.sorted(by: { $0.range.location < $1.range.location })
        for i in 0..<(sorted.count - 1) {
            let end = sorted[i].range.location + sorted[i].range.length
            XCTAssertLessThanOrEqual(end, sorted[i + 1].range.location,
                                     "Range for '\(sorted[i].word)' should not overlap with '\(sorted[i + 1].word)'")
        }

        // Verify all source lines are different
        let sourceLines = allRanges.map(\.sourceLine)
        XCTAssertEqual(Set(sourceLines).count, 11,
                       "All 11 items should have unique source lines: \(sourceLines)")

        // Verify each range is on a list item line
        for item in allRanges {
            let adjLine = item.sourceLine + model.frontmatterLineCount - 1
            if adjLine >= 0 && adjLine < lines.count {
                XCTAssertTrue(lines[adjLine].trimmingCharacters(in: .whitespaces).hasPrefix("- "),
                              "'\(item.word)' should be on a list item line, got: '\(lines[adjLine])'")
            }
        }
    }

    // MARK: - Incremental Content Update E2E Tests

    /// Load markdown with morphdom + contentUpdateScript injected, for testing __updateContent.
    /// Same as loadMarkdown but kept for backward compatibility — now uses allScripts too.
    private func loadMarkdownWithUpdateScript(_ markdown: String) throws -> (html: String, model: MarkdownDocumentModel) {
        return try loadMarkdown(markdown)
    }

    /// Push an incremental update to the WebView and wait for it to apply.
    private func pushUpdate(newMarkdown: String) {
        let bodyHTML = MarkdownDocumentModel.markdownBodyHTML(from: newMarkdown)
        let escaped = bodyHTML
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "`", with: "\\`")
            .replacingOccurrences(of: "${", with: "\\${")
        let js = "if(window.__updateContent) { __updateContent(`\(escaped)`); true } else { false }"
        let result = evalJS(js)
        XCTAssertEqual(result as? Bool, true, "__updateContent should be defined and return true")
    }

    /// Get the text content of the article.markdown-body element.
    private func getArticleText() -> String {
        let result = evalJS("document.querySelector('article.markdown-body')?.textContent || ''")
        return result as? String ?? ""
    }

    /// Count elements matching a CSS selector inside the article.
    private func countElements(_ selector: String) -> Int {
        let js = "document.querySelectorAll('article.markdown-body \(selector)').length"
        return evalJS(js) as? Int ?? 0
    }

    // MARK: - Tests

    func testIncrementalUpdate_addParagraph() throws {
        let initial = "# Hello\n\nWorld"
        _ = try loadMarkdownWithUpdateScript(initial)

        let articleText = getArticleText()
        XCTAssertTrue(articleText.contains("Hello"), "Initial render should contain 'Hello'")
        XCTAssertTrue(articleText.contains("World"), "Initial render should contain 'World'")
        XCTAssertFalse(articleText.contains("New paragraph"), "Should not contain 'New paragraph' initially")

        pushUpdate(newMarkdown: "# Hello\n\nWorld\n\nNew paragraph")

        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Hello"), "Should still contain 'Hello' after update")
        XCTAssertTrue(updatedText.contains("World"), "Should still contain 'World' after update")
        XCTAssertTrue(updatedText.contains("New paragraph"), "Should contain 'New paragraph' after update")
    }

    func testIncrementalUpdate_modifyHeading() throws {
        let initial = "# Original Title\n\nSome text"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertEqual(countElements("h1"), 1, "Should have one h1 initially")
        let initialText = getArticleText()
        XCTAssertTrue(initialText.contains("Original Title"))

        pushUpdate(newMarkdown: "# Updated Title\n\nSome text")

        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Updated Title"), "Heading should be updated")
        XCTAssertFalse(updatedText.contains("Original Title"), "Old heading should be gone")
        XCTAssertEqual(countElements("h1"), 1, "Should still have exactly one h1")
    }

    func testIncrementalUpdate_addListItems() throws {
        let initial = "# List\n\n- Item 1\n- Item 2"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertEqual(countElements("li"), 2, "Should have 2 list items initially")

        pushUpdate(newMarkdown: "# List\n\n- Item 1\n- Item 2\n- Item 3\n- Item 4")

        XCTAssertEqual(countElements("li"), 4, "Should have 4 list items after update")
        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Item 3"))
        XCTAssertTrue(updatedText.contains("Item 4"))
    }

    func testIncrementalUpdate_removeContent() throws {
        let initial = "# Title\n\nParagraph one\n\nParagraph two\n\nParagraph three"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertEqual(countElements("p"), 3, "Should have 3 paragraphs initially")

        pushUpdate(newMarkdown: "# Title\n\nParagraph one")

        XCTAssertEqual(countElements("p"), 1, "Should have 1 paragraph after removing content")
        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Paragraph one"))
        XCTAssertFalse(updatedText.contains("Paragraph two"))
        XCTAssertFalse(updatedText.contains("Paragraph three"))
    }

    func testIncrementalUpdate_addCodeBlock() throws {
        let initial = "# Code Example\n\nSome text"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertEqual(countElements("pre"), 0, "Should have no code blocks initially")

        pushUpdate(newMarkdown: "# Code Example\n\nSome text\n\n```swift\nlet x = 42\n```")

        XCTAssertEqual(countElements("pre"), 1, "Should have 1 code block after update")
        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("let x = 42"), "Code content should appear")
    }

    func testIncrementalUpdate_multipleRapidUpdates() throws {
        let initial = "# Counter\n\nValue: 0"
        _ = try loadMarkdownWithUpdateScript(initial)

        for i in 1...5 {
            pushUpdate(newMarkdown: "# Counter\n\nValue: \(i)")
        }

        let finalText = getArticleText()
        XCTAssertTrue(finalText.contains("Value: 5"), "Should show the final update value")
        XCTAssertFalse(finalText.contains("Value: 0"), "Should not show the initial value")
    }

    func testIncrementalUpdate_preservesHeadingStructure() throws {
        let initial = "# H1\n\n## H2\n\n### H3\n\nParagraph"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertEqual(countElements("h1"), 1)
        XCTAssertEqual(countElements("h2"), 1)
        XCTAssertEqual(countElements("h3"), 1)

        pushUpdate(newMarkdown: "# H1\n\n## H2\n\n### H3\n\nParagraph\n\n## Another H2\n\nMore text")

        XCTAssertEqual(countElements("h1"), 1, "Should still have 1 h1")
        XCTAssertEqual(countElements("h2"), 2, "Should now have 2 h2s")
        XCTAssertEqual(countElements("h3"), 1, "Should still have 1 h3")
        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Another H2"))
        XCTAssertTrue(updatedText.contains("More text"))
    }

    func testIncrementalUpdate_withFrontmatter() throws {
        let initial = "---\ntitle: Test\n---\n\n# Hello\n\nWorld"
        _ = try loadMarkdownWithUpdateScript(initial)

        let initialText = getArticleText()
        XCTAssertTrue(initialText.contains("Hello"))
        XCTAssertTrue(initialText.contains("World"))

        pushUpdate(newMarkdown: "---\ntitle: Test\n---\n\n# Hello\n\nWorld\n\nAdded after frontmatter")

        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("Added after frontmatter"),
                       "Content added after frontmatter should appear in renderer")
    }

    func testIncrementalUpdate_withComments() throws {
        let initial = "# Doc\n\nSome <!-- COMMENT: note -->annotated<!-- /COMMENT --> text"
        _ = try loadMarkdownWithUpdateScript(initial)

        let initialText = getArticleText()
        XCTAssertTrue(initialText.contains("annotated"))

        pushUpdate(newMarkdown: "# Doc\n\nSome <!-- COMMENT: note -->annotated<!-- /COMMENT --> text\n\nNew paragraph")

        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("annotated"), "Comment-annotated text should survive update")
        XCTAssertTrue(updatedText.contains("New paragraph"), "New content should appear")
        XCTAssertEqual(countElements(".qmd-comment"), 1, "Comment mark should still exist")
    }

    func testIncrementalUpdate_emptyToContent() throws {
        let initial = ""
        _ = try loadMarkdownWithUpdateScript(initial)

        pushUpdate(newMarkdown: "# New Document\n\nThis is fresh content")

        let updatedText = getArticleText()
        XCTAssertTrue(updatedText.contains("New Document"), "Content should appear from empty state")
        XCTAssertTrue(updatedText.contains("fresh content"))
    }

    func testIncrementalUpdate_contentToEmpty() throws {
        let initial = "# Title\n\nParagraph\n\n- List item"
        _ = try loadMarkdownWithUpdateScript(initial)

        XCTAssertTrue(getArticleText().contains("Title"))

        pushUpdate(newMarkdown: "")

        let updatedText = getArticleText().trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertTrue(updatedText.isEmpty || !updatedText.contains("Title"),
                       "Content should be cleared after empty update")
    }

    // MARK: - Comment rendering E2E

    /// E2E: verify comment inside paragraph with inline code renders as highlighted mark.
    func testCommentRenderingWithInlineCode() throws {
        let md = "The `OverrideVerdict` host function enforces <!-- COMMENT: non escalations -->escalation-only<!-- /COMMENT --> semantics:"
        let (html, _) = try loadMarkdown(md)

        // HTML should contain the mark tag
        XCTAssertTrue(html.contains("qmd-comment"), "HTML should contain qmd-comment class: \(html)")

        // DOM should have the mark element after JS runs
        let markCount = evalJS("document.querySelectorAll('.qmd-comment').length") as? Int ?? 0
        XCTAssertEqual(markCount, 1, "Should have exactly 1 comment mark in DOM")

        // The comment text should be accessible
        let commentText = evalJS("document.querySelector('.qmd-comment')?.getAttribute('data-comment')") as? String
        XCTAssertEqual(commentText, "non escalations")
    }

    /// E2E: verify comment wrapping bold text renders correctly.
    func testCommentRenderingWithBoldContent() throws {
        let md = "Their decisions are <!-- COMMENT: review -->**discarded**<!-- /COMMENT --> by the system."
        let (html, _) = try loadMarkdown(md)

        XCTAssertTrue(html.contains("qmd-comment"), "HTML should contain qmd-comment class")

        let markCount = evalJS("document.querySelectorAll('.qmd-comment').length") as? Int ?? 0
        XCTAssertEqual(markCount, 1, "Should have exactly 1 comment mark in DOM")

        // The bold should be rendered inside the comment mark
        let hasBoldInside = evalJS("document.querySelector('.qmd-comment strong') !== null") as? Bool ?? false
        XCTAssertTrue(hasBoldInside, "Bold text should be rendered inside the comment mark")
    }
}
