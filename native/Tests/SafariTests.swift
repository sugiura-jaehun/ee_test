import XCTest

final class SafariTests: XCTestCase {
    func testTapLinkInSafari() throws {
        continueAfterFailure = false

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.open(try XCTUnwrap(URL(string: "http://127.0.0.1:8765/")))

        let link = safari.links["Open result"].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 30), safari.debugDescription)
        link.tap()

        let result = safari.staticTexts["Link clicked"].firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 15), safari.debugDescription)
    }
}
