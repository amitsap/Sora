import XCTest

final class SoraUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launch()
    }

    func testTabBarIsVisible() throws {
        XCTAssert(app.tabBars.firstMatch.waitForExistence(timeout: 5))
    }

    func testAddFlightButtonExists() throws {
        // Home tab should have the + FAB
        XCTAssert(app.tabBars.firstMatch.waitForExistence(timeout: 5))
        let addButton = app.buttons.matching(NSPredicate(format: "label CONTAINS 'plus'")).firstMatch
        XCTAssert(addButton.waitForExistence(timeout: 3))
    }
}
