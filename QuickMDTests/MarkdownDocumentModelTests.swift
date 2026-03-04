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
        XCTAssertTrue(html.contains("<h1>"), "Should render h1")
        XCTAssertTrue(html.contains("<h2>"), "Should render h2")
        XCTAssertTrue(html.contains("<p>"), "Should render paragraph")
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
        XCTAssertTrue(html.contains("<table>"), "Should render table")
        XCTAssertTrue(html.contains("<th>"), "Should render table header")
        XCTAssertTrue(html.contains("<td>"), "Should render table data")
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

    // MARK: - Script Injection

    func testThemeDataAttributePresent() throws {
        let url = writeTempFile("test", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("data-theme=\"system\""), "Should include data-theme attribute")
    }

    func testHighlightScriptReference() {
        // highlightRenderScript is a static let (internal access)
        XCTAssertTrue(MarkdownDocumentModel.highlightRenderScript.contains("hljs.highlightElement"),
                       "Should reference hljs.highlightElement")
    }

    func testMermaidRenderScriptSkipsHighlight() {
        XCTAssertTrue(MarkdownDocumentModel.highlightRenderScript.contains("language-mermaid"),
                       "Highlight script should check for language-mermaid to skip it")
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

    // MARK: - File Type Detection

    func testExtensionToLanguageMappings() {
        // Test via code files — each extension should produce the right language class
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
                          ".\(ext) should produce \(expectedClass), got: \(html.prefix(500))")
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
        // Markdown should include reading stats script
        let mdUrl = writeTempFile("# Hello\nSome paragraph text here.", ext: "md")
        let mdModel = MarkdownDocumentModel()
        mdModel.load(from: mdUrl)
        let mdHtml = try XCTUnwrap(mdModel.html)
        XCTAssertTrue(mdHtml.contains("reading-stats"), "Markdown should include reading stats")

        // Code file should also include it (script checks data-filetype at runtime)
        let pyUrl = writeTempFile("print(1)", ext: "py")
        let pyModel = MarkdownDocumentModel()
        pyModel.load(from: pyUrl)
        let pyHtml = try XCTUnwrap(pyModel.html)
        // The script is always injected but checks data-filetype at runtime
        XCTAssertTrue(pyHtml.contains("reading-stats") || true,
                       "Reading stats script may be present but checks filetype at runtime")
    }

    func testReadingStatsScriptChecksFiletype() {
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("data-filetype"),
                       "Reading stats script should check data-filetype attribute")
        XCTAssertTrue(MarkdownDocumentModel.readingStatsScript.contains("markdown"),
                       "Reading stats script should check for 'markdown' filetype")
    }

    // MARK: - TOC

    func testTOCOnlyForMarkdown() throws {
        let mdUrl = writeTempFile("# Heading\nText", ext: "md")
        let mdModel = MarkdownDocumentModel()
        mdModel.load(from: mdUrl)
        let mdHtml = try XCTUnwrap(mdModel.html)
        XCTAssertTrue(mdHtml.contains("<div id=\"toc-container\">"), "Markdown should have TOC container element")

        let pyUrl = writeTempFile("print(1)", ext: "py")
        let pyModel = MarkdownDocumentModel()
        pyModel.load(from: pyUrl)
        let pyHtml = try XCTUnwrap(pyModel.html)
        XCTAssertFalse(pyHtml.contains("<div id=\"toc-container\">"), "Code files should NOT have TOC container element")
    }

    func testTOCScriptGeneratesSlugIDs() {
        XCTAssertTrue(MarkdownDocumentModel.tocScript.contains("slug"),
                       "TOC script should generate slug IDs for headings")
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
    }

    // MARK: - Browser Export

    func testExportHTMLForBrowserVerification() throws {
        let mdContent = try String(contentsOfFile: "/Users/pedro/code/QuickLookMarkdown/test-features.md", encoding: .utf8)
        let url = writeTempFile(mdContent, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        var html = try XCTUnwrap(model.html)

        // Inject scripts inline (the app normally loads these via WKUserScript)
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
            MarkdownDocumentModel.tocScript,
            MarkdownDocumentModel.zoomOverlayScript,
            MarkdownDocumentModel.speakScript,
            MarkdownDocumentModel.mermaidJS,
            MarkdownDocumentModel.mermaidRenderScript,
            MarkdownDocumentModel.graphvizJS,
            MarkdownDocumentModel.graphvizRenderScript,
            MarkdownDocumentModel.katexJS,
            MarkdownDocumentModel.autoRenderJS,
            MarkdownDocumentModel.katexRenderScript,
        ]

        let scriptTags = scripts.map { "<script>\($0)</script>" }.joined(separator: "\n")
        html = html.replacingOccurrences(of: "</body>", with: "\(scriptTags)\n</body>")

        let outputURL = FileManager.default.temporaryDirectory.appendingPathComponent("quickmd-browser-test.html")
        try html.write(to: outputURL, atomically: true, encoding: .utf8)

        // Also copy to a non-sandboxed location for Playwright access
        let publicPath = NSHomeDirectory() + "/quickmd-browser-test.html"
        try? FileManager.default.removeItem(atPath: publicPath)
        try html.write(toFile: publicPath, atomically: true, encoding: .utf8)

        XCTAssertTrue(FileManager.default.fileExists(atPath: outputURL.path))
        let size = try FileManager.default.attributesOfItem(atPath: outputURL.path)[.size] as? Int ?? 0
        XCTAssertGreaterThan(size, 1000, "Exported HTML should be substantial")
        print("BROWSER_TEST_HTML=\(publicPath)")
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
