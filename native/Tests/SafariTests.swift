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

    func testTapLinkOnConfiguredSite() throws {
        continueAfterFailure = false

        let environment = ProcessInfo.processInfo.environment
        let start = try XCTUnwrap(environment["SMOKE_START_URL"])
        let linkLabel = try XCTUnwrap(environment["SMOKE_LINK_LABEL"])
        let destinationLabel = try XCTUnwrap(environment["SMOKE_DESTINATION_LABEL"])
        let url = try XCTUnwrap(URL(string: start))
        XCTAssertEqual(url.scheme, "https")

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        safari.open(url)

        let link = safari.links[linkLabel].firstMatch
        let destination = safari.staticTexts[destinationLabel].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 60), "Start-page link was unavailable")
        XCTAssertFalse(destination.exists, "Destination marker was already visible before the tap")
        link.tap()
        XCTAssertTrue(destination.waitForExistence(timeout: 45), "Destination marker was unavailable after the tap")
    }
}
