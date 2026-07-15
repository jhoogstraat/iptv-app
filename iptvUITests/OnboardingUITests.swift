import XCTest

final class OnboardingUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testSourceSelectionOffersXtreamAndLabelsM3U8AsSoon() {
        let app = XCUIApplication()
        app.launch()

        let xtreamSource = app.descendants(matching: .any)["onboarding.source.xtream"]
        XCTAssertTrue(xtreamSource.waitForExistence(timeout: 10))

        let m3u8Source = app.descendants(matching: .any)["onboarding.source.m3u8"]
        XCTAssertTrue(m3u8Source.exists)
        XCTAssertTrue(m3u8Source.staticTexts["soon"].exists)
        XCTAssertFalse(m3u8Source.isEnabled)
    }

    func testXtreamSelectionReachesCredentialForm() {
        let app = XCUIApplication()
        app.launch()

        let source = app.descendants(matching: .any)["onboarding.source.xtream"]
        XCTAssertTrue(source.waitForExistence(timeout: 10))
        source.tap()
        app.descendants(matching: .any)["onboarding.source.continue"].tap()

        XCTAssertTrue(app.textFields["onboarding.provider.url"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.secureTextFields["onboarding.provider.password"].exists)

        let insecureToggle = app.switches["onboarding.provider.allowInsecureHTTP"]
        XCTAssertTrue(insecureToggle.exists)
        XCTAssertFalse(app.descendants(matching: .any)["onboarding.provider.insecureHTTPWarning"].exists)
        insecureToggle.tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.provider.insecureHTTPWarning"].exists)

        let navigationBar = app.navigationBars["Xtream API"]
        XCTAssertTrue(navigationBar.exists)
        XCTAssertTrue(navigationBar.buttons.firstMatch.exists)
        navigationBar.buttons.firstMatch.tap()

        XCTAssertTrue(app.descendants(matching: .any)["onboarding.source.continue"].waitForExistence(timeout: 3))
    }
}
