import XCTest
@testable import TokenTraceApp

final class URLSchemeHandlerTests: XCTestCase {

    func testWellFormedImportURLDecodesCookieValue() {
        // sessionKey=eyJ123; lastActiveOrg=abc → percent-encoded
        let url = URL(string: "tokentrace://import?cookie=sessionKey%3DeyJ123%3B%20lastActiveOrg%3Dabc")!
        let outcome = URLSchemeHandler.handle(url)
        XCTAssertEqual(outcome, .importCookie("sessionKey=eyJ123; lastActiveOrg=abc"))
    }

    func testMissingCookieParameterIsMalformed() {
        let url = URL(string: "tokentrace://import")!
        let outcome = URLSchemeHandler.handle(url)
        guard case .importMalformed(let reason) = outcome else {
            return XCTFail("expected importMalformed, got \(outcome)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("missing"))
    }

    func testEmptyCookieValueIsMalformed() {
        let url = URL(string: "tokentrace://import?cookie=")!
        let outcome = URLSchemeHandler.handle(url)
        guard case .importMalformed(let reason) = outcome else {
            return XCTFail("expected importMalformed, got \(outcome)")
        }
        XCTAssertTrue(reason.localizedCaseInsensitiveContains("empty"))
    }

    func testUnknownPathIsIgnored() {
        let url = URL(string: "tokentrace://something-else?cookie=evil")!
        XCTAssertEqual(URLSchemeHandler.handle(url), .ignored)
    }

    func testUnknownSchemeIsIgnored() {
        let url = URL(string: "https://import?cookie=evil")!
        XCTAssertEqual(URLSchemeHandler.handle(url), .ignored)
    }

    func testQueryOrderingDoesNotMatter() {
        let url = URL(string: "tokentrace://import?other=foo&cookie=sessionKey%3Dabc&trailing=bar")!
        XCTAssertEqual(URLSchemeHandler.handle(url), .importCookie("sessionKey=abc"))
    }

    func testHostMatchIsCaseInsensitive() {
        let url = URL(string: "tokentrace://Import?cookie=sessionKey%3Dabc")!
        XCTAssertEqual(URLSchemeHandler.handle(url), .importCookie("sessionKey=abc"))
    }
}
