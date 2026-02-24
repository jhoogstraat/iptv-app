//
//  iptvUITests.swift
//  iptvUITests
//
//  Created by HOOGSTRAAT, JOSHUA on 02.09.25.
//

import XCTest

final class iptvUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testShowsConfigureProviderCTAWhenMissingConfig() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-movies")
        app.launch()

        XCTAssertTrue(app.staticTexts["Configure Provider"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Configure Provider"].exists)
    }

    @MainActor
    func testOpenAndCloseSettingsFromConfigureProviderCTA() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-movies")
        app.launch()

        let configureButton = app.buttons["Configure Provider"]
        XCTAssertTrue(configureButton.waitForExistence(timeout: 5))
        configureButton.tap()

        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
        let doneButton = app.buttons["Done"]
        XCTAssertTrue(doneButton.exists)
        doneButton.tap()
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            makeApp().launch()
        }
    }

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--disable-keychain-auth-ui")
        return app
    }
}
