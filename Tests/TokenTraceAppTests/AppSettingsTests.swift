import XCTest
@testable import TokenTraceApp

final class AppSettingsTests: XCTestCase {

    private let key = "lastDashboardTab"

    override func tearDown() {
        UserDefaults.standard.removeObject(forKey: key)
        super.tearDown()
    }

    func testDefaultIsSubscription() {
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(AppSettings.lastDashboardTab, .subscription)
    }

    func testWriteThenRead() {
        AppSettings.lastDashboardTab = .claudeCode
        XCTAssertEqual(AppSettings.lastDashboardTab, .claudeCode)

        AppSettings.lastDashboardTab = .subscription
        XCTAssertEqual(AppSettings.lastDashboardTab, .subscription)
    }

    func testCorruptValueFallsBack() {
        UserDefaults.standard.set("notATab", forKey: key)
        XCTAssertEqual(AppSettings.lastDashboardTab, .subscription)
    }

    func testUnknownFutureValueFallsBack() {
        // A future build might persist a new case like "menuBar"; older builds
        // should still load cleanly into the default rather than crash.
        UserDefaults.standard.set("menuBar", forKey: key)
        XCTAssertEqual(AppSettings.lastDashboardTab, .subscription)
    }
}
