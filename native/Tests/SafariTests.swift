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
        let webLinks = safari.webViews.links
        let matchingLabels = webLinks.matching(NSPredicate(format: "label CONTAINS %@", destinationLabel))
        let matchingChildren = webLinks.containing(.staticText, identifier: destinationLabel)
        XCTAssertTrue(link.waitForExistence(timeout: 60), "Start-page link was unavailable")
        XCTAssertFalse(matchingLabels.firstMatch.exists || matchingChildren.firstMatch.exists,
                       "Destination link was already present before the tap")
        link.tap()

        // Start above Safari's bottom controls and first-run tips.
        let scrollStart = safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.60))
        let scrollEnd = safari.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.23))
        _ = matchingLabels.firstMatch.waitForExistence(timeout: 8)
        for scrollCount in 0...20 {
            let candidates = matchingLabels.allElementsBoundByIndex + matchingChildren.allElementsBoundByIndex
            if candidates.contains(where: { $0.isHittable }) {
                return
            }
            if scrollCount < 20 {
                scrollStart.press(forDuration: 0.05, thenDragTo: scrollEnd)
            }
        }
        XCTFail("Destination link was not visible after scrolling")
    }
}
