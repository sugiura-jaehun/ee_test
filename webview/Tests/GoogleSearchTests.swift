import XCTest

final class GoogleSearchTests: XCTestCase {
    func testSearchWithinInstalledApp() {
        continueAfterFailure = false

        let app = XCUIApplication()
        app.launch()

        let webView = app.webViews.firstMatch
        XCTAssertTrue(webView.waitForExistence(timeout: 25))

        let rejectCookies = webView.buttons["Reject all"].firstMatch
        if rejectCookies.waitForExistence(timeout: 5) {
            rejectCookies.tap()
        }

        let searchField = webView.searchFields.firstMatch
        let textField = webView.textFields.firstMatch
        let field = searchField.waitForExistence(timeout: 8) ? searchField : textField
        XCTAssertTrue(field.waitForExistence(timeout: 25), app.debugDescription)
        let query = "Apple XCTest documentation"
        field.tap()
        field.typeText(query + "\n")

        let page = app.staticTexts["loaded-page"]
        let resultsLoaded = NSPredicate { object, _ in
            guard let element = object as? XCUIElement,
                  let url = URLComponents(string: element.label) else {
                return false
            }
            return url.host == "www.google.com"
                && url.path == "/search"
                && url.queryItems?.contains { item in
                    item.name == "q" && item.value?.replacingOccurrences(of: "+", with: " ") == query
                } == true
        }
        let wait = XCTNSPredicateExpectation(predicate: resultsLoaded, object: page)
        XCTAssertEqual(XCTWaiter.wait(for: [wait], timeout: 45), .completed, app.debugDescription)
        XCTAssertEqual(app.state, .runningForeground)
        print("Google WebView loaded search results for \(query)")
    }
}
