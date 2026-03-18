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

    /// Find the NSRange that the sync algorithm would pick for a given word + source line + offset.
    private func findRange(word: String, in source: String, sourceLine: Int, offsetInBlock: Int = 0, fmLines: Int = 0) -> NSRange? {
        WebView.Coordinator.findWordRange(word: word, in: source, sourceLine: sourceLine, offsetInBlock: offsetInBlock, frontmatterLineCount: fmLines)
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
    // MARK: - findWordRange: basic cases
    // =========================================================================

    func testFindWordSingleOccurrence() {
        let source = "# Hello\n\nWorld is unique here."
        let range = findRange(word: "unique", in: source, sourceLine: 3)
        XCTAssertNotNil(range)
        XCTAssertEqual((source as NSString).substring(with: range!), "unique")
    }

    func testFindWordNotFound() {
        let source = "# Hello\n\nWorld."
        let range = findRange(word: "nonexistent", in: source, sourceLine: 1)
        XCTAssertNil(range)
    }

    // =========================================================================
    // MARK: - findWordRange: duplicate word disambiguation
    // =========================================================================

    func testDuplicateWordInDifferentSections() {
        let source = "# Section One\n\nThe word test appears here.\n\n# Section Two\n\nThe word test appears here too."
        // "test" at line 3 (section one) vs line 7 (section two)
        let range1 = findRange(word: "test", in: source, sourceLine: 3)
        let range2 = findRange(word: "test", in: source, sourceLine: 7)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location, "Should find different occurrences")
        // range1 should be in section one (earlier in doc)
        XCTAssertLessThan(range1!.location, range2!.location)
    }

    func testDuplicateWordInDifferentParagraphs() {
        let source = "First paragraph with word apple.\n\nSecond paragraph with word apple.\n\nThird paragraph with word apple."
        let range1 = findRange(word: "apple", in: source, sourceLine: 1)
        let range2 = findRange(word: "apple", in: source, sourceLine: 3)
        let range3 = findRange(word: "apple", in: source, sourceLine: 5)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        XCTAssertLessThan(range1!.location, range2!.location)
        XCTAssertLessThan(range2!.location, range3!.location)
    }

    func testDuplicateWordSameLineUsesOffset() {
        let source = "The cat sat on the cat mat near cat."
        // "cat" appears 3 times on line 1 at different offsets
        let range1 = findRange(word: "cat", in: source, sourceLine: 1, offsetInBlock: 4)   // "The cat..."
        let range2 = findRange(word: "cat", in: source, sourceLine: 1, offsetInBlock: 19)  // "...the cat mat..."
        let range3 = findRange(word: "cat", in: source, sourceLine: 1, offsetInBlock: 32)  // "...near cat."
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        // Each should pick the closest occurrence to the offset
        XCTAssertLessThan(range1!.location, range2!.location)
        XCTAssertLessThan(range2!.location, range3!.location)
    }

    func testDuplicateWordInHeadingVsParagraph() {
        let source = "# Overview\n\nThis overview explains things."
        // "Overview" in heading (line 1) vs paragraph (line 3)
        // Note: case-insensitive, "Overview" vs "overview"
        let range1 = findRange(word: "Overview", in: source, sourceLine: 1)
        let range2 = findRange(word: "overview", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testDuplicateWordInListItems() {
        let source = "- item with data\n- another with data\n- more with data"
        // List items are on consecutive lines (no blank line), so block extent spans all three.
        // Use offsetInBlock to disambiguate within the block.
        let range1 = findRange(word: "data", in: source, sourceLine: 1, offsetInBlock: 12)
        let range2 = findRange(word: "data", in: source, sourceLine: 2, offsetInBlock: 30)
        let range3 = findRange(word: "data", in: source, sourceLine: 3, offsetInBlock: 48)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        // With offsets, each should pick the closest occurrence
        XCTAssertLessThanOrEqual(range1!.location, range2!.location)
        XCTAssertLessThanOrEqual(range2!.location, range3!.location)
    }

    func testDuplicateWordInTableCells() {
        let source = "| value | other |\n|-------|-------|\n| value | value |"
        // "value" appears in header (line 1) and both cells (line 3)
        let range1 = findRange(word: "value", in: source, sourceLine: 1)
        let range3 = findRange(word: "value", in: source, sourceLine: 3, offsetInBlock: 0)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range3)
        XCTAssertLessThan(range1!.location, range3!.location)
    }

    func testDuplicateWordInBlockquoteVsParagraph() {
        let source = "The word error here.\n\n> The word error in quote."
        let range1 = findRange(word: "error", in: source, sourceLine: 1)
        let range2 = findRange(word: "error", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    // =========================================================================
    // MARK: - findWordRange: markdown syntax edge cases
    // =========================================================================

    func testWordInsideBoldText() {
        let source = "Normal **important** word.\n\nAnother **important** mention."
        let range1 = findRange(word: "important", in: source, sourceLine: 1)
        let range2 = findRange(word: "important", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordInsideItalicText() {
        let source = "The *key* idea.\n\nAnother *key* concept."
        let range1 = findRange(word: "key", in: source, sourceLine: 1)
        let range2 = findRange(word: "key", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordInsideLinkText() {
        let source = "Click [here](url1) now.\n\nClick [here](url2) again."
        let range1 = findRange(word: "here", in: source, sourceLine: 1)
        let range2 = findRange(word: "here", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordInsideInlineCode() {
        let source = "Use `code` method.\n\nAnother `code` example."
        let range1 = findRange(word: "code", in: source, sourceLine: 1)
        let range2 = findRange(word: "code", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordAfterHeadingMarker() {
        // "# Title" — the word "Title" has an offset that accounts for "# "
        let source = "# Title\n\nTitle appears again in body."
        let range1 = findRange(word: "Title", in: source, sourceLine: 1, offsetInBlock: 0)
        let range2 = findRange(word: "Title", in: source, sourceLine: 3, offsetInBlock: 0)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        // range1 should be at offset 2 (after "# "), range2 later
        XCTAssertLessThan(range1!.location, range2!.location)
    }

    func testWordAfterListMarker() {
        // "- item" — rendered text is "item" but source includes "- "
        let source = "- item one\n\nThe item is here."
        let range1 = findRange(word: "item", in: source, sourceLine: 1, offsetInBlock: 0)
        let range2 = findRange(word: "item", in: source, sourceLine: 3, offsetInBlock: 4)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    // =========================================================================
    // MARK: - findWordRange: frontmatter offset
    // =========================================================================

    func testWordWithFrontmatterOffset() {
        // With frontmatter, body starts later in the raw source
        let source = "---\ntitle: Test\n---\n\n# Hello\n\nworld is here."
        // Body: "# Hello\n\nworld is here."
        // Parser sees "# Hello" as line 1, but in raw source it's line 5
        // frontmatterLineCount = 4 (3 lines of frontmatter + 1 blank line)
        let range = findRange(word: "world", in: source, sourceLine: 3, fmLines: 4)
        XCTAssertNotNil(range)
        let matched = (source as NSString).substring(with: range!)
        XCTAssertEqual(matched, "world")
        // Should be at the right position (line 7 in raw source)
        XCTAssertGreaterThan(range!.location, 20) // Past the frontmatter
    }

    func testDuplicateWordWithFrontmatter() {
        let source = "---\ntitle: data\n---\n\nFirst data here.\n\nSecond data there."
        // "data" appears in frontmatter (line 2), paragraph 1 (line 5), paragraph 2 (line 7)
        // Parser sees body as line 1 (First data) and line 3 (Second data)
        // frontmatterLineCount = 4
        let range1 = findRange(word: "data", in: source, sourceLine: 1, fmLines: 4)
        let range2 = findRange(word: "data", in: source, sourceLine: 3, fmLines: 4)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        // Both should be past the frontmatter
        XCTAssertGreaterThan(range1!.location, 15)
        XCTAssertGreaterThan(range2!.location, range1!.location)
    }

    // =========================================================================
    // MARK: - findWordRange: multi-line blocks
    // =========================================================================

    func testMultiLineParagraph() {
        let source = "This is a long paragraph\nthat spans multiple lines\nwith the word test here.\n\nAnother paragraph with test."
        // Parser treats continuous lines (no blank line) as one paragraph starting at line 1
        let range1 = findRange(word: "test", in: source, sourceLine: 1, offsetInBlock: 60)
        let range2 = findRange(word: "test", in: source, sourceLine: 5, offsetInBlock: 25)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testMultiLineBlockquote() {
        let source = "> First line of quote\n> with continuation.\n\nAnd outside."
        let html = MarkdownDocumentModel.SourceMappedHTMLFormatter.format(source)
        XCTAssertTrue(html.contains("<blockquote data-source-line=\"1\""))
    }

    // =========================================================================
    // MARK: - findWordRange: edge cases
    // =========================================================================

    func testSingleCharacterWord() {
        let source = "A sentence with a word.\n\nAnother a here."
        // "a" appears many times — needs source line to disambiguate
        let range = findRange(word: "a", in: source, sourceLine: 1, offsetInBlock: 18)
        XCTAssertNotNil(range)
    }

    func testVeryCommonWord() {
        let source = "the the the\n\nthe the the\n\nthe the the"
        let range1 = findRange(word: "the", in: source, sourceLine: 1, offsetInBlock: 0)
        let range2 = findRange(word: "the", in: source, sourceLine: 3, offsetInBlock: 0)
        let range3 = findRange(word: "the", in: source, sourceLine: 5, offsetInBlock: 0)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        // Each should be in different blocks
        XCTAssertLessThan(range1!.location, range2!.location)
        XCTAssertLessThan(range2!.location, range3!.location)
    }

    func testWordAtDocumentStart() {
        let source = "Hello world.\n\nHello again."
        let range = findRange(word: "Hello", in: source, sourceLine: 1, offsetInBlock: 0)
        XCTAssertNotNil(range)
        XCTAssertEqual(range!.location, 0)
    }

    func testWordAtDocumentEnd() {
        let source = "Start here.\n\nEnd word."
        let range = findRange(word: "word", in: source, sourceLine: 3)
        XCTAssertNotNil(range)
        XCTAssertEqual(range!.location + range!.length, source.count - 1) // before the "."
    }

    func testCaseInsensitiveMatching() {
        let source = "Hello world.\n\nhello again."
        // Both "Hello" and "hello" should be found case-insensitively
        let range1 = findRange(word: "Hello", in: source, sourceLine: 1)
        let range2 = findRange(word: "Hello", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testEmptySource() {
        let range = findRange(word: "test", in: "", sourceLine: 1)
        XCTAssertNil(range)
    }

    func testNoSourceLine() {
        // When sourceLine is -1 (fallback), should pick middle occurrence
        let source = "word at start.\n\nword in middle.\n\nword at end."
        let range = findRange(word: "word", in: source, sourceLine: -1)
        XCTAssertNotNil(range)
        // Should pick the one closest to the middle of the document
    }

    func testInvalidSourceLine() {
        let source = "Short document."
        let range = findRange(word: "Short", in: source, sourceLine: 999)
        XCTAssertNotNil(range)
        // Should still find the word via fallback
    }

    func testWordWithSpecialCharacters() {
        let source = "C++ is great.\n\nC++ is powerful."
        let range1 = findRange(word: "C++", in: source, sourceLine: 1)
        let range2 = findRange(word: "C++", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordWithUnicode() {
        let source = "The café is nice.\n\nAnother café here."
        let range1 = findRange(word: "café", in: source, sourceLine: 1)
        let range2 = findRange(word: "café", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testWordWithEmoji() {
        let source = "Hello 🎉 world.\n\nHello 🎉 again."
        let range1 = findRange(word: "Hello", in: source, sourceLine: 1)
        let range2 = findRange(word: "Hello", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    // =========================================================================
    // MARK: - findWordRange: complex document structures
    // =========================================================================

    func testNestedListsWithDuplicateWords() {
        let source = "- outer item\n  - inner item\n  - another inner item\n- second outer item"
        let range1 = findRange(word: "item", in: source, sourceLine: 1, offsetInBlock: 6)
        let range4 = findRange(word: "item", in: source, sourceLine: 4, offsetInBlock: 13)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range4)
        XCTAssertNotEqual(range1!.location, range4!.location)
    }

    func testCodeBlockContentNotMatchedAsBlock() {
        // Words inside code blocks are on the <pre> source line
        let source = "Use data variable.\n\n```\ndata = 42\n```\n\nMore data here."
        let range1 = findRange(word: "data", in: source, sourceLine: 1, offsetInBlock: 4)
        let range3 = findRange(word: "data", in: source, sourceLine: 7, offsetInBlock: 5)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range3)
        XCTAssertNotEqual(range1!.location, range3!.location)
    }

    func testHeadingsAtMultipleLevels() {
        let source = "# Section\n\n## Section\n\n### Section"
        // "Section" appears 3 times, each at different heading levels
        let range1 = findRange(word: "Section", in: source, sourceLine: 1)
        let range2 = findRange(word: "Section", in: source, sourceLine: 3)
        let range3 = findRange(word: "Section", in: source, sourceLine: 5)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        XCTAssertLessThan(range1!.location, range2!.location)
        XCTAssertLessThan(range2!.location, range3!.location)
    }

    func testAdjacentParagraphsWithSameContent() {
        let source = "identical text here.\n\nidentical text here.\n\nidentical text here."
        let range1 = findRange(word: "identical", in: source, sourceLine: 1)
        let range2 = findRange(word: "identical", in: source, sourceLine: 3)
        let range3 = findRange(word: "identical", in: source, sourceLine: 5)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotNil(range3)
        XCTAssertLessThan(range1!.location, range2!.location)
        XCTAssertLessThan(range2!.location, range3!.location)
    }

    func testWordInHorizontalRuleSeparatedSections() {
        let source = "word here.\n\n---\n\nword there."
        let range1 = findRange(word: "word", in: source, sourceLine: 1)
        let range2 = findRange(word: "word", in: source, sourceLine: 5)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    // =========================================================================
    // MARK: - findWordRange: comments interaction
    // =========================================================================

    func testWordNearCommentAnnotation() {
        // Comment markers are preprocessed before parsing, which may shift offsets
        let source = "The <!-- COMMENT: note -->word<!-- /COMMENT --> here.\n\nAnother word there."
        let range1 = findRange(word: "word", in: source, sourceLine: 1)
        let range2 = findRange(word: "word", in: source, sourceLine: 3)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
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
        for i in 0..<50 {
            let parserLine = i * 2 + 1
            let range = findRange(word: "test", in: source, sourceLine: parserLine)
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
            let _ = findRange(word: "target", in: source, sourceLine: 290, offsetInBlock: 10)
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
        let range1 = findRange(word: "word", in: source, sourceLine: 1, offsetInBlock: 0)
        let range2 = findRange(word: "word", in: source, sourceLine: 4, offsetInBlock: 20)
        XCTAssertNotNil(range1)
        XCTAssertNotNil(range2)
        XCTAssertNotEqual(range1!.location, range2!.location)
    }

    func testBlockExtentStopsAtHeading() {
        let source = "word in paragraph.\n# Heading with word\nword after heading."
        // Paragraph at line 1, heading at line 2, paragraph at line 3
        let range1 = findRange(word: "word", in: source, sourceLine: 1, offsetInBlock: 0)
        XCTAssertNotNil(range1)
        // Should only find "word" in the first paragraph's range
        let firstLineEnd = "word in paragraph.".count
        XCTAssertLessThan(range1!.location, firstLineEnd)
    }

    func testBlockExtentHandlesLastLine() {
        let source = "First.\n\nLast line with word."
        let range = findRange(word: "word", in: source, sourceLine: 3)
        XCTAssertNotNil(range)
        XCTAssertGreaterThan(range!.location, 8) // Past "First.\n\n"
    }
}
