import XCTest

/// Captures the screenshots used in the App Store listing.
///
/// Each screen is its own test method so we get a fresh app launch per
/// screenshot. This sidesteps NavigationStack back-button identifier
/// fragility and keeps every capture independent — if one screen fails the
/// rest still run.
///
/// `scripts/screenshots.sh` runs this suite on the iPhone 6.9" and iPad 13"
/// simulators, pulls the PNGs out of the xcresult bundle, and renames them
/// per App Store convention.
final class AppStoreScreenshots: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // 1. List with seeded credentials.
    func test01List() {
        let app = launchSeeded()
        XCTAssertTrue(app.staticTexts["GitHub"].waitForExistence(timeout: 15))
        attach(name: "01-list")
    }

    // 2. Onboarding welcome screen (privacy story for App Store reviewers).
    //    Tapping a row would jump straight into edit mode + passcode prompt,
    //    which is not a useful App Store screenshot, so we capture onboarding
    //    instead.
    func test02Onboarding() {
        let app = XCUIApplication()
        app.launchArguments += ["--reset-onboarding"]
        app.launch()
        XCTAssertTrue(app.staticTexts["Welcome to KeyNest"].waitForExistence(timeout: 15))
        attach(name: "02-onboarding")
    }

    // 3. New credential form.
    func test03Add() {
        let app = launchSeeded()
        XCTAssertTrue(app.staticTexts["GitHub"].waitForExistence(timeout: 15))
        XCTAssertTrue(tapToolbarButton(app, label: "Add credential"),
                      "Add credential toolbar button not found")
        _ = app.textFields.firstMatch.waitForExistence(timeout: 5)
        attach(name: "03-add")
    }

    // 4. Settings screen.
    func test04Settings() {
        let app = launchSeeded()
        XCTAssertTrue(app.staticTexts["GitHub"].waitForExistence(timeout: 15))
        XCTAssertTrue(tapToolbarButton(app, label: "Settings"),
                      "Settings toolbar button not found")
        _ = app.navigationBars["Settings"].waitForExistence(timeout: 5)
        attach(name: "04-settings")
    }

    // 5. Sort menu open (visual variety on the list).
    func test05Sort() {
        let app = launchSeeded()
        XCTAssertTrue(app.staticTexts["GitHub"].waitForExistence(timeout: 15))
        XCTAssertTrue(tapToolbarButton(app, label: "Sort"),
                      "Sort toolbar button not found")
        _ = app.staticTexts["Updated (newest)"].waitForExistence(timeout: 3)
        attach(name: "05-sort")
    }

    // MARK: - Helpers

    private func launchSeeded() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["--seed-demo"]
        app.launchEnvironment["KN_SEED_DEMO"] = "1"
        app.launch()
        return app
    }

    private func attach(name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @discardableResult
    private func tapToolbarButton(_ app: XCUIApplication, label: String) -> Bool {
        let candidates: [XCUIElement] = [
            app.navigationBars.buttons[label],
            app.buttons[label]
        ]
        for el in candidates {
            if el.waitForExistence(timeout: 2), el.isHittable {
                el.tap()
                return true
            }
        }
        return false
    }
}
