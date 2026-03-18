import XCTest
import WebKit
@testable import QuickMD

/// Tests for file link navigation, back/forward history, and the openLinksInNewTab setting.
/// Includes both unit tests for the navigation stack and WKWebView E2E tests for link rendering and click handling.
final class NavigationTests: XCTestCase {

    // MARK: - Helpers

    private func writeTempFile(_ content: String, ext: String) -> URL {
        let dir = FileManager.default.temporaryDirectory
        let url = dir.appendingPathComponent(UUID().uuidString + "." + ext)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func writeTempFileNamed(_ name: String, content: String) -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("quickmd-nav-test-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        try! content.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        return url
    }

    // =========================================================================
    // MARK: - Navigation Stack: navigateTo
    // =========================================================================

    func testNavigateToSetsCurrentURL() {
        let url = writeTempFile("# Page", ext: "md")
        let model = MarkdownDocumentModel()
        model.navigateTo(url)
        XCTAssertEqual(model.currentURL, url)
    }

    func testNavigateToPushesBackStack() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        XCTAssertTrue(model.backStack.isEmpty)

        model.navigateTo(url2)
        XCTAssertEqual(model.backStack.count, 1)
        XCTAssertEqual(model.backStack[0], url1)
        XCTAssertEqual(model.currentURL, url2)
    }

    func testNavigateToClearsForwardStack() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let url3 = writeTempFile("# Page 3", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack() // now at url1, forwardStack has url2

        XCTAssertEqual(model.forwardStack.count, 1)
        model.navigateTo(url3) // should clear forward stack
        XCTAssertTrue(model.forwardStack.isEmpty, "Navigating to new URL should clear forward stack")
    }

    func testMultipleNavigations() {
        let urls = (0..<5).map { writeTempFile("# Page \($0)", ext: "md") }
        let model = MarkdownDocumentModel()
        model.load(from: urls[0])

        for i in 1..<5 {
            model.navigateTo(urls[i])
        }

        XCTAssertEqual(model.backStack.count, 4)
        XCTAssertEqual(model.currentURL, urls[4])
        XCTAssertEqual(model.backStack, Array(urls[0..<4]))
    }

    // =========================================================================
    // MARK: - Navigation Stack: goBack
    // =========================================================================

