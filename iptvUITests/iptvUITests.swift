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

    #if os(iOS)
    @MainActor
    func testPlayerQuickSettingsSheetShowsVolumeAndBrightnessControls() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-player")
        app.launch()

        let settingsChip = app.buttons["player.chip.settings"]
        XCTAssertTrue(settingsChip.waitForExistence(timeout: 5))
        settingsChip.tap()

        XCTAssertTrue(app.navigationBars["Quick Settings"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["player.volume"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.sliders["player.brightness"].exists)
        XCTAssertTrue(app.otherElements["player.outputRoutePicker"].exists)
        XCTAssertTrue(app.buttons["player.outputRouteSelection"].exists)
    }

    @MainActor
    func testPlayerSeriesModeShowsEpisodeSwitcher() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-player-series")
        app.launch()

        let episodesChip = app.buttons["player.chip.episodes"]
        XCTAssertTrue(episodesChip.waitForExistence(timeout: 5))
        XCTAssertTrue(episodesChip.isEnabled)
        episodesChip.tap()

        XCTAssertTrue(app.navigationBars["Episodes"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Episode 1"].exists)
        XCTAssertTrue(app.buttons["Episode 2"].exists)
    }

    @MainActor
    func testUnsupportedControlsRemainVisibleButDisabled() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-player")
        app.launch()

        let mediaChip = app.buttons["player.chip.media"]
        XCTAssertTrue(mediaChip.waitForExistence(timeout: 5))
        XCTAssertFalse(mediaChip.isEnabled)
    }
    #endif

    #if os(tvOS)
    @MainActor
    func testTvOSPlayerOverlayShowsTransportAndMediaActions() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-player")
        app.launch()

        XCTAssertTrue(app.buttons["player.playPause"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Media"].exists)
        XCTAssertTrue(app.buttons["Quality"].exists)
        XCTAssertTrue(app.buttons["Chapters"].exists)
    }
    #endif

    #if os(macOS)
    @MainActor
    func testMacOSPlayerMenuContainsAdvancedSections() throws {
        let app = makeApp()
        app.launchArguments.append("--uitest-open-player")
        app.launch()

        let playerMenu = app.menuBars.menuBarItems["Player"]
        XCTAssertTrue(playerMenu.waitForExistence(timeout: 5))
        playerMenu.click()

        XCTAssertTrue(app.menuItems["Audio Tracks"].exists)
        XCTAssertTrue(app.menuItems["Subtitles"].exists)
        XCTAssertTrue(app.menuItems["More"].exists)
        XCTAssertFalse(app.menuItems["Quality"].exists)
    }
    #endif

    private func makeApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments.append("--disable-keychain-auth-ui")
        return app
    }
}
