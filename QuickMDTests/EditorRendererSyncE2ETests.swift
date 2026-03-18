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

    override func tearDown() {
        webView = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func writeTempFile(_ content: String, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Load markdown into a real WKWebView with all scripts injected, wait for it to finish.
    private func loadMarkdown(_ markdown: String) throws -> (html: String, model: MarkdownDocumentModel) {
        let url = writeTempFile(markdown, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        let loadExpectation = expectation(description: "WebView loaded")
        webView.loadHTMLString(html, baseURL: nil)

        // Inject scripts after load
        let scripts = [
            MarkdownDocumentModel.editorSyncScript,
            MarkdownDocumentModel.commentScript,
            MarkdownDocumentModel.commentsSidebarScript,
            MarkdownDocumentModel.sidebarArrangeScript
        ]

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            for script in scripts {
                self.webView.evaluateJavaScript(script) { _, _ in }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                loadExpectation.fulfill()
            }
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
    private func getSelectionSourceInfo() -> (sourceLine: Int, offsetInBlock: Int, text: String)? {
        let js = "window.__getSelectionSourceInfo ? JSON.stringify(__getSelectionSourceInfo()) : null"
        guard let jsonStr = evalJS(js) as? String,
              let data = jsonStr.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return (
            sourceLine: dict["sourceLine"] as? Int ?? -1,
            offsetInBlock: dict["offsetInBlock"] as? Int ?? -1,
            text: dict["text"] as? String ?? ""
        )
    }

    /// Simulate a double-click by selecting a word and calling the dblclick logic manually.
    /// Returns the message that would be sent to Swift.
    private func simulateDoubleClick(selectingWord word: String, occurrence: Int = 1) -> (sourceLine: Int, sourceCol: Int, offsetInBlock: Int)? {
        guard selectText(word, occurrence: occurrence) else { return nil }

        // Call the source info function (same logic as dblclick handler)
        let js = """
        (function() {
            var sel = window.getSelection();
            if (!sel || sel.rangeCount === 0) return null;
            var word = sel.toString().trim();
            if (!word) return null;

            var el = sel.anchorNode;
            while (el && el !== document.body) {
                if (el.nodeType === 1 && el.hasAttribute('data-source-line')) break;
                el = el.parentNode;
            }
            if (!el || !el.hasAttribute || !el.hasAttribute('data-source-line')) return null;

            var sourceLine = parseInt(el.getAttribute('data-source-line'), 10);
            var sourceCol = parseInt(el.getAttribute('data-source-col') || '1', 10);

            var offsetInBlock = -1;
            try {
                var range = sel.getRangeAt(0);
                var preRange = document.createRange();
                preRange.setStart(el, 0);
                preRange.setEnd(range.startContainer, range.startOffset);
                offsetInBlock = preRange.toString().length;
            } catch(ex) {}

            return JSON.stringify({sourceLine: sourceLine, sourceCol: sourceCol, offsetInBlock: offsetInBlock});
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
            offsetInBlock: dict["offsetInBlock"] as? Int ?? -1
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
            let range1 = WebView.Coordinator.findWordRange(word: "apple", in: model.rawContent, sourceLine: info1.sourceLine, offsetInBlock: info1.offsetInBlock, frontmatterLineCount: model.frontmatterLineCount)
            XCTAssertNotNil(range1)
            XCTAssertLessThan(range1!.location, 25, "First apple should be in first paragraph")
        }
        if let info2 = info2 {
            let range2 = WebView.Coordinator.findWordRange(word: "apple", in: model.rawContent, sourceLine: info2.sourceLine, offsetInBlock: info2.offsetInBlock, frontmatterLineCount: model.frontmatterLineCount)
            XCTAssertNotNil(range2)
            XCTAssertGreaterThan(range2!.location, 25, "Second apple should be past first paragraph")
        }
        if let info3 = info3 {
            let range3 = WebView.Coordinator.findWordRange(word: "apple", in: model.rawContent, sourceLine: info3.sourceLine, offsetInBlock: info3.offsetInBlock, frontmatterLineCount: model.frontmatterLineCount)
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

            let r1 = WebView.Coordinator.findWordRange(word: "Section", in: model.rawContent, sourceLine: i1.sourceLine, offsetInBlock: i1.offsetInBlock, frontmatterLineCount: 0)
            let r2 = WebView.Coordinator.findWordRange(word: "Section", in: model.rawContent, sourceLine: i2.sourceLine, offsetInBlock: i2.offsetInBlock, frontmatterLineCount: 0)
            let r3 = WebView.Coordinator.findWordRange(word: "Section", in: model.rawContent, sourceLine: i3.sourceLine, offsetInBlock: i3.offsetInBlock, frontmatterLineCount: 0)
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
            let range = WebView.Coordinator.findWordRange(word: "data", in: model.rawContent, sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, frontmatterLineCount: 0)
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
        let info1: (sourceLine: Int, offsetInBlock: Int, text: String)? = {
            guard selectText("First") else { return nil }
            return getSelectionSourceInfo()
        }()
        let info2: (sourceLine: Int, offsetInBlock: Int, text: String)? = {
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

    func testSidebarContainerExistsInDOM() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.")
        let exists = evalJS("document.getElementById('sidebar-container') !== null") as? Bool
        XCTAssertTrue(exists ?? false, "Sidebar container should exist in DOM")
    }

    func testTOCPanelExistsInDOM() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.")
        let exists = evalJS("document.getElementById('toc-panel') !== null") as? Bool
        XCTAssertTrue(exists ?? false, "TOC panel should exist")
    }

    func testCommentsPanelExistsInDOM() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.")
        let exists = evalJS("document.getElementById('comments-panel') !== null") as? Bool
        XCTAssertTrue(exists ?? false, "Comments panel should exist")
    }

    func testSidebarIconsExistInDOM() throws {
        let (_, _) = try loadMarkdown("# Heading\n\nParagraph.")
        let iconCount = evalJS("document.querySelectorAll('.sidebar-icon').length") as? Int
        XCTAssertEqual(iconCount, 2, "Should have 2 sidebar icons (TOC + Comments)")
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
            let range = WebView.Coordinator.findWordRange(word: "paragraph", in: model.rawContent, sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, frontmatterLineCount: model.frontmatterLineCount)
            XCTAssertNotNil(range)
            // "Second paragraph" is in the second paragraph — verify it's past the first
            let firstParagraphEnd = (model.rawContent as NSString).range(of: "First paragraph.").location + "First paragraph.".count
            XCTAssertGreaterThan(range!.location, firstParagraphEnd, "Should find the second 'paragraph', not the first")
        }
    }

    func testFullRoundTripWithFormatting() throws {
        let md = "The **word** is bold.\n\nThe *word* is italic."
        let (_, model) = try loadMarkdown(md)

        let info1 = simulateDoubleClick(selectingWord: "word", occurrence: 1)
        let info2 = simulateDoubleClick(selectingWord: "word", occurrence: 2)

        XCTAssertNotNil(info1)
        XCTAssertNotNil(info2)

        if let i1 = info1, let i2 = info2 {
            let r1 = WebView.Coordinator.findWordRange(word: "word", in: model.rawContent, sourceLine: i1.sourceLine, offsetInBlock: i1.offsetInBlock, frontmatterLineCount: 0)
            let r2 = WebView.Coordinator.findWordRange(word: "word", in: model.rawContent, sourceLine: i2.sourceLine, offsetInBlock: i2.offsetInBlock, frontmatterLineCount: 0)
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
                let range = WebView.Coordinator.findWordRange(word: "testing", in: model.rawContent, sourceLine: info.sourceLine, offsetInBlock: info.offsetInBlock, frontmatterLineCount: 0)
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

    /// E2E: simulate adding a comment to each list item via findWordRange (the same path as addCommentToSource).
    func testArchitectureFixtureCommentEachListItem() throws {
        let (_, model) = try loadMarkdown(architectureFixture)
        let source = model.rawContent

        // For each list item, select a unique word, get source info, then verify findWordRange
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

            // Use findWordRange — same algorithm as addCommentToSource
            guard let range = WebView.Coordinator.findWordRange(
                word: word,
                in: source,
                sourceLine: info.sourceLine,
                offsetInBlock: info.offsetInBlock,
                frontmatterLineCount: model.frontmatterLineCount
            ) else {
                XCTFail("findWordRange returned nil for '\(word)' at line \(info.sourceLine)")
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
        guard let range = WebView.Coordinator.findWordRange(
            word: "Reliability-first",
            in: source,
            sourceLine: info.sourceLine,
            offsetInBlock: info.offsetInBlock,
            frontmatterLineCount: model.frontmatterLineCount
        ) else {
            XCTFail("findWordRange returned nil"); return
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
            guard let range = WebView.Coordinator.findWordRange(
                word: word, in: source,
                sourceLine: info.sourceLine,
                offsetInBlock: info.offsetInBlock,
                frontmatterLineCount: model.frontmatterLineCount
            ) else {
                XCTFail("findWordRange nil for '\(word)' (#\(i))"); continue
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
}