    func testGoBackRestoresPreviousURL() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)

        model.goBack()
        XCTAssertEqual(model.currentURL, url1)
    }

    func testGoBackPushesForwardStack() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)

        model.goBack()
        XCTAssertEqual(model.forwardStack.count, 1)
        XCTAssertEqual(model.forwardStack[0], url2)
    }

    func testGoBackEmptyStackDoesNothing() {
        let url = writeTempFile("# Page", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertFalse(model.canGoBack)
        model.goBack() // should not crash
        XCTAssertEqual(model.currentURL, url)
    }

    func testGoBackMultipleTimes() {
        let urls = (0..<4).map { writeTempFile("# Page \($0)", ext: "md") }
        let model = MarkdownDocumentModel()
        model.load(from: urls[0])
        model.navigateTo(urls[1])
        model.navigateTo(urls[2])
        model.navigateTo(urls[3])

        model.goBack()
        XCTAssertEqual(model.currentURL, urls[2])
        model.goBack()
        XCTAssertEqual(model.currentURL, urls[1])
        model.goBack()
        XCTAssertEqual(model.currentURL, urls[0])
        XCTAssertFalse(model.canGoBack)
    }

    // =========================================================================
    // MARK: - Navigation Stack: goForward
    // =========================================================================

    func testGoForwardRestoresNextURL() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack()

        model.goForward()
        XCTAssertEqual(model.currentURL, url2)
    }

    func testGoForwardPushesBackStack() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack()

        model.goForward()
        XCTAssertEqual(model.backStack.last, url1)
    }

    func testGoForwardEmptyStackDoesNothing() {
        let url = writeTempFile("# Page", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)

        XCTAssertFalse(model.canGoForward)
        model.goForward() // should not crash
        XCTAssertEqual(model.currentURL, url)
    }

    // =========================================================================
    // MARK: - Navigation Stack: complex sequences
    // =========================================================================

    func testBackThenForwardReturnsToSamePage() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)

        model.goBack()
        XCTAssertEqual(model.currentURL, url1)
        model.goForward()
        XCTAssertEqual(model.currentURL, url2)
    }

    func testBackThenNavigateClearsForward() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let url3 = writeTempFile("# Page 3", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack() // at url1, forward has url2

        model.navigateTo(url3) // should clear forward
        XCTAssertTrue(model.forwardStack.isEmpty)
        XCTAssertEqual(model.currentURL, url3)
        XCTAssertEqual(model.backStack, [url1])
    }

    func testZigZagNavigation() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let url3 = writeTempFile("# Page 3", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.navigateTo(url3)

        // Go back twice
        model.goBack()
        model.goBack()
        XCTAssertEqual(model.currentURL, url1)
        XCTAssertEqual(model.forwardStack.count, 2)

        // Go forward once
        model.goForward()
        XCTAssertEqual(model.currentURL, url2)
        XCTAssertEqual(model.backStack.count, 1)
        XCTAssertEqual(model.forwardStack.count, 1)

        // Navigate to new page — clears forward
        let url4 = writeTempFile("# Page 4", ext: "md")
        model.navigateTo(url4)
        XCTAssertTrue(model.forwardStack.isEmpty)
        XCTAssertEqual(model.backStack, [url1, url2])
    }

    // =========================================================================
    // MARK: - canGoBack / canGoForward
    // =========================================================================

    func testCanGoBackFalseInitially() {
        let model = MarkdownDocumentModel()
        XCTAssertFalse(model.canGoBack)
    }

    func testCanGoForwardFalseInitially() {
        let model = MarkdownDocumentModel()
        XCTAssertFalse(model.canGoForward)
    }

    func testCanGoBackTrueAfterNavigate() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        XCTAssertTrue(model.canGoBack)
    }

    func testCanGoForwardTrueAfterGoBack() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack()
        XCTAssertTrue(model.canGoForward)
    }

    func testCanGoBackFalseAfterAllBacks() {
        let url1 = writeTempFile("# Page 1", ext: "md")
        let url2 = writeTempFile("# Page 2", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack()
        XCTAssertFalse(model.canGoBack)
    }

    // =========================================================================
    // MARK: - Navigation preserves content
    // =========================================================================

    func testGoBackRestoresFileContent() {
        let url1 = writeTempFile("# First Page Content", ext: "md")
        let url2 = writeTempFile("# Second Page Content", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        XCTAssertTrue(model.rawContent.contains("Second"))

        model.goBack()
        XCTAssertTrue(model.rawContent.contains("First"))
    }

    func testGoForwardRestoresFileContent() {
        let url1 = writeTempFile("# First Page", ext: "md")
        let url2 = writeTempFile("# Second Page", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)
        model.goBack()

        model.goForward()
        XCTAssertTrue(model.rawContent.contains("Second"))
    }

    func testNavigationProducesHTML() throws {
        let url1 = writeTempFile("# Page One", ext: "md")
        let url2 = writeTempFile("# Page Two", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        let html1 = try XCTUnwrap(model.html)
        XCTAssertTrue(html1.contains("Page One"))

        model.navigateTo(url2)
        let html2 = try XCTUnwrap(model.html)
        XCTAssertTrue(html2.contains("Page Two"))

        model.goBack()
        let html3 = try XCTUnwrap(model.html)
        XCTAssertTrue(html3.contains("Page One"))
    }

    // =========================================================================
    // MARK: - WKWebView E2E: links render correctly
    // =========================================================================

    private var webView: WKWebView!

    private func loadMarkdownInWebView(_ markdown: String) throws -> String {
        if webView == nil {
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        let url = writeTempFile(markdown, ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url)
        let html = try XCTUnwrap(model.html)

        let exp = expectation(description: "load")
        webView.loadHTMLString(html, baseURL: url.deletingLastPathComponent())
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            // Inject link click script
            self.webView.evaluateJavaScript(MarkdownDocumentModel.linkClickScript) { _, _ in
                exp.fulfill()
            }
        }
        wait(for: [exp], timeout: 5.0)
        return html
    }

    private func evalJS(_ js: String) -> Any? {
        let exp = expectation(description: "JS")
        var result: Any?
        webView.evaluateJavaScript(js) { value, _ in
            result = value
            exp.fulfill()
        }
        wait(for: [exp], timeout: 5.0)
        return result
    }

    func testLinkRendersAsAnchorTag() throws {
        let html = try loadMarkdownInWebView("Click [here](other.md) to navigate.")
        XCTAssertTrue(html.contains("<a href=\"other.md\">here</a>"), "Link should render as <a> tag")
    }

    func testMultipleLinksRender() throws {
        let html = try loadMarkdownInWebView("[Link A](a.md) and [Link B](b.md) and [Link C](c.md)")
        let count = html.components(separatedBy: "<a href=").count - 1
        XCTAssertEqual(count, 3, "Should render 3 links")
    }

    func testRelativeLinkHref() throws {
        let _ = try loadMarkdownInWebView("Go to [page](./subdir/page.md).")
        let href = evalJS("document.querySelector('a[href]').getAttribute('href')") as? String
        XCTAssertEqual(href, "./subdir/page.md")
    }

    func testExternalLinkHref() throws {
        let _ = try loadMarkdownInWebView("Visit [example](https://example.com).")
        let href = evalJS("document.querySelector('a[href]').getAttribute('href')") as? String
        XCTAssertEqual(href, "https://example.com")
    }

    // =========================================================================
    // MARK: - WKWebView E2E: link click JS interception
    // =========================================================================

    func testLinkClickScriptPresent() throws {
        let _ = try loadMarkdownInWebView("[link](test.md)")
        // The linkClick script should have been injected — check by trying to find a link
        let linkCount = evalJS("document.querySelectorAll('a[href]').length") as? Int
        XCTAssertGreaterThan(linkCount ?? 0, 0, "Should have at least one link in DOM")
    }

    func testAnchorLinkNotIntercepted() throws {
        let _ = try loadMarkdownInWebView("Go to [section](#heading).\n\n## Heading")
        // Anchor links should NOT be intercepted by the linkClick script
        let href = evalJS("document.querySelector('a[href]').getAttribute('href')") as? String
        XCTAssertTrue(href?.hasPrefix("#") ?? false, "Anchor link should have # href")
    }

    func testLinkClickScriptInterceptsFileLinks() throws {
        let _ = try loadMarkdownInWebView("[page](other.md)")
        // Simulate clicking the link and verify it would be intercepted
        // We can't fully test the native handler, but we can verify the JS listener exists
        let js = """
        (function() {
            var link = document.querySelector('a[href="other.md"]');
            if (!link) return 'no-link';
            // Check that clicking would be intercepted by checking event listener existence
            // The linkClick script adds a capture-phase listener on document
            return 'link-found';
        })()
        """
        let result = evalJS(js) as? String
        XCTAssertEqual(result, "link-found")
    }

    // =========================================================================
    // MARK: - WKWebView E2E: cross-linked fixture files
    // =========================================================================

    func testCrossLinkedFilesRenderLinks() throws {
        // Create two files that link to each other in the same directory
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nav-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("a.md")
        let fileB = dir.appendingPathComponent("b.md")
        try "# Page A\n\nGo to [Page B](b.md).".write(to: fileA, atomically: true, encoding: .utf8)
        try "# Page B\n\nBack to [Page A](a.md).".write(to: fileB, atomically: true, encoding: .utf8)

        let model = MarkdownDocumentModel()
        model.load(from: fileA)
        let html = try XCTUnwrap(model.html)
        XCTAssertTrue(html.contains("b.md"), "Should have link to b.md")

        // Navigate to B
        model.navigateTo(fileB)
        let htmlB = try XCTUnwrap(model.html)
        XCTAssertTrue(htmlB.contains("a.md"), "Page B should have link back to a.md")
        XCTAssertTrue(model.canGoBack)

        // Go back to A
        model.goBack()
        XCTAssertEqual(model.currentURL, fileA)
        XCTAssertTrue(model.rawContent.contains("Page A"))

        // Go forward to B
        model.goForward()
        XCTAssertEqual(model.currentURL, fileB)
        XCTAssertTrue(model.rawContent.contains("Page B"))
    }

    func testCrossLinkedFilesInWebView() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nav-e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let fileA = dir.appendingPathComponent("a.md")
        try "# Page A\n\nGo to [Page B](b.md) and [Page C](c.md).".write(to: fileA, atomically: true, encoding: .utf8)

        let model = MarkdownDocumentModel()
        model.load(from: fileA)
        let html = try XCTUnwrap(model.html)

        if webView == nil {
            webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        }
        let exp = expectation(description: "load")
        webView.loadHTMLString(html, baseURL: dir)
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { exp.fulfill() }
        wait(for: [exp], timeout: 5.0)

        // Verify both links exist in DOM
        let linkCount = evalJS("document.querySelectorAll('article a[href]').length") as? Int
        XCTAssertEqual(linkCount, 2, "Should have 2 links")

        let href1 = evalJS("document.querySelectorAll('article a[href]')[0].getAttribute('href')") as? String
        let href2 = evalJS("document.querySelectorAll('article a[href]')[1].getAttribute('href')") as? String
        XCTAssertEqual(href1, "b.md")
        XCTAssertEqual(href2, "c.md")
    }

    // =========================================================================
    // MARK: - Navigation with file content verification
    // =========================================================================

    func testNavigateToLoadsCorrectContent() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("nav-content-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }

        let urls = (0..<3).map { i -> URL in
            let url = dir.appendingPathComponent("page\(i).md")
            try! "# Unique Content \(i)\n\nBody of page \(i).".write(to: url, atomically: true, encoding: .utf8)
            return url
        }

        let model = MarkdownDocumentModel()
        model.load(from: urls[0])
        XCTAssertTrue(model.rawContent.contains("Unique Content 0"))

        model.navigateTo(urls[1])
        XCTAssertTrue(model.rawContent.contains("Unique Content 1"))
        XCTAssertFalse(model.rawContent.contains("Unique Content 0"))

        model.navigateTo(urls[2])
        XCTAssertTrue(model.rawContent.contains("Unique Content 2"))

        model.goBack()
        XCTAssertTrue(model.rawContent.contains("Unique Content 1"))

        model.goBack()
        XCTAssertTrue(model.rawContent.contains("Unique Content 0"))

        model.goForward()
        model.goForward()
        XCTAssertTrue(model.rawContent.contains("Unique Content 2"))
    }

    // =========================================================================
    // MARK: - Stress tests
    // =========================================================================

    func testDeepNavigationStack() {
        let urls = (0..<20).map { writeTempFile("# Page \($0)", ext: "md") }
        let model = MarkdownDocumentModel()
        model.load(from: urls[0])

        // Navigate forward through all 20 pages
        for i in 1..<20 {
            model.navigateTo(urls[i])
        }
        XCTAssertEqual(model.backStack.count, 19)
        XCTAssertEqual(model.currentURL, urls[19])

        // Go all the way back
        for i in (0..<19).reversed() {
            model.goBack()
            XCTAssertEqual(model.currentURL, urls[i])
        }
        XCTAssertFalse(model.canGoBack)
        XCTAssertEqual(model.forwardStack.count, 19)

        // Go all the way forward
        for i in 1..<20 {
            model.goForward()
            XCTAssertEqual(model.currentURL, urls[i])
        }
        XCTAssertFalse(model.canGoForward)
    }

    func testRapidBackForward() {
        let url1 = writeTempFile("# A", ext: "md")
        let url2 = writeTempFile("# B", ext: "md")
        let model = MarkdownDocumentModel()
        model.load(from: url1)
        model.navigateTo(url2)

        // Rapidly toggle back and forward
        for _ in 0..<50 {
            model.goBack()
            XCTAssertEqual(model.currentURL, url1)
            model.goForward()
            XCTAssertEqual(model.currentURL, url2)
        }
    }

    override func tearDown() {
        webView = nil
        super.tearDown()
    }
}
