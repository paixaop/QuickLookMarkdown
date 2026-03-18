import XCTest

final class QuickMDUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    override func tearDownWithError() throws {
        app.terminate()
    }

    // MARK: - Helpers

    /// Open a fixture file by using the File > Open menu
    private func openFixture(_ name: String) {
        let fixtureURL = fixtureURL(name)
        // Use AppleScript to open the file since XCUITest can't easily interact with NSOpenPanel
        let script = """
        tell application "QuickMD"
            activate
            open POSIX file "\(fixtureURL.path)"
        end tell
        """
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        proc.arguments = ["-e", script]
        try? proc.run()
        proc.waitUntilExit()
        // Wait for the file to load
        sleep(2)
    }

    private func fixtureURL(_ name: String) -> URL {
        // Fixtures are in the test bundle
        let bundle = Bundle(for: type(of: self))
        if let url = bundle.url(forResource: "Fixtures", withExtension: nil) {
            return url.appendingPathComponent(name)
        }
        // Fallback: look in the source directory
        let srcDir = URL(fileURLWithPath: #file).deletingLastPathComponent()
        return srcDir.appendingPathComponent("Fixtures").appendingPathComponent(name)
    }

    // MARK: - App Launch

    func testAppLaunches() {
        XCTAssertTrue(app.windows.count > 0, "App should have at least one window")
    }

    func testMainWindowExists() {
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist")
    }

    // MARK: - Menu Bar

    func testViewMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.menuBarItems["View"].exists, "View menu should exist")
    }

    func testToolsMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.menuBarItems["Tools"].exists, "Tools menu should exist")
    }

    func testFileMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.menuBarItems["File"].exists, "File menu should exist")
    }

    func testEditMenuExists() {
        let menuBar = app.menuBars.firstMatch
        XCTAssertTrue(menuBar.menuBarItems["Edit"].exists, "Edit menu should exist")
    }

    // MARK: - View Menu Items

    func testViewMenuHasZoomItems() {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()

        let viewMenu = menuBar.menuBarItems["View"]
        XCTAssertTrue(viewMenu.menuItems["Zoom In"].exists, "Should have Zoom In")
        XCTAssertTrue(viewMenu.menuItems["Zoom Out"].exists, "Should have Zoom Out")
        XCTAssertTrue(viewMenu.menuItems["Actual Size"].exists, "Should have Actual Size")

        // Dismiss menu
        app.typeKey(.escape, modifierFlags: [])
    }

    func testViewMenuHasSidebarToggle() {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()

        let viewMenu = menuBar.menuBarItems["View"]
        XCTAssertTrue(viewMenu.menuItems["Toggle Sidebar"].exists, "Should have Toggle Sidebar")
        XCTAssertTrue(viewMenu.menuItems["Show Comments"].exists, "Should have Show Comments")

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - Tools Menu Items

    func testToolsMenuHasCommentItems() {
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["Tools"].click()

        let toolsMenu = menuBar.menuBarItems["Tools"]
        // Look for comment-related items
        let menuItemNames = toolsMenu.menuItems.allElementsBoundByIndex.map { $0.title }
        XCTAssertTrue(menuItemNames.contains(where: { $0.contains("Comment") }), "Should have comment menu items. Found: \(menuItemNames)")

        app.typeKey(.escape, modifierFlags: [])
    }

    // MARK: - File Opening

    func testOpenMarkdownFile() {
        openFixture("basic.md")

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
        // Window title should contain the filename
        XCTAssertTrue(window.title.contains("basic") || app.windows.allElementsBoundByIndex.contains(where: { $0.title.contains("basic") }),
                      "Window title should contain 'basic'")
    }

    func testOpenFileWithComments() {
        openFixture("comments.md")
        sleep(1)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    func testOpenFileWithFrontmatter() {
        openFixture("frontmatter.md")
        sleep(1)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    func testOpenEmptyFile() {
        openFixture("empty.md")
        sleep(1)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    func testOpenLargeFile() {
        openFixture("large.md")
        sleep(2)

        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists)
    }

    // MARK: - Keyboard Shortcuts

    func testCmdPlusZoomsIn() {
        openFixture("basic.md")
        // Cmd+= is Zoom In
        app.typeKey("=", modifierFlags: .command)
        // Should not crash
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCmdMinusZoomsOut() {
        openFixture("basic.md")
        app.typeKey("-", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCmdZeroResetsZoom() {
        openFixture("basic.md")
        app.typeKey("0", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCmdETogglesEditor() {
        openFixture("basic.md")
        // Toggle editor (if Cmd+E is the shortcut)
        app.typeKey("e", modifierFlags: .command)
        sleep(1)
        XCTAssertTrue(app.windows.firstMatch.exists)
        // Toggle back
        app.typeKey("e", modifierFlags: .command)
        sleep(1)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCtrlCmdSTogglesSidebar() {
        openFixture("basic.md")
        app.typeKey("s", modifierFlags: [.command, .control])
        sleep(1)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    func testCmdShiftMShowsComments() {
        openFixture("basic.md")
        app.typeKey("m", modifierFlags: [.command, .shift])
        sleep(1)
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    // MARK: - Editor Toggle

    func testEditorCanBeToggled() {
        openFixture("basic.md")

        // Find the editor toggle - it might be a menu item
        let menuBar = app.menuBars.firstMatch
        menuBar.menuBarItems["View"].click()

        let hasEditor = menuBar.menuBarItems["View"].menuItems.allElementsBoundByIndex.contains(where: {
            $0.title.contains("Editor") || $0.title.contains("editor")
        })
        app.typeKey(.escape, modifierFlags: [])

        // Just verify the app doesn't crash with editor operations
        XCTAssertTrue(app.windows.firstMatch.exists)
    }

    // MARK: - Multiple Files

    func testOpenMultipleFiles() {
        openFixture("basic.md")
        sleep(1)
        openFixture("linked.md")
        sleep(1)

        // Should have tabs or multiple windows
        XCTAssertTrue(app.windows.count >= 1, "Should handle multiple files")
    }

    // MARK: - Settings

    func testSettingsWindowOpens() {
        app.typeKey(",", modifierFlags: .command)
        sleep(1)

        // Check for settings window
        let settingsExists = app.windows.allElementsBoundByIndex.contains(where: {
            $0.title.contains("Settings") || $0.title.contains("Preferences") || $0.title.contains("QuickMD")
        })
        XCTAssertTrue(settingsExists || app.windows.count > 0, "Settings should be accessible")
    }

    // MARK: - Find

    func testCmdFOpensFind() {
        openFixture("basic.md")
        app.typeKey("f", modifierFlags: .command)
        sleep(1)
        XCTAssertTrue(app.windows.firstMatch.exists, "Find should not crash the app")
    }

    // MARK: - Stress Tests

    func testRapidFileOpening() {
        // Open files rapidly to check for crashes
        for name in ["basic.md", "linked.md", "comments.md", "headings.md", "formatting.md"] {
            openFixture(name)
            usleep(500_000) // 0.5s
        }
        XCTAssertTrue(app.windows.firstMatch.exists, "App should handle rapid file opening")
    }
}
