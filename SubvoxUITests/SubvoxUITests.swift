import Darwin
import XCTest

/// End-to-end checks that drive the running app: sidebar navigation across all three
/// screens, vocabulary persistence, and the session recorder's on-disk output.
final class SubvoxUITests: XCTestCase {
    var app: XCUIApplication!

    /// The real home directory. The test runner itself is sandboxed, so plain
    /// `FileManager` lookups land in its container instead of the app's files.
    private var realHome: URL {
        URL(fileURLWithPath: String(cString: getpwuid(getuid()).pointee.pw_dir))
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    private func goTo(_ screen: String) {
        let row = app.staticTexts[screen]
        XCTAssertTrue(row.waitForExistence(timeout: 15), "missing sidebar row \(screen)")
        row.click()
    }

    func testNavigationAndScreens() {
        goTo("Sensors")
        XCTAssertTrue(app.staticTexts["AirPods motion"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Microphone"].waitForExistence(timeout: 15))
        goTo("Train")
        XCTAssertTrue(app.staticTexts["Vocabulary"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Is there signal? (leave-one-out + permutation test)"].waitForExistence(timeout: 15))
        goTo("Decode")
        XCTAssertTrue(app.staticTexts["Decoded from motion"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Microphone transcript (reference)"].waitForExistence(timeout: 15))
    }

    func testAddWordPersistsDataset() throws {
        goTo("Train")
        let field = app.textFields["Add word"]
        XCTAssertTrue(field.waitForExistence(timeout: 15))
        field.click()
        field.typeText("helix")
        app.buttons["Add"].click()
        XCTAssertTrue(app.staticTexts["helix"].waitForExistence(timeout: 15))
        let url = realHome
            .appendingPathComponent("Library/Application Support/Subvox", isDirectory: true)
            .appendingPathComponent("dataset.json")
        let data = try Data(contentsOf: url)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("helix") ?? false)
        // Clean up through the UI: exercises word removal and leaves a clean dataset.
        app.staticTexts["helix"].rightClick()
        let deleteItem = app.menuItems["Delete “helix” and its takes"]
        XCTAssertTrue(deleteItem.waitForExistence(timeout: 15))
        deleteItem.click()
        XCTAssertFalse(app.staticTexts["helix"].waitForExistence(timeout: 5))
    }

    func testRecordingCreatesSession() throws {
        let root = realHome
            .appendingPathComponent("Documents/Subvox/Sessions", isDirectory: true)
        let before = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        goTo("Sensors")
        let record = app.buttons["Record Session"]
        XCTAssertTrue(record.waitForExistence(timeout: 15))
        record.click()
        XCTAssertTrue(app.buttons["Stop Recording"].waitForExistence(timeout: 15))
        app.buttons["Stop Recording"].click()
        XCTAssertTrue(app.buttons["Record Session"].waitForExistence(timeout: 15))
        let after = try FileManager.default.contentsOfDirectory(atPath: root.path)
        let fresh = after.filter { !before.contains($0) }
        XCTAssertEqual(fresh.count, 1, "expected one new session dir, got \(fresh)")
        let meta = root.appendingPathComponent(fresh[0]).appendingPathComponent("meta.json")
        let text = try String(contentsOf: meta)
        XCTAssertTrue(text.contains("Silent mouthing"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(fresh[0]).appendingPathComponent("motion.csv").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent(fresh[0]).appendingPathComponent("events.csv").path))
    }
}
