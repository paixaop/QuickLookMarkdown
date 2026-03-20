import XCTest
@testable import QuickMD

/// Exhaustive E2E tests for renderer↔editor synchronization.
/// Tests the full pipeline: markdown → SourceMappedHTMLFormatter → data-source-line attributes → jumpEditorToWord algorithm.
final class EditorRendererSyncTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempFile(_ content: String, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let name = UUID().uuidString + "." + ext
        let url = dir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// Extract the data-source-line attribute from the first HTML tag matching a pattern.
    private func sourceLine(in html: String, forTag tag: String, containing text: String? = nil) -> Int? {
        let pattern = "<\(tag)[^>]*data-source-line=\"(\\d+)\"[^>]*>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let nsHTML = html as NSString
        let matches = regex.matches(in: html, range: NSRange(location: 0, length: nsHTML.length))
        for match in matches {
            let lineStr = nsHTML.substring(with: match.range(at: 1))
            if let text = text {
                // Check if this tag's content contains the text
                let tagEnd = match.range.location + match.range.length
                let remaining = nsHTML.substring(from: tagEnd)
                if remaining.hasPrefix(text) || remaining.contains(text) {
                    return Int(lineStr)
                }
            } else {
                return Int(lineStr)
            }
        }
        return nil
    }

    // =========================================================================
    // MARK: - SourceMappedHTMLFormatter: data-source-line correctness
    // =========================================================================

    func testFormatterAddsSourceLineToHeadings() {
        let md = "# Title\n\n## Subtitle"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<h1 data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<h2 data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToParagraphs() {
        let md = "First paragraph.\n\nSecond paragraph."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<p data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<p data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToListItems() {
        let md = "- item A\n- item B\n- item C"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<li data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"2\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToOrderedList() {
        let md = "1. first\n2. second\n3. third"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<ol data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"2\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToBlockquotes() {
        let md = "Normal text.\n\n> Quoted text."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<blockquote data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToCodeBlocks() {
        let md = "Some text.\n\n```python\nprint('hello')\n```"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<pre data-source-line=\"3\""))
    }

    func testFormatterAddsSourceLineToTables() {
        let md = "| A | B |\n|---|---|\n| 1 | 2 |"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<table data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<th data-source-line="))
        XCTAssertTrue(html.contains("<td data-source-line="))
    }

    func testFormatterPreservesInlineFormattingInHeadings() {
        let md = "# Hello **world**"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        // Should use descendInto, not plainText, so <strong> is preserved
        XCTAssertTrue(html.contains("<strong>world</strong>"))
    }

    func testFormatterHandlesEmptyDocument() {
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format("")
        XCTAssertTrue(html.isEmpty || html.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    func testFormatterHandlesSingleLine() {
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format("Just text.")
        XCTAssertTrue(html.contains("<p data-source-line=\"1\""))
    }

    func testFormatterNestedBlockquoteList() {
        let md = "> - item in quote\n> - another item"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<blockquote data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line="))
    }

    func testFormatterMultiLineCodeBlock() {
        let md = "```\nline1\nline2\nline3\n```"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<pre data-source-line=\"1\""))
        XCTAssertTrue(html.contains("line1\nline2\nline3\n"))
    }

    func testFormatterThematicBreak() {
        let md = "Before\n\n---\n\nAfter"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<hr />\n"))
        XCTAssertTrue(html.contains("<p data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<p data-source-line=\"5\""))
    }

    func testFormatterPreservesLinks() {
        let md = "Click [here](https://example.com) now."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<a href=\"https://example.com\">here</a>"))
    }

    func testFormatterPreservesImages() {
        let md = "![Alt](image.png)"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<img src=\"image.png\""))
    }

    func testFormatterPreservesInlineCode() {
        let md = "Use `code` here."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<code>code</code>"))
    }

    func testFormatterPreservesStrikethrough() {
        let md = "This is ~~deleted~~ text."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<del>deleted</del>"))
    }

    func testFormatterTaskList() {
        let md = "- [x] Done\n- [ ] Todo"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("checked=\"\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<li data-source-line=\"2\""))
    }

    // =========================================================================
    // MARK: - Frontmatter line count
    // =========================================================================

    func testFrontmatterLineCountZeroWithoutFrontmatter() {
        let url = writeTempFile("# Hello\nWorld", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        XCTAssertEqual(model.frontmatterLineCount, 0)
    }

    func testFrontmatterLineCountWithFrontmatter() {
        let md = "---\ntitle: Test\nauthor: Me\n---\n\n# Hello"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        // Frontmatter is 3 content lines + 2 delimiters = 5 lines before body
        // But stripFrontmatter removes them, so frontmatterLineCount should be > 0
        XCTAssertGreaterThan(model.frontmatterLineCount, 0)
    }

    func testFrontmatterLineCountAccuracy() {
        let md = "---\ntitle: Test\n---\n\n# Body"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        XCTAssertGreaterThan(model.frontmatterLineCount, 0, "Should have nonzero frontmatter offset")
        // stripFrontmatter produces body = "\n# Body", so parser sees heading at line 2
        // Verify the mapping: parser line 2 + frontmatterLineCount - 1 should point to "# Body"
        let lines = md.components(separatedBy: "\n")
        let parserLine = 2 // heading is at line 2 in the body (body starts with blank line)
        let adjustedLine = parserLine + model.frontmatterLineCount - 1 // 0-based
        XCTAssertTrue(adjustedLine < lines.count, "Adjusted line should be in range")
        XCTAssertEqual(lines[adjustedLine], "# Body", "Should map to the body heading")
    }

    // =========================================================================
    // MARK: - sourceRangeFromRenderedOffsets
    // =========================================================================

    private func sourceRange(sourceLine: Int, offset: Int, endOffset: Int, frontmatter: Int = 0, source: String) -> NSRange? {
        WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: sourceLine, offsetInBlock: offset, endOffsetInBlock: endOffset,
            frontmatterLineCount: frontmatter, source: source
        )
    }

    func testSourceRangeFromRenderedOffsetsPlainText() {
        let source = "Hello world this is text."
        // Select "world" (rendered offset 6..11)
        let range = sourceRange(sourceLine: 1, offset: 6, endOffset: 11, source: source)
        XCTAssertNotNil(range)
        XCTAssertEqual((source as NSString).substring(with: range!), "world")
    }

    func testSourceRangeFromRenderedOffsetsWithBold() {
        let source = "Hello **world** this is text."
        // Rendered: "Hello world this is text." — "world" is at rendered offset 6..11
        let range = sourceRange(sourceLine: 1, offset: 6, endOffset: 11, source: source)
        XCTAssertNotNil(range)
        XCTAssertEqual((source as NSString).substring(with: range!), "world")
    }

    func testSourceRangeFromRenderedOffsetsSpanningBold() {
        let source = "Hello **world** here."
        // Rendered: "Hello world here." — select "Hello world" (0..11)
        let range = sourceRange(sourceLine: 1, offset: 0, endOffset: 11, source: source)
        XCTAssertNotNil(range)
        // The range includes the opening ** but stops before the closing **
        let matched = (source as NSString).substring(with: range!)
        XCTAssertTrue(matched.hasPrefix("Hello"), "Should start with 'Hello': got '\(matched)'")
        XCTAssertTrue(matched.contains("world"), "Should contain 'world': got '\(matched)'")
    }

    func testSourceRangeFromRenderedOffsetsWithCommentMarker() {
        let source = "enforces <!-- COMMENT: note -->escalation-only<!-- /COMMENT --> semantics:"
        // Rendered: "enforces escalation-only semantics:"
        // Select "enforces escalation-only" (0..24)
        let range = sourceRange(sourceLine: 1, offset: 0, endOffset: 24, source: source)
        XCTAssertNotNil(range, "Should find range spanning comment marker")
        let matched = (source as NSString).substring(with: range!)
        XCTAssertTrue(matched.hasPrefix("enforces"), "Should start with 'enforces': got '\(matched)'")
        XCTAssertTrue(matched.contains("escalation-only"), "Should contain full word: got '\(matched)'")
    }

    func testSourceRangeFromRenderedOffsetsWithStrikethrough() {
        let source = "This is ~~deleted~~ text here."
        // Rendered: "This is deleted text here." — select "deleted" (8..15)
        let range = sourceRange(sourceLine: 1, offset: 8, endOffset: 15, source: source)
        XCTAssertNotNil(range)
        let matched = (source as NSString).substring(with: range!)
        XCTAssertEqual(matched, "deleted")
    }

    func testSourceRangeFromRenderedOffsetsWithFrontmatter() {
        let source = "---\ntitle: Test\n---\n\nHello world."
        // "Hello world." is on source line 5, frontmatter has 3 lines
        // frontmatterLineCount adjusts the line index: 5 + 3 - 1 = 7 (0-based) but
        // the actual text line is at index 4 (0-based). frontmatterLineCount should be 0
        // when the source already includes frontmatter and sourceLine is absolute.
        // In practice, preprocessComments strips frontmatter first and sourceLine is
        // relative to the body. Here we test with sourceLine=1 (first body line) and
        // frontmatter=0, passing just the body.
        let body = "Hello world."
        let range = sourceRange(sourceLine: 1, offset: 6, endOffset: 11, frontmatter: 0, source: body)
        XCTAssertNotNil(range)
        XCTAssertEqual((body as NSString).substring(with: range!), "world")
    }

    // =========================================================================
    // MARK: - Full pipeline: markdown → HTML → source line mapping
    // =========================================================================

    func testFullPipelineHeadingsHaveCorrectLines() throws {
        let md = "# First Heading\n\nSome text.\n\n## Second Heading\n\nMore text."
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        XCTAssertTrue(html.contains("data-source-line=\"1\""), "First heading should be at line 1")
        XCTAssertTrue(html.contains("data-source-line=\"3\""), "Paragraph should be at line 3")
        XCTAssertTrue(html.contains("data-source-line=\"5\""), "Second heading should be at line 5")
    }

    func testFullPipelineWithFrontmatter() throws {
        let md = "---\ntitle: Test\n---\n\n# Body Heading\n\nBody text."
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        // Should have source line attributes and frontmatter offset
        XCTAssertTrue(html.contains("data-source-line="), "Should have source line attributes")
        XCTAssertGreaterThan(model.frontmatterLineCount, 0, "Should have frontmatter offset")
        // Verify the heading is in the HTML
        XCTAssertTrue(html.contains("Body Heading"), "Should render the heading text")
    }

    func testFullPipelineWithComments() throws {
        let md = "# Title\n\nSome <!-- COMMENT: note -->annotated<!-- /COMMENT --> text.\n\nMore text."
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        XCTAssertTrue(html.contains("data-source-line="), "Should have source line attributes")
        XCTAssertTrue(html.contains("qmd-comment"), "Should have comment marks")
    }

    func testCommentInsideParagraphWithInlineCode() throws {
        // Reproduces the bug: comment wrapping text next to backtick code and special chars
        let md = "The `OverrideVerdict` host function enforces <!-- COMMENT: non escalations always audit -->escalation-only<!-- /COMMENT --> semantics:"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        XCTAssertTrue(html.contains("qmd-comment"), "Comment mark should be present in HTML: \(html)")
        XCTAssertTrue(html.contains("data-comment=\"non escalations always audit\""),
                       "Comment data attribute should be preserved: \(html)")
        XCTAssertTrue(html.contains("escalation-only</mark>"),
                       "Annotated text should be inside mark tag: \(html)")
    }

    func testCommentWrappingBoldText() throws {
        // Comment wrapping text that has bold markers
        let md = "Their decisions are <!-- COMMENT: note -->**discarded**<!-- /COMMENT --> by the system."
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        XCTAssertTrue(html.contains("qmd-comment"), "Comment mark should be present: \(html)")
    }

    func testCommentInsideTableCell() throws {
        let md = "| A | B |\n|---|---|\n| <!-- COMMENT: test -->value<!-- /COMMENT --> | other |"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        XCTAssertTrue(html.contains("qmd-comment"), "Comment in table cell should render: \(html)")
    }

    func testFullPipelineComplexDocument() throws {
        let md = """
        # Title

        First paragraph with **bold** and *italic*.

        ## Section Two

        - List item one
        - List item two

        > A blockquote.

        ```python
        x = 1
        ```

        | A | B |
        |---|---|
        | 1 | 2 |

        ## Final Section

        Last paragraph.
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        // Every block element should have a data-source-line
        XCTAssertTrue(html.contains("<h1 data-source-line="))
        XCTAssertTrue(html.contains("<h2 data-source-line="))
        XCTAssertTrue(html.contains("<p data-source-line="))
        XCTAssertTrue(html.contains("<li data-source-line="))
        XCTAssertTrue(html.contains("<blockquote data-source-line="))
        XCTAssertTrue(html.contains("<pre data-source-line="))
        XCTAssertTrue(html.contains("<table data-source-line="))
    }

    // =========================================================================
    // MARK: - Stress tests
    // =========================================================================

    func testManyDuplicateWords() {
        // 50 paragraphs all containing the word "test"
        var lines: [String] = []
        for i in 0..<50 {
            lines.append("Paragraph \(i) with word test in it.")
            lines.append("")
        }
        let source = lines.joined(separator: "\n")

        // Each even line (0, 2, 4, ...) is a paragraph
        // Parser line numbers are 1-based: 1, 3, 5, ...
        // "test" starts at rendered offset 24 within each paragraph line: "Paragraph X with word test in it."
        // endOffset = offset + 4 (length of "test")
        for i in 0..<50 {
            let parserLine = i * 2 + 1
            let paragraphText = lines[i * 2]
            let testOffset = (paragraphText as NSString).range(of: "test").location
            let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(
                sourceLine: parserLine, offsetInBlock: testOffset, endOffsetInBlock: testOffset + 4,
                frontmatterLineCount: 0, source: source
            )
            XCTAssertNotNil(range, "Should find 'test' for paragraph \(i)")
            if let range = range {
                let lineStart = source.components(separatedBy: "\n").prefix(i * 2).joined(separator: "\n").count + (i > 0 ? 1 : 0)
                let lineEnd = lineStart + lines[i * 2].count
                XCTAssertTrue(range.location >= lineStart && range.location < lineEnd,
                              "Paragraph \(i): range \(range.location) should be between \(lineStart) and \(lineEnd)")
            }
        }
    }

    func testLargeDocumentPerformance() {
        var lines: [String] = ["# Large Document\n"]
        for i in 0..<100 {
            lines.append("## Section \(i)\n")
            lines.append("The word target appears in section \(i) among other words.\n")
            lines.append("")
        }
        let source = lines.joined(separator: "\n")

        measure {
            // Finding a word near the end should be fast
            let _ = WebView.Coordinator.sourceRangeFromRenderedOffsets(
                sourceLine: 290, offsetInBlock: 10, endOffsetInBlock: 16,
                frontmatterLineCount: 0, source: source
            )
        }
    }

    // =========================================================================
    // MARK: - SourceMappedHTMLFormatter: regression tests
    // =========================================================================

    func testFormatterMatchesHTMLFormatterOutput() {
        // The source-mapped formatter should produce structurally equivalent HTML
        // (same tags, same text) just with extra data attributes
        let md = "# Hello\n\nWorld with **bold** and [link](url).\n\n- item 1\n- item 2"
        let mapped = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)

        // Strip data-source-line/col attributes to compare structure
        let stripped = mapped.replacingOccurrences(of: #" data-source-line="\d+" data-source-col="\d+""#, with: "", options: .regularExpression)

        // Should still have all the structural elements
        XCTAssertTrue(stripped.contains("<h1"))
        XCTAssertTrue(stripped.contains("<p"))
        XCTAssertTrue(stripped.contains("<strong>bold</strong>"))
        XCTAssertTrue(stripped.contains("<a href=\"url\">link</a>"))
        XCTAssertTrue(stripped.contains("<ul"))
        XCTAssertTrue(stripped.contains("<li"))
    }

    func testFormatterDoesNotAddAttrsToInlineElements() {
        let md = "Text with **bold** and *italic* and `code` and [link](url)."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        // Inline elements should NOT have data-source-line
        XCTAssertFalse(html.contains("<strong data-source-line"))
        XCTAssertFalse(html.contains("<em data-source-line"))
        XCTAssertFalse(html.contains("<code data-source-line"))
        XCTAssertFalse(html.contains("<a data-source-line"))
    }

    func testFormatterHandlesConsecutiveBlankLines() {
        let md = "First.\n\n\n\nSecond."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<p data-source-line=\"1\""))
        XCTAssertTrue(html.contains("<p data-source-line=\"5\""))
    }

    func testFormatterHandlesWindowsLineEndings() {
        let md = "# Title\r\n\r\nParagraph."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<h1 data-source-line="))
        XCTAssertTrue(html.contains("<p data-source-line="))
    }

    func testFormatterHandlesTabIndentation() {
        let md = "- item\n\t- nested"
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(md)
        XCTAssertTrue(html.contains("<li data-source-line="))
    }

    // =========================================================================
    // MARK: - Block extent detection edge cases
    // =========================================================================

    func testBlockExtentStopsAtBlankLine() {
        let source = "word here on line one.\nContinuation of same paragraph.\n\nNew paragraph with word."
        // Line 1 starts a paragraph that continues to line 2 (no blank line between)
        // Line 4 is a new paragraph
        let range1 = WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: 1, offsetInBlock: 0, endOffsetInBlock: 4,
            frontmatterLineCount: 0, source: source
        )
        let range2 = WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: 4, offsetInBlock: 20, endOffsetInBlock: 24,
            frontmatterLineCount: 0, source: source
        )
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testBlockExtentStopsAtHeading() {
        let source = "word in paragraph.\n# Heading with word\nword after heading."
        // Paragraph at line 1, heading at line 2, paragraph at line 3
        let range1 = WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: 1, offsetInBlock: 0, endOffsetInBlock: 4,
            frontmatterLineCount: 0, source: source
        )
        XCTAssertNotNil(range1)
        // Should only find "word" in the first paragraph's range
        let firstLineEnd = "word in paragraph.".count
        XCTAssertLessThan(range1!.location, firstLineEnd)
    }

    func testBlockExtentHandlesLastLine() {
        let source = "First.\n\nLast line with word."
        let range = WebView.Coordinator.sourceRangeFromRenderedOffsets(
            sourceLine: 3, offsetInBlock: 15, endOffsetInBlock: 19,
            frontmatterLineCount: 0, source: source
        )
        XCTAssertNotNil(range)
        XCTAssertGreaterThan(range!.location, 8) // Past "First.\n\n"
    }
}
