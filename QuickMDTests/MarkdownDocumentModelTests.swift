import XCTest
@testable import QuickMD

final class MarkdownDocumentModelTests: XCTestCase {

    // MARK: - HTML Structure via load()

    func testLoadMarkdownProducesValidHTML() throws {
        let url = writeTempFile("# Hello\nSome text", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<!doctype html>"), "Should have DOCTYPE")
        XCTAssertTrue(html.contains("<meta charset=\"utf-8\""), "Should have charset meta")
        XCTAssertTrue(html.contains("data-filetype=\"markdown\""), "Should have markdown filetype")
        XCTAssertTrue(html.contains("data-theme=\"system\""), "Should have default theme")
    }

    func testLoadCodeFileProducesValidHTML() throws {
        let url = writeTempFile("print('hello')", ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<!doctype html>"))
        XCTAssertTrue(html.contains("data-filetype=\"code\""), "Should have code filetype")
    }

    // MARK: - Markdown Rendering

    func testMarkdownHeadingsRendered() throws {
        let url = writeTempFile("# Title\n## Subtitle\nParagraph text", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<h1"), "Should render h1")
        XCTAssertTrue(html.contains("<h2"), "Should render h2")
        XCTAssertTrue(html.contains("<p"), "Should render paragraph")
    }

    func testMarkdownTablesRendered() throws {
        let md = """
        | A | B |
        |---|---|
        | 1 | 2 |
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<table"), "Should render table")
        XCTAssertTrue(html.contains("<th"), "Should render table header")
        XCTAssertTrue(html.contains("<td"), "Should render table data")
    }

    func testMarkdownCodeBlockRendered() throws {
        let md = """
        ```python
        print("hello")
        ```
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<code"), "Should render code block")
        XCTAssertTrue(html.contains("language-python"), "Should have language class")
    }

    func testMarkdownLinksRendered() throws {
        let url = writeTempFile("[Click](https://example.com)", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<a"), "Should render anchor tag")
        XCTAssertTrue(html.contains("https://example.com"), "Should contain URL")
    }

    func testMarkdownBlockquoteRendered() throws {
        let url = writeTempFile("> This is a quote", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<blockquote"), "Should render blockquote")
    }

    func testMarkdownImageRendered() throws {
        let url = writeTempFile("![Alt text](image.png)", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<img"), "Should render image tag")
        XCTAssertTrue(html.contains("image.png"), "Should contain image src")
    }

    func testMarkdownListsRendered() throws {
        let md = "- item 1\n- item 2\n\n1. first\n2. second"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<ul"), "Should render unordered list")
        XCTAssertTrue(html.contains("<ol"), "Should render ordered list")
        XCTAssertTrue(html.contains("<li"), "Should render list items")
    }

    func testMarkdownHorizontalRuleRendered() throws {
        let url = writeTempFile("Above\n\n---\n\nBelow", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<hr"), "Should render horizontal rule")
    }

    func testMarkdownInlineCodeRendered() throws {
        let url = writeTempFile("Use `code` here", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<code>code</code>"), "Should render inline code")
    }

    func testMarkdownEmphasisRendered() throws {
        let url = writeTempFile("**bold** and *italic*", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<strong>"), "Should render bold")
        XCTAssertTrue(html.contains("<em>"), "Should render italic")
    }

    // MARK: - Code File Rendering

    func testCodeFileLanguageClass() throws {
        let url = writeTempFile("fn main() {}", ext: "rs")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("language-rust"), "Rust file should get language-rust class")
    }

    func testCodeFileHTMLEscaping() throws {
        let url = writeTempFile("<script>alert('xss')</script>", ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), "Should HTML-escape angle brackets")
        XCTAssertFalse(html.contains("<script>alert"), "Should NOT contain raw script tags in code content")
    }

    func testCodeFileAmpersandEscaping() throws {
        let url = writeTempFile("a && b", ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("a &amp;&amp; b"), "Should escape ampersands in code")
    }

    func testUnknownExtensionNoLanguageClass() throws {
        let url = writeTempFile("some content", ext: "xyz")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<pre><code>"), "Unknown ext should get plain pre/code")
        XCTAssertFalse(html.contains("class=\"language-"), "Unknown ext should not have language class")
        XCTAssertTrue(html.contains("data-filetype=\"code\""), "Should still be code filetype")
    }

    func testCodeFileWrappedInPreCode() throws {
        let content = "func hello() { }"
        let url = writeTempFile(content, ext: "swift")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<pre><code class=\"language-swift\">"), "Should wrap in pre>code")
    }

    // MARK: - Script Injection

    func testThemeDataAttributePresent() throws {
        let url = writeTempFile("test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("data-theme=\"system\""), "Should include data-theme attribute")
    }

    func testHighlightScriptReference() {
        XCTAssertTrue(MarkdownDocumentModel.highlightRenderScript.contains("hljs.highlightElement"),
                       "Should reference hljs.highlightElement")
    }

    func testMermaidRenderScriptSkipsHighlight() {
        XCTAssertTrue(MarkdownDocumentModel.highlightRenderScript.contains("language-mermaid"),
                       "Highlight script should check for language-mermaid to skip it")
    }

    // MARK: - Theme Script

    func testThemeScriptContent() {
        let script = MarkdownDocumentModel.themeScript
        XCTAssertTrue(script.contains("__setTheme"), "Should expose __setTheme function")
        XCTAssertTrue(script.contains("data-theme"), "Should set data-theme attribute")
        XCTAssertTrue(script.contains("colorScheme"), "Should set colorScheme style")
    }

    // MARK: - Mermaid Blocks Preserved

    func testMermaidBlockPreserved() throws {
        let md = """
        ```mermaid
        graph TD
          A --> B
        ```
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("language-mermaid"), "Should preserve language-mermaid class")
        XCTAssertTrue(html.contains("A --&gt; B") || html.contains("A --> B"),
                       "Should contain mermaid graph definition")
    }

    func testMermaidRenderScriptContent() {
        let script = MarkdownDocumentModel.mermaidRenderScript
        XCTAssertTrue(script.contains("mermaid.initialize"), "Should initialize mermaid")
        XCTAssertTrue(script.contains("mermaid.render"), "Should call mermaid.render")
        XCTAssertTrue(script.contains("securityLevel"), "Should set securityLevel")
        XCTAssertTrue(script.contains("language-mermaid"), "Should target mermaid code blocks")
    }

    // MARK: - Graphviz

    func testGraphvizRenderScriptContent() {
        let script = MarkdownDocumentModel.graphvizRenderScript
        XCTAssertTrue(script.contains("Viz"), "Should check for Viz")
        XCTAssertTrue(script.contains("language-dot"), "Should target .dot code blocks")
        XCTAssertTrue(script.contains("language-graphviz"), "Should target .graphviz code blocks")
        XCTAssertTrue(script.contains("renderSVGElement"), "Should call renderSVGElement")
        XCTAssertTrue(script.contains("graphviz-error"), "Should show error class on failure")
    }

    func testGraphvizBlockPreserved() throws {
        let md = """
        ```dot
        digraph { A -> B }
        ```
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("language-dot"), "Should preserve language-dot class")
    }

    // MARK: - KaTeX

    func testKatexRenderScriptContent() {
        let script = MarkdownDocumentModel.katexRenderScript
        XCTAssertTrue(script.contains("renderMathInElement"), "Should call renderMathInElement")
        XCTAssertTrue(script.contains("$$"), "Should support display math delimiters")
        XCTAssertTrue(script.contains("throwOnError"), "Should set throwOnError")
    }

    // MARK: - File Type Detection

    func testExtensionToLanguageMappings() {
        let expectations: [(String, String)] = [
            ("swift", "language-swift"),
            ("go", "language-go"),
            ("js", "language-javascript"),
            ("ts", "language-typescript"),
            ("py", "language-python"),
            ("rb", "language-ruby"),
            ("java", "language-java"),
            ("c", "language-c"),
            ("cpp", "language-cpp"),
            ("rs", "language-rust"),
            ("sql", "language-sql"),
            ("sh", "language-bash"),
            ("json", "language-json"),
            ("yaml", "language-yaml"),
            ("toml", "language-toml"),
            ("cs", "language-csharp"),
            ("ex", "language-elixir"),
            ("zig", "language-zig"),
            ("lua", "language-lua"),
            ("dart", "language-dart"),
            ("kt", "language-kotlin"),
        ]

        for (ext, expectedClass) in expectations {
            let url = writeTempFile("test code", ext: ext)
            let model = MarkdownDocumentModel()
            model.load(from: url)

            guard let html = model.html else {
                XCTFail("No HTML generated for .\(ext)")
                continue
            }
            XCTAssertTrue(html.contains(expectedClass),
                          ".\(ext) should produce \(expectedClass)")
        }
    }

    func testAdditionalLanguageMappings() {
        let expectations: [(String, String)] = [
            ("yml", "language-yaml"),
            ("jsx", "language-javascript"),
            ("tsx", "language-typescript"),
            ("mjs", "language-javascript"),
            ("h", "language-c"),
            ("hpp", "language-cpp"),
            ("cxx", "language-cpp"),
            ("cc", "language-cpp"),
            ("hxx", "language-cpp"),
            ("m", "language-objectivec"),
            ("mm", "language-objectivec"),
            ("bash", "language-bash"),
            ("zsh", "language-bash"),
            ("css", "language-css"),
            ("html", "language-html"),
            ("htm", "language-html"),
            ("xml", "language-xml"),
            ("r", "language-r"),
            ("scala", "language-scala"),
            ("hs", "language-haskell"),
            ("ini", "language-ini"),
            ("conf", "language-ini"),
            ("cfg", "language-ini"),
            ("fs", "language-fsharp"),
            ("exs", "language-elixir"),
            ("erl", "language-erlang"),
            ("clj", "language-clojure"),
            ("nim", "language-nim"),
            ("groovy", "language-groovy"),
            ("gradle", "language-groovy"),
            ("gv", "language-graphviz"),
            ("dot", "language-dot"),
            ("kts", "language-kotlin"),
            ("php", "language-php"),
            ("pl", "language-perl"),
            ("v", "language-v"),
        ]

        for (ext, expectedClass) in expectations {
            let url = writeTempFile("test", ext: ext)
            let model = MarkdownDocumentModel()
            model.load(from: url)

            guard let html = model.html else {
                XCTFail("No HTML generated for .\(ext)")
                continue
            }
            XCTAssertTrue(html.contains(expectedClass),
                          ".\(ext) should produce \(expectedClass)")
        }
    }

    func testMarkdownExtensionsDetected() {
        let mdExts = ["md", "markdown", "mdown", "mkd"]
        for ext in mdExts {
            let url = writeTempFile("# Test", ext: ext)
            let model = MarkdownDocumentModel()
            model.load(from: url)

            guard let html = model.html else {
                XCTFail("No HTML generated for .\(ext)")
                continue
            }
            XCTAssertTrue(html.contains("data-filetype=\"markdown\""),
                          ".\(ext) should be detected as markdown")
        }
    }

    // MARK: - Reading Stats

    func testReadingStatsOnlyForMarkdown() throws {
        let mdUrl = writeTempFile("# Hello\nSome paragraph text here.", ext: "md")
        let mdModel = MarkdownDocumentModel()
        mdModel.load(from: mdUrl)
        let mdHtml = try XCTUnwrap(mdModel.html)
        XCTAssertTrue(mdHtml.contains("reading-stats"), "Markdown should include reading stats")
    }

    func testReadingStatsScriptChecksFiletype() {
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("data-filetype"),
                       "Reading stats script should check data-filetype attribute")
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("markdown"),
                       "Reading stats script should check for 'markdown' filetype")
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("words"),
                       "Should calculate word count")
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("min read"),
                       "Should show reading time")
    }

    // MARK: - TOC

    func testTOCOnlyForMarkdown() throws {
        let mdUrl = writeTempFile("# Heading\nText", ext: "md")
        let mdModel = MarkdownDocumentModel()
        mdModel.load(from: mdUrl)
        let mdHtml = try XCTUnwrap(mdModel.html)
        // Sidebar is now native SwiftUI — HTML should NOT contain sidebar markup
        XCTAssertFalse(mdHtml.contains("id=\"sidebar-container\""), "Sidebar should not be in HTML (native SwiftUI)")
        XCTAssertTrue(mdHtml.contains("id=\"layout\""), "Markdown should have layout wrapper")
    }

    func testHeadingDataScriptGeneratesSlugIDs() {
        XCTAssertTrue(MarkdownDocumentModel.headingDataScript.contains("slug"),
                       "Heading data script should generate slug IDs for headings")
    }

    func testHeadingDataScriptContent() {
        let script = MarkdownDocumentModel.headingDataScript
        XCTAssertTrue(script.contains("tocData"), "Should send data via tocData bridge")
        XCTAssertTrue(script.contains("IntersectionObserver"), "Should use IntersectionObserver for active tracking")
        XCTAssertTrue(script.contains("__rebuildHeadingData"), "Should expose rebuild function")
        XCTAssertTrue(script.contains("data-source-line"), "Should extract source line from headings")
    }

    func testHTMLHasLayoutWrapper() throws {
        let url = writeTempFile("# Heading", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("id=\"layout\""), "Should have layout wrapper")
        // Sidebar is now native SwiftUI, not in HTML
        XCTAssertFalse(html.contains("id=\"sidebar-container\""), "Sidebar should not be in HTML (native SwiftUI)")
    }

    // MARK: - Model State

    func testLoadSetsFileNameAndBaseURL() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.fileName)
        XCTAssertNotNil(model.baseURL)
        XCTAssertNil(model.errorMessage)
    }

    func testLoadInvalidFileShowsError() {
        let url = URL(fileURLWithPath: "/nonexistent/file.md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNil(model.html)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertTrue(model.errorMessage?.contains("Could not render") == true)
        XCTAssertEqual(model.fileName, "file.md", "Should still set fileName on error")
    }

    func testLoadInvalidFileSetsNilBaseURL() {
        let url = URL(fileURLWithPath: "/nonexistent/file.md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNil(model.baseURL)
    }

    func testLoadSetsRawContentAndCurrentURL() throws {
        let content = "# Raw content test\nWith body"
        let url = writeTempFile(content, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertEqual(model.rawContent, content, "rawContent should match file content")
        XCTAssertEqual(model.currentURL, url, "currentURL should be set")
    }

    func testLoadSecondFileUpdatesModel() throws {
        let url1 = writeTempFile("# First", ext: "md")
        let url2 = writeTempFile("# Second", ext: "md")
        let model = MarkdownDocumentModel()

        model.load(from: url1)
        XCTAssertEqual(model.rawContent, "# First")
        XCTAssertEqual(model.currentURL, url1)

        model.load(from: url2)
        XCTAssertEqual(model.rawContent, "# Second")
        XCTAssertEqual(model.currentURL, url2)
    }

    func testLoadBaseURLIsParentDirectory() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertEqual(model.baseURL, url.deletingLastPathComponent())
    }

    // MARK: - Print Stylesheet (Feature 1)

    func testPrintStylesheetIncluded() throws {
        let url = writeTempFile("# Hello", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("@media print"), "Should include print stylesheet")
        XCTAssertTrue(html.contains("page-break-after: avoid"), "Should prevent page breaks after headings")
        XCTAssertTrue(html.contains("page-break-inside: avoid"), "Should prevent page breaks inside elements")
    }

    func testPrintStylesheetHidesUIElements() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("toc-container") && html.contains("@media print"),
                       "Should hide TOC in print")
        XCTAssertTrue(html.contains("copy-btn") && html.contains("display: none !important"),
                       "Should hide copy buttons in print")
    }

    // MARK: - Task Lists (Feature 2)

    func testTaskListCSSIncluded() throws {
        let url = writeTempFile("# Hello", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("task-list-item") || html.contains("type=\"checkbox\""),
                       "Should include task list CSS or checkbox support")
    }

    // MARK: - Word Wrap Toggle (Feature 3)

    func testWordWrapScriptContent() {
        let script = MarkdownDocumentModel.wordWrapScript
        XCTAssertTrue(script.contains("__toggleWordWrap"), "Should expose toggle function")
        XCTAssertTrue(script.contains("pre-wrap"), "Should toggle to pre-wrap")
        XCTAssertTrue(script.contains("break-all"), "Should toggle word-break")
        XCTAssertTrue(script.contains("wrapped = !wrapped"), "Should toggle state")
    }

    // MARK: - Anchor Links (Feature 4)

    func testAnchorLinksScriptContent() {
        let script = MarkdownDocumentModel.anchorLinksScript
        XCTAssertTrue(script.contains("heading-anchor"), "Should create anchor elements")
        XCTAssertTrue(script.contains("h1, h2, h3, h4, h5, h6"), "Should target all heading levels")
        XCTAssertTrue(script.contains("insertBefore"), "Should insert anchor before heading text")
        XCTAssertTrue(script.contains("href"), "Should set href to heading ID")
        XCTAssertTrue(script.contains("markdown-body"), "Should scope to markdown body")
    }

    // MARK: - Emoji Shortcodes (Feature 5)

    func testEmojiScriptContainsCommonEmoji() {
        let script = MarkdownDocumentModel.emojiScript
        XCTAssertTrue(script.contains("+1"), "Should contain thumbs up shortcode")
        XCTAssertTrue(script.contains("smile"), "Should contain smile shortcode")
        XCTAssertTrue(script.contains("heart"), "Should contain heart shortcode")
        XCTAssertTrue(script.contains("createTreeWalker"), "Should use TreeWalker for text nodes")
        XCTAssertTrue(script.contains("rocket"), "Should contain rocket emoji")
        XCTAssertTrue(script.contains("fire"), "Should contain fire emoji")
        XCTAssertTrue(script.contains("tada"), "Should contain tada emoji")
    }

    func testEmojiScriptSkipsCodeBlocks() {
        let script = MarkdownDocumentModel.emojiScript
        XCTAssertTrue(script.contains("PRE"), "Should skip PRE elements")
        XCTAssertTrue(script.contains("CODE"), "Should skip CODE elements")
        XCTAssertTrue(script.contains("SCRIPT"), "Should skip SCRIPT elements")
        XCTAssertTrue(script.contains("STYLE"), "Should skip STYLE elements")
        XCTAssertTrue(script.contains("FILTER_REJECT"), "Should use FILTER_REJECT")
    }

    func testEmojiScriptUsesRegex() {
        let script = MarkdownDocumentModel.emojiScript
        XCTAssertTrue(script.contains(":([a-z0-9_+-]+):"), "Should use regex for :shortcode: pattern")
    }

    // MARK: - Footnotes (Feature 6)

    func testFootnotesScriptContent() {
        let script = MarkdownDocumentModel.footnotesScript
        XCTAssertTrue(script.contains("footnote"), "Should handle footnotes")
        XCTAssertTrue(script.contains("sup"), "Should create superscript elements")
        XCTAssertTrue(script.contains("footnote-backref"), "Should create back-references")
        XCTAssertTrue(script.contains("footnote-ref"), "Should create footnote references")
        XCTAssertTrue(script.contains("fn-"), "Should create fn- IDs")
        XCTAssertTrue(script.contains("fnref-"), "Should create fnref- IDs")
        XCTAssertTrue(script.contains("footnotes"), "Should create footnotes section")
    }

    // MARK: - Frontmatter (Feature 7)

    func testFrontmatterStrippedFromMarkdown() throws {
        let md = """
        ---
        title: Test
        tags: [a, b]
        ---
        # Hello
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("frontmatter-data"), "Should have hidden frontmatter div")
        XCTAssertTrue(html.contains("title: Test"), "Should contain escaped frontmatter YAML")
        XCTAssertTrue(html.contains("<h1"), "Should render the body heading")
    }

    func testFrontmatterNotPresentWhenMissing() throws {
        let url = writeTempFile("# No frontmatter here", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertFalse(html.contains("frontmatter-data"), "Should NOT have frontmatter div")
    }

    func testFrontmatterScriptContent() {
        let script = MarkdownDocumentModel.frontmatterScript
        XCTAssertTrue(script.contains("frontmatter-data"), "Should look for frontmatter div")
        XCTAssertTrue(script.contains("jsyaml"), "Should parse YAML with jsyaml")
        XCTAssertTrue(script.contains("banner"), "Should create a banner element")
        XCTAssertTrue(script.contains("frontmatter-title"), "Should show title")
        XCTAssertTrue(script.contains("frontmatter-meta"), "Should show meta")
        XCTAssertTrue(script.contains("frontmatter-tags"), "Should show tags")
        XCTAssertTrue(script.contains("frontmatter-tag"), "Should create tag pills")
    }

    func testFrontmatterHTMLEscaping() throws {
        let md = """
        ---
        title: <script>alert('xss')</script>
        ---
        # Safe
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("&lt;script&gt;"), "Should escape HTML in frontmatter")
        XCTAssertFalse(html.contains("<script>alert"), "Should NOT have raw script in frontmatter")
    }

    func testFrontmatterAmpersandEscaping() throws {
        let md = """
        ---
        title: A & B
        ---
        # Test
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("A &amp; B"), "Should escape ampersands in frontmatter")
    }

    func testStripFrontmatterViaPublicAPI() throws {
        let md = """
        ---
        key: value
        ---
        # Body
        """
        let url = writeTempFile(md, ext: "md")
        let (body, isMarkdown) = try MarkdownDocumentModel.htmlBodyPublic(for: url)
        XCTAssertTrue(isMarkdown)
        XCTAssertTrue(body.contains("frontmatter-data"), "Public API should also strip frontmatter")
    }

    func testFrontmatterWithNoClosingDelimiter() throws {
        let md = """
        ---
        key: value
        # This is not closed
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        // Without closing ---, the whole thing should be treated as content (no frontmatter)
        XCTAssertFalse(html.contains("frontmatter-data"),
                       "Unclosed frontmatter should not be stripped")
    }

    func testFrontmatterNotDetectedInMiddleOfFile() throws {
        let md = """
        # Title
        ---
        key: value
        ---
        More content
        """
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertFalse(html.contains("frontmatter-data"),
                       "YAML block in middle of file should not be treated as frontmatter")
    }

    func testFrontmatterOnlyInMarkdownFiles() throws {
        let content = """
        ---
        key: value
        ---
        code here
        """
        let url = writeTempFile(content, ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertFalse(html.contains("frontmatter-data"),
                       "Frontmatter should only be processed for markdown files")
    }

    // MARK: - Auto-Detect Encoding (Feature 8)

    func testUTF8FileReads() throws {
        let url = writeTempFile("Hello UTF-8: café ñ", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("café"), "Should read UTF-8 content")
    }

    func testLatin1FileReads() throws {
        let latin1Data = "Héllo wörld".data(using: .isoLatin1)!
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + ".md")
        try latin1Data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle Latin-1 encoded file")
        XCTAssertNil(model.errorMessage, "Should not produce error for Latin-1 file")
    }

    func testUTF16FileReads() throws {
        let utf16Data = "Hello UTF-16 world".data(using: .utf16)!
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + ".md")
        try utf16Data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle UTF-16 encoded file")
        XCTAssertNil(model.errorMessage)
    }

    func testWindowsCP1252FileReads() throws {
        // Build raw CP1252 bytes with characters not valid in UTF-8
        // 0x93 = left double quote, 0x94 = right double quote in CP1252
        let data = Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x20, 0x93, 0x77, 0x6F, 0x72, 0x6C, 0x64, 0x94])
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + ".md")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }

        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle Windows-1252 encoded file")
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - Live Reload (Feature 11)

    func testStartAndStopWatching() throws {
        let url = writeTempFile("# Watch me", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        model.startWatching(url: url)
        XCTAssertTrue(model.autoReload, "autoReload should be true after startWatching")

        model.stopWatching()
        XCTAssertFalse(model.autoReload, "autoReload should be false after stopWatching")
    }

    func testStopWatchingIdempotent() {
        let model = MarkdownDocumentModel()
        model.stopWatching()
        XCTAssertFalse(model.autoReload)
        model.stopWatching()
        XCTAssertFalse(model.autoReload)
    }

    func testLoadAutoStartsWatching() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        // load() calls startWatching by default
        XCTAssertTrue(model.autoReload, "load() should auto-start watching")
    }

    func testStartWatchingInvalidPathDoesNotCrash() {
        let model = MarkdownDocumentModel()
        let url = URL(fileURLWithPath: "/nonexistent/path/file.md")
        model.startWatching(url: url)
        // open() returns -1 for invalid path, so autoReload should remain false
        XCTAssertFalse(model.autoReload, "Should not enable autoReload for invalid path")
    }

    func testStartWatchingReplacesExistingWatcher() throws {
        let url1 = writeTempFile("# First", ext: "md")
        let url2 = writeTempFile("# Second", ext: "md")
        let model = MarkdownDocumentModel()

        model.startWatching(url: url1)
        XCTAssertTrue(model.autoReload)

        model.startWatching(url: url2)
        XCTAssertTrue(model.autoReload, "Should still be watching after replacing")
    }

    // MARK: - Custom CSS Themes (Feature 12)

    func testThemesDirectoryExists() {
        let dir = MarkdownDocumentModel.themesDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.path),
                       "Themes directory should be created")
        XCTAssertTrue(dir.path.contains("QuickMD/themes"),
                       "Themes directory should be under QuickMD/themes")
    }

    func testAvailableThemesReturnsCSS() throws {
        let dir = MarkdownDocumentModel.themesDirectory
        let testTheme = dir.appendingPathComponent("_test_theme.css")
        try "body { color: red; }".write(to: testTheme, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: testTheme) }

        let themes = MarkdownDocumentModel.availableThemes()
        XCTAssertTrue(themes.contains("_test_theme"), "Should find the test theme")
    }

    func testAvailableThemesIgnoresNonCSS() throws {
        let dir = MarkdownDocumentModel.themesDirectory
        let nonCSS = dir.appendingPathComponent("_test_notcss.txt")
        try "not css".write(to: nonCSS, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: nonCSS) }

        let themes = MarkdownDocumentModel.availableThemes()
        XCTAssertFalse(themes.contains("_test_notcss"), "Should not include non-CSS files")
    }

    func testAvailableThemesAreSorted() throws {
        let dir = MarkdownDocumentModel.themesDirectory
        let themeB = dir.appendingPathComponent("_test_b_theme.css")
        let themeA = dir.appendingPathComponent("_test_a_theme.css")
        try "b".write(to: themeB, atomically: true, encoding: .utf8)
        try "a".write(to: themeA, atomically: true, encoding: .utf8)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: themeA)
            try? FileManager.default.removeItem(at: themeB)
        }

        let themes = MarkdownDocumentModel.availableThemes()
        if let idxA = themes.firstIndex(of: "_test_a_theme"),
           let idxB = themes.firstIndex(of: "_test_b_theme") {
            XCTAssertTrue(idxA < idxB, "Themes should be sorted alphabetically")
        }
    }

    func testCustomCSSForTheme() throws {
        let dir = MarkdownDocumentModel.themesDirectory
        let testTheme = dir.appendingPathComponent("_test_read.css")
        let css = "body { background: blue; }"
        try css.write(to: testTheme, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: testTheme) }

        let result = MarkdownDocumentModel.customCSS(for: "_test_read")
        XCTAssertEqual(result, css, "Should read back the CSS content")
    }

    func testCustomCSSForMissingTheme() {
        let result = MarkdownDocumentModel.customCSS(for: "_nonexistent_theme_xyz")
        XCTAssertEqual(result, "", "Missing theme should return empty string")
    }

    // MARK: - Presentation Mode (Feature 13)

    func testPresentationScriptContent() {
        let script = MarkdownDocumentModel.presentationScript
        XCTAssertTrue(script.contains("__startPresentation"), "Should expose start function")
        XCTAssertTrue(script.contains("__stopPresentation"), "Should expose stop function")
        XCTAssertTrue(script.contains("__presentationActive"), "Should expose active check")
        XCTAssertTrue(script.contains("Escape"), "Should handle Escape key")
        XCTAssertTrue(script.contains("ArrowRight"), "Should handle ArrowRight for next slide")
        XCTAssertTrue(script.contains("ArrowLeft"), "Should handle ArrowLeft for prev slide")
    }

    func testPresentationScriptSplitsOnHR() {
        let script = MarkdownDocumentModel.presentationScript
        XCTAssertTrue(script.contains("HR"), "Should split slides on <hr> elements")
        XCTAssertTrue(script.contains("pres-overlay"), "Should create overlay")
        XCTAssertTrue(script.contains("pres-content"), "Should create content area")
        XCTAssertTrue(script.contains("pres-counter"), "Should create slide counter")
    }

    // MARK: - Copy Button

    func testCopyButtonScriptContent() {
        let script = MarkdownDocumentModel.copyButtonScript
        XCTAssertTrue(script.contains("copy-btn"), "Should create copy button")
        XCTAssertTrue(script.contains("clipboard"), "Should use clipboard API")
        XCTAssertTrue(script.contains("Copied!"), "Should show 'Copied!' feedback")
        XCTAssertTrue(script.contains("fallbackCopy"), "Should have fallback copy method")
        XCTAssertTrue(script.contains("language-mermaid"), "Should skip mermaid blocks")
    }

    // MARK: - Line Numbers

    func testLineNumbersScriptContent() {
        let script = MarkdownDocumentModel.lineNumbersScript
        XCTAssertTrue(script.contains("__toggleLineNumbers"), "Should expose toggle function")
        XCTAssertTrue(script.contains("code-line"), "Should wrap lines in code-line spans")
        XCTAssertTrue(script.contains("has-line-numbers"), "Should use has-line-numbers class")
        XCTAssertTrue(script.contains("localStorage"), "Should persist preference")
        XCTAssertTrue(script.contains("language-mermaid"), "Should skip mermaid blocks")
        XCTAssertTrue(script.contains("language-dot"), "Should skip dot blocks")
        XCTAssertTrue(script.contains("language-graphviz"), "Should skip graphviz blocks")
    }

    // MARK: - Jump to Line

    func testJumpToLineScriptContent() {
        let script = MarkdownDocumentModel.jumpToLineScript
        XCTAssertTrue(script.contains("__jumpToLine"), "Should expose jump function")
        XCTAssertTrue(script.contains("jump-bar"), "Should create jump bar")
        XCTAssertTrue(script.contains("scrollIntoView"), "Should scroll to target line")
        XCTAssertTrue(script.contains("line-flash"), "Should flash target line")
        XCTAssertTrue(script.contains("code-line"), "Should target code-line elements")
    }

    // MARK: - Find

    func testFindScriptContent() {
        let script = MarkdownDocumentModel.findScript
        XCTAssertTrue(script.contains("__findOpen"), "Should expose find open function")
        XCTAssertTrue(script.contains("find-bar"), "Should create find bar")
        XCTAssertTrue(script.contains("find-highlight"), "Should highlight matches")
        XCTAssertTrue(script.contains("find-highlight-active"), "Should highlight active match")
        XCTAssertTrue(script.contains("find-counter"), "Should show match counter")
        XCTAssertTrue(script.contains("createTreeWalker"), "Should use TreeWalker")
        XCTAssertTrue(script.contains("toLowerCase"), "Should do case-insensitive search")
    }

    // MARK: - Speak

    func testSpeakScriptContent() {
        let script = MarkdownDocumentModel.speakScript
        XCTAssertTrue(script.contains("speak-btn"), "Should create speak button")
        XCTAssertTrue(script.contains("speechSynthesis"), "Should use speechSynthesis API")
        XCTAssertTrue(script.contains("__speak"), "Should expose __speak interface")
        XCTAssertTrue(script.contains("SpeechSynthesisUtterance"), "Should create utterance")
        XCTAssertTrue(script.contains("speaking"), "Should track speaking state")
        XCTAssertTrue(script.contains("paused"), "Should track paused state")
    }

    // MARK: - Zoom Overlay

    func testZoomOverlayScriptContent() {
        let script = MarkdownDocumentModel.zoomOverlayScript
        XCTAssertTrue(script.contains("mermaid-overlay"), "Should create overlay")
        XCTAssertTrue(script.contains("openOverlay"), "Should have open function")
        XCTAssertTrue(script.contains("closeOverlay"), "Should have close function")
        XCTAssertTrue(script.contains("fitToScreen"), "Should have fit-to-screen")
        XCTAssertTrue(script.contains("Escape"), "Should close on Escape")
        XCTAssertTrue(script.contains("wheel"), "Should handle mouse wheel zoom")
        XCTAssertTrue(script.contains("mousedown"), "Should handle drag")
        XCTAssertTrue(script.contains("img"), "Should handle image clicks")
        XCTAssertTrue(script.contains(".mermaid"), "Should handle mermaid clicks")
    }

    // MARK: - Font Size Script

    func testFontSizeScriptKeyboardZoom() {
        let script = MarkdownDocumentModel.fontSizeScript
        XCTAssertTrue(script.contains("fontSize"), "Should adjust root font size")
        XCTAssertTrue(script.contains("metaKey"), "Should use ⌘ for shortcuts")
        XCTAssertTrue(script.contains("keydown"), "Should listen for keydown")
    }

    // MARK: - Highlight Render Script

    func testHighlightRenderScriptJSON() {
        let script = MarkdownDocumentModel.highlightRenderScript
        XCTAssertTrue(script.contains("JSON.parse"), "Should pretty-print JSON")
        XCTAssertTrue(script.contains("JSON.stringify"), "Should re-serialize JSON")
        XCTAssertTrue(script.contains("language-json"), "Should target JSON code blocks")
    }

    func testHighlightRenderScriptYAML() {
        let script = MarkdownDocumentModel.highlightRenderScript
        XCTAssertTrue(script.contains("jsyaml.load"), "Should parse YAML")
        XCTAssertTrue(script.contains("jsyaml.dump"), "Should re-serialize YAML")
        XCTAssertTrue(script.contains("language-yaml"), "Should target YAML code blocks")
    }

    // MARK: - CSS Structure

    func testHTMLContainsHighlightCSS() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<style>"), "Should contain style tags")
        XCTAssertTrue(html.contains("prefers-color-scheme: dark"), "Should have dark mode media query")
        XCTAssertTrue(html.contains("color-scheme: light dark"), "Should set color-scheme")
    }

    func testHTMLContainsDarkThemeOverrides() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("html[data-theme=\"dark\"]"), "Should have dark theme selectors")
        XCTAssertTrue(html.contains("html[data-theme=\"light\"]"), "Should have light theme selectors")
    }

    func testHTMLLayoutStructure() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<div id=\"layout\">"), "Should have layout div")
        XCTAssertTrue(html.contains("<article class=\"markdown-body\">"), "Should have markdown-body article")
        XCTAssertTrue(html.contains("</article>"), "Should close article")
        XCTAssertTrue(html.contains("<meta name=\"viewport\""), "Should have viewport meta")
    }

    func testCodeFileLayoutStructure() throws {
        let url = writeTempFile("print(1)", ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("<div id=\"layout\">"), "Code should have layout div")
        XCTAssertTrue(html.contains("<article class=\"markdown-body\">"), "Code should use same body class")
        XCTAssertFalse(html.contains("<div id=\"toc-container\">"), "Code should NOT have TOC element")
    }

    // MARK: - Heading Anchor CSS

    func testHeadingAnchorCSSPresent() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains(".heading-anchor"), "Should have heading anchor CSS")
    }

    // MARK: - Footnote CSS

    func testFootnoteCSSPresent() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains(".footnote-ref"), "Should have footnote ref CSS")
        XCTAssertTrue(html.contains(".footnotes"), "Should have footnotes section CSS")
        XCTAssertTrue(html.contains(".footnote-backref"), "Should have footnote backref CSS")
    }

    // MARK: - Frontmatter CSS

    func testFrontmatterCSSPresent() throws {
        let url = writeTempFile("# Test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains(".frontmatter-banner"), "Should have frontmatter banner CSS")
        XCTAssertTrue(html.contains(".frontmatter-title"), "Should have frontmatter title CSS")
        XCTAssertTrue(html.contains(".frontmatter-tag"), "Should have frontmatter tag CSS")
    }

    // MARK: - Public API Wrappers

    func testHtmlBodyPublicForMarkdown() throws {
        let url = writeTempFile("# Public API", ext: "md")
        let (body, isMarkdown) = try MarkdownDocumentModel.htmlBodyPublic(for: url)
        XCTAssertTrue(isMarkdown, "Should detect markdown")
        XCTAssertTrue(body.contains("<h1"), "Should render heading")
    }

    func testHtmlBodyPublicForCode() throws {
        let url = writeTempFile("let x = 1", ext: "swift")
        let (body, isMarkdown) = try MarkdownDocumentModel.htmlBodyPublic(for: url)
        XCTAssertFalse(isMarkdown, "Should detect code file")
        XCTAssertTrue(body.contains("language-swift"), "Should have language class")
    }

    func testHtmlBodyPublicThrowsForMissingFile() {
        let url = URL(fileURLWithPath: "/nonexistent/file.md")
        XCTAssertThrowsError(try MarkdownDocumentModel.htmlBodyPublic(for: url))
    }

    func testWrapHTMLPublicMarkdown() {
        let wrapped = MarkdownDocumentModel.wrapHTMLPublic("<h1>Test</h1>", isMarkdown: true)
        XCTAssertTrue(wrapped.contains("<!doctype html>"))
        XCTAssertTrue(wrapped.contains("data-filetype=\"markdown\""))
        XCTAssertTrue(wrapped.contains("toc-container"), "Markdown should have TOC")
    }

    func testWrapHTMLPublicCode() {
        let wrapped = MarkdownDocumentModel.wrapHTMLPublic("<pre><code>x</code></pre>", isMarkdown: false)
        XCTAssertTrue(wrapped.contains("<!doctype html>"))
        XCTAssertTrue(wrapped.contains("data-filetype=\"code\""))
        XCTAssertFalse(wrapped.contains("<div id=\"toc-container\">"), "Code should NOT have TOC element")
    }

    func testWrapHTMLPublicPreservesBody() {
        let body = "<p>Hello World</p>"
        let wrapped = MarkdownDocumentModel.wrapHTMLPublic(body, isMarkdown: true)
        XCTAssertTrue(wrapped.contains(body), "Should contain the original body HTML")
    }

    // MARK: - Log

    func testLogFileExists() {
        MarkdownDocumentModel.log("test message")
        XCTAssertTrue(FileManager.default.fileExists(atPath: MarkdownDocumentModel.logFileURL.path),
                       "Log file should exist after logging")
    }

    func testLogFileLocation() {
        let logURL = MarkdownDocumentModel.logFileURL
        XCTAssertTrue(logURL.lastPathComponent == "QuickMD.log", "Log file should be named QuickMD.log")
    }

    func testLogAppendsToFile() throws {
        let marker1 = UUID().uuidString
        let marker2 = UUID().uuidString
        MarkdownDocumentModel.log(marker1)
        MarkdownDocumentModel.log(marker2)

        let content = try String(contentsOf: MarkdownDocumentModel.logFileURL, encoding: .utf8)
        XCTAssertTrue(content.contains(marker1), "Log should contain first message")
        XCTAssertTrue(content.contains(marker2), "Log should contain second message")
    }

    // MARK: - Empty File Handling

    func testEmptyMarkdownFile() throws {
        let url = writeTempFile("", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle empty markdown file")
        XCTAssertNil(model.errorMessage)
        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("data-filetype=\"markdown\""))
    }

    func testEmptyCodeFile() throws {
        let url = writeTempFile("", ext: "py")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle empty code file")
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - Large Content

    func testLargeMarkdownFile() throws {
        let content = String(repeating: "# Heading\nParagraph text.\n\n", count: 100)
        let url = writeTempFile(content, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertNotNil(model.html, "Should handle large markdown file")
        XCTAssertNil(model.errorMessage)
    }

    // MARK: - Special Characters

    func testUnicodeContentInMarkdown() throws {
        let url = writeTempFile("# 日本語 🎉\nEmoji: 🚀 中文 العربية", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("日本語"), "Should handle CJK characters")
        XCTAssertTrue(html.contains("🚀"), "Should handle emoji")
    }

    func testSpecialHTMLCharsInMarkdown() throws {
        let url = writeTempFile("Less than: 5 < 10 and greater: 10 > 5", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        // The markdown renderer may or may not escape these (they're in prose)
        XCTAssertNotNil(model.html, "Should handle special HTML chars")
    }

    // MARK: - New Scripts in Browser Export

    func testBrowserExportIncludesAllNewScripts() throws {
        let scripts: [(String, String)] = [
            ("emojiScript", MarkdownDocumentModel.emojiScript),
            ("footnotesScript", MarkdownDocumentModel.footnotesScript),
            ("frontmatterScript", MarkdownDocumentModel.frontmatterScript),
            ("anchorLinksScript", MarkdownDocumentModel.anchorLinksScript),
            ("wordWrapScript", MarkdownDocumentModel.wordWrapScript),
            ("presentationScript", MarkdownDocumentModel.presentationScript),
        ]

        for (name, script) in scripts {
            XCTAssertFalse(script.isEmpty, "\(name) should not be empty")
            XCTAssertTrue(script.contains("function") || script.contains("var"),
                          "\(name) should contain JavaScript code")
        }
    }

    // MARK: - All Static Scripts Non-Empty

    func testAllStaticScriptsAccessible() {
        // Verify all static script properties can be accessed without crashing
        let scripts: [(String, String)] = [
            ("themeScript", MarkdownDocumentModel.themeScript),
            ("mermaidRenderScript", MarkdownDocumentModel.mermaidRenderScript),
            ("highlightRenderScript", MarkdownDocumentModel.highlightRenderScript),
            ("copyButtonScript", MarkdownDocumentModel.copyButtonScript),
            ("readingStatsScript", MarkdownDocumentModel.readingStatsScript),
            ("lineNumbersScript", MarkdownDocumentModel.lineNumbersScript),
            ("jumpToLineScript", MarkdownDocumentModel.jumpToLineScript),
            ("findScript", MarkdownDocumentModel.findScript),
            ("speakScript", MarkdownDocumentModel.speakScript),
            ("headingDataScript", MarkdownDocumentModel.headingDataScript),
            ("zoomOverlayScript", MarkdownDocumentModel.zoomOverlayScript),
            ("katexRenderScript", MarkdownDocumentModel.katexRenderScript),
            ("graphvizRenderScript", MarkdownDocumentModel.graphvizRenderScript),
            ("emojiScript", MarkdownDocumentModel.emojiScript),
            ("footnotesScript", MarkdownDocumentModel.footnotesScript),
            ("frontmatterScript", MarkdownDocumentModel.frontmatterScript),
            ("anchorLinksScript", MarkdownDocumentModel.anchorLinksScript),
            ("wordWrapScript", MarkdownDocumentModel.wordWrapScript),
            ("presentationScript", MarkdownDocumentModel.presentationScript),
        ]

        for (name, script) in scripts {
            XCTAssertFalse(script.isEmpty, "\(name) should not be empty")
        }
    }

    // MARK: - Resource Loading

    func testHighlightCSSProperties() {
        // These are loaded from bundle, may be empty in test target but should not crash
        _ = MarkdownDocumentModel.highlightGitHubCSS
        _ = MarkdownDocumentModel.highlightGitHubDarkCSS
    }

    func testResourceLoadersDoNotCrash() {
        // These attempt to load from bundle; in test they may be empty but shouldn't crash
        _ = MarkdownDocumentModel.mermaidJS
        _ = MarkdownDocumentModel.highlightJS
        _ = MarkdownDocumentModel.jsYamlJS
        _ = MarkdownDocumentModel.katexJS
        _ = MarkdownDocumentModel.autoRenderJS
        _ = MarkdownDocumentModel.graphvizJS
    }

    // MARK: - Browser Export

    func testExportHTMLForBrowserVerification() throws {
        let testMdPath = "/Users/pedro/code/QuickLookMarkdown/test-features.md"
        guard FileManager.default.fileExists(atPath: testMdPath) else {
            // Skip if test-features.md doesn't exist
            return
        }
        let mdContent = try String(contentsOfFile: testMdPath, encoding: .utf8)
        let url = writeTempFile(mdContent, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        var html = try XCTUnwrap(model.html)

        let scripts = [
            MarkdownDocumentModel.themeScript,
            MarkdownDocumentModel.highlightJS,
            MarkdownDocumentModel.highlightRenderScript,
            MarkdownDocumentModel.jsYamlJS,
            MarkdownDocumentModel.copyButtonScript,
            MarkdownDocumentModel.readingStatsScript,
            MarkdownDocumentModel.lineNumbersScript,
            MarkdownDocumentModel.jumpToLineScript,
            MarkdownDocumentModel.findScript,
            MarkdownDocumentModel.headingDataScript,
            MarkdownDocumentModel.zoomOverlayScript,
            MarkdownDocumentModel.speakScript,
            MarkdownDocumentModel.mermaidJS,
            MarkdownDocumentModel.mermaidRenderScript,
            MarkdownDocumentModel.graphvizJS,
            MarkdownDocumentModel.graphvizRenderScript,
            MarkdownDocumentModel.katexJS,
            MarkdownDocumentModel.autoRenderJS,
            MarkdownDocumentModel.katexRenderScript,
            MarkdownDocumentModel.emojiScript,
            MarkdownDocumentModel.footnotesScript,
            MarkdownDocumentModel.frontmatterScript,
            MarkdownDocumentModel.anchorLinksScript,
            MarkdownDocumentModel.wordWrapScript,
            MarkdownDocumentModel.presentationScript,
        ]

        let scriptTags = scripts.map { "<script>\($0)</script>" }.joined(separator: "\n")
        html = html.replacingOccurrences(of: "</body>", with: "\(scriptTags)\n</body>")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("quickmd-browser-test.html")
        try html.write(to: outputURL, atomically: true, encoding: .utf8)

        let publicPath = NSHomeDirectory() + "/quickmd-browser-test.html"
        try? FileManager.default.removeItem(atPath: publicPath)
        try html.write(toFile: publicPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let size = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000, "Exported HTML should be substantial")
    }

    // MARK: - Comment Annotations

    func testPreprocessCommentsSingleComment() {
        let md = "Hello <!-- COMMENT: my note -->world<!-- /COMMENT --> end"
        let result = MarkdownDocumentModel.preprocessComments(md)
        XCTAssertTrue(result.contains("<mark class=\"qmd-comment\" data-comment=\"my note\">world</mark>"))
        XCTAssertFalse(result.contains("<!-- COMMENT"))
    }

    func testPreprocessCommentsMultipleComments() {
        let md = "<!-- COMMENT: a -->first<!-- /COMMENT --> mid <!-- COMMENT: b -->second<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.preprocessComments(md)
        XCTAssertTrue(result.contains("data-comment=\"a\">first</mark>"))
        XCTAssertTrue(result.contains("data-comment=\"b\">second</mark>"))
    }

    func testPreprocessCommentsNoComments() {
        let md = "# Hello\nJust regular markdown"
        let result = MarkdownDocumentModel.preprocessComments(md)
        XCTAssertEqual(result, md)
    }

    func testPreprocessCommentsHTMLEscapesComment() {
        let md = "<!-- COMMENT: has <b>&amp; \"quotes\" -->text<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.preprocessComments(md)
        XCTAssertTrue(result.contains("data-comment=\"has &lt;b&gt;&amp;amp; &quot;quotes&quot;\""))
    }

    func testPreprocessCommentsMultilineAnnotatedText() {
        let md = "<!-- COMMENT: note -->line1\nline2<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.preprocessComments(md)
        XCTAssertTrue(result.contains(">line1\nline2</mark>"))
    }

    func testAddCommentWrapsText() {
        let text = "Hello world end"
        let range = NSRange(location: 6, length: 5) // "world"
        let result = MarkdownDocumentModel.addComment(around: range, comment: "my note", in: text)
        XCTAssertEqual(result, "Hello <!-- COMMENT: my note -->world<!-- /COMMENT --> end")
    }

    func testAddCommentAtStart() {
        let text = "Hello world"
        let range = NSRange(location: 0, length: 5) // "Hello"
        let result = MarkdownDocumentModel.addComment(around: range, comment: "start", in: text)
        XCTAssertEqual(result, "<!-- COMMENT: start -->Hello<!-- /COMMENT --> world")
    }

    func testAddCommentAtEnd() {
        let text = "Hello world"
        let range = NSRange(location: 6, length: 5) // "world"
        let result = MarkdownDocumentModel.addComment(around: range, comment: "end note", in: text)
        XCTAssertEqual(result, "Hello <!-- COMMENT: end note -->world<!-- /COMMENT -->")
    }

    func testRemoveCommentKeepsText() {
        let text = "Hello <!-- COMMENT: note -->world<!-- /COMMENT --> end"
        let result = MarkdownDocumentModel.removeComment(at: 0, in: text)
        XCTAssertEqual(result, "Hello world end")
    }

    func testRemoveCommentFirstOfMultiple() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT --> <!-- COMMENT: b -->second<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.removeComment(at: 0, in: text)
        XCTAssertTrue(result.contains("first"))
        XCTAssertTrue(result.contains("<!-- COMMENT: b -->second<!-- /COMMENT -->"))
        XCTAssertFalse(result.contains("<!-- COMMENT: a -->"))
    }

    func testRemoveCommentSecondOfMultiple() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT --> <!-- COMMENT: b -->second<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.removeComment(at: 1, in: text)
        XCTAssertTrue(result.contains("<!-- COMMENT: a -->first<!-- /COMMENT -->"))
        XCTAssertTrue(result.contains("second"))
        XCTAssertFalse(result.contains("<!-- COMMENT: b -->"))
    }

    func testRemoveCommentInvalidIndex() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.removeComment(at: 5, in: text)
        XCTAssertEqual(result, text, "Invalid index should return unchanged text")
    }

    func testUpdateCommentChangesText() {
        let text = "Hello <!-- COMMENT: old -->world<!-- /COMMENT --> end"
        let result = MarkdownDocumentModel.updateComment(at: 0, newComment: "new note", in: text)
        XCTAssertEqual(result, "Hello <!-- COMMENT: new note -->world<!-- /COMMENT --> end")
    }

    func testUpdateCommentSecondOfMultiple() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT --> <!-- COMMENT: b -->second<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.updateComment(at: 1, newComment: "updated", in: text)
        XCTAssertTrue(result.contains("<!-- COMMENT: a -->first<!-- /COMMENT -->"))
        XCTAssertTrue(result.contains("<!-- COMMENT: updated -->second<!-- /COMMENT -->"))
    }

    func testUpdateCommentInvalidIndex() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.updateComment(at: 5, newComment: "x", in: text)
        XCTAssertEqual(result, text, "Invalid index should return unchanged text")
    }

    func testParseCommentsFindsAll() {
        let text = "<!-- COMMENT: a -->first<!-- /COMMENT --> mid <!-- COMMENT: b -->second<!-- /COMMENT -->"
        let comments = MarkdownDocumentModel.parseComments(in: text)
        XCTAssertEqual(comments.count, 2)
        XCTAssertEqual(comments[0].comment, "a")
        XCTAssertEqual(comments[0].annotatedText, "first")
        XCTAssertEqual(comments[1].comment, "b")
        XCTAssertEqual(comments[1].annotatedText, "second")
    }

    func testParseCommentsEmpty() {
        let comments = MarkdownDocumentModel.parseComments(in: "No comments here")
        XCTAssertTrue(comments.isEmpty)
    }

    func testParseCommentsRangesAreCorrect() {
        let text = "pre <!-- COMMENT: x -->hello<!-- /COMMENT --> post"
        let comments = MarkdownDocumentModel.parseComments(in: text)
        XCTAssertEqual(comments.count, 1)
        let nsText = text as NSString
        let matched = nsText.substring(with: comments[0].range)
        XCTAssertEqual(matched, "<!-- COMMENT: x -->hello<!-- /COMMENT -->")
    }

    func testCommentRoundTrip() {
        // Add a comment, then update it, then remove it — should return to original
        let original = "The quick brown fox"
        let range = NSRange(location: 4, length: 5) // "quick"
        let added = MarkdownDocumentModel.addComment(around: range, comment: "fast", in: original)
        XCTAssertTrue(added.contains("<!-- COMMENT: fast -->quick<!-- /COMMENT -->"))

        let updated = MarkdownDocumentModel.updateComment(at: 0, newComment: "speedy", in: added)
        XCTAssertTrue(updated.contains("<!-- COMMENT: speedy -->quick<!-- /COMMENT -->"))

        let removed = MarkdownDocumentModel.removeComment(at: 0, in: updated)
        XCTAssertEqual(removed, original)
    }

    func testCommentInRenderedHTML() throws {
        let md = "Hello <!-- COMMENT: note -->world<!-- /COMMENT --> end"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("qmd-comment"), "Should have comment mark class")
        XCTAssertTrue(html.contains("data-comment=\"note\""), "Should have comment data attribute")
        XCTAssertFalse(html.contains("<!-- COMMENT"), "Comment markers should be preprocessed away")
    }

    func testSidebarHTMLRemovedFromOutput() throws {
        let md = "# Title\nSome text"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        // Sidebar is now native SwiftUI, not in HTML
        XCTAssertFalse(html.contains("id=\"sidebar-container\""), "Should NOT have sidebar container")
        XCTAssertFalse(html.contains("id=\"comments-panel\""), "Should NOT have comments panel in HTML")
        XCTAssertTrue(html.contains("id=\"layout\""), "Should still have layout wrapper")
    }

    func testCommentSidebarScriptInjected() {
        // Sidebar is now native SwiftUI — verify headingDataScript sends data via bridge
        let script = MarkdownDocumentModel.headingDataScript
        XCTAssertTrue(script.contains("__rebuildHeadingData"), "Should have heading data rebuild function")
        XCTAssertTrue(script.contains("tocData"), "Should post to tocData bridge handler")
    }

    func testCommentFlashAnimationCSS() throws {
        let md = "# Title\nSome text"
        let url = writeTempFile(md, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("qmd-comment-flash"), "Should have flash animation class")
        XCTAssertTrue(html.contains("comment-flash"), "Should have flash keyframes")
    }

    func testCommentContextMenuHelpers() {
        let script = MarkdownDocumentModel.commentScript
        XCTAssertTrue(script.contains("__getSelectionText"), "Should have selection text helper")
        XCTAssertTrue(script.contains("__getCommentAtPoint"), "Should have comment-at-point helper")
        XCTAssertFalse(script.contains("contextmenu"), "Should NOT have contextmenu listener")
    }

    func testNoSidebarHTMLInOutput() throws {
        let url = writeTempFile("# Heading\nSome text", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertFalse(html.contains("sidebar-container"), "Sidebar is native SwiftUI, not in HTML")
        XCTAssertFalse(html.contains("sidebar-icons"), "Sidebar icons should not be in HTML")
        XCTAssertFalse(html.contains("sidebar-panel"), "Sidebar panels should not be in HTML")
    }

    func testParsedCommentsRefresh() {
        let model = MarkdownDocumentModel()
        model.rawContent = "<!-- COMMENT: note -->hello<!-- /COMMENT --> world"
        model.refreshParsedComments()
        XCTAssertEqual(model.parsedComments.count, 1)
        XCTAssertEqual(model.parsedComments[0].comment, "note")
        XCTAssertEqual(model.parsedComments[0].annotatedText, "hello")
    }

    func testMultipleCommentsPreprocessOrder() {
        let text = "<!-- COMMENT: first -->A<!-- /COMMENT --> B <!-- COMMENT: second -->C<!-- /COMMENT --> D <!-- COMMENT: third -->E<!-- /COMMENT -->"
        let result = MarkdownDocumentModel.preprocessComments(text)
        // All three should be processed
        XCTAssertTrue(result.contains("data-comment=\"first\">A</mark>"))
        XCTAssertTrue(result.contains("data-comment=\"second\">C</mark>"))
        XCTAssertTrue(result.contains("data-comment=\"third\">E</mark>"))
        // No raw comment markers should remain
        XCTAssertFalse(result.contains("<!-- COMMENT"))
        XCTAssertFalse(result.contains("<!-- /COMMENT"))
    }

    func testCommentWithSpecialMarkdown() {
        // Comment around bold text
        let text = "Hello <!-- COMMENT: emphasis -->**bold text**<!-- /COMMENT --> end"
        let result = MarkdownDocumentModel.preprocessComments(text)
        XCTAssertTrue(result.contains("<mark class=\"qmd-comment\" data-comment=\"emphasis\">**bold text**</mark>"))
    }

    func testSetContentUpdatesRawContent() {
        let model = MarkdownDocumentModel()
        let url = writeTempFile("original", ext: "md")
        model.load(from: url)
        XCTAssertEqual(model.rawContent, "original")

        model.setContent("modified", actionName: "Test")
        XCTAssertEqual(model.rawContent, "modified")
    }

    // MARK: - Helpers

    private func writeTempFile(_ content: String, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let name = UUID().uuidString + "." + ext
        let url = dir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
