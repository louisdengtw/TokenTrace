import XCTest
@testable import TokenTraceApp

final class CookieParserTests: XCTestCase {

    // MARK: - Raw cookie header

    func testAcceptsRawCookieHeaderUnchanged() throws {
        let input = "sessionKey=eyJ123; lastActiveOrg=11111111-2222-3333-4444-555555555555; cf_bm=xyz"
        XCTAssertEqual(try CookieParser.parse(input).get(), input)
    }

    func testTrimsLeadingTrailingWhitespaceFromRawHeader() throws {
        let input = "  sessionKey=eyJ123; lastActiveOrg=abc  \n"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    // MARK: - Cookie: prefix

    func testStripsCookieHeaderPrefix() throws {
        let input = "Cookie: sessionKey=eyJ123; lastActiveOrg=abc"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    func testCookiePrefixIsCaseInsensitive() throws {
        let input = "cookie: sessionKey=eyJ123"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123")
    }

    func testCookiePrefixWithMixedCase() throws {
        let input = "CoOkIe:   sessionKey=eyJ123; lastActiveOrg=abc"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    // MARK: - cURL single-line

    func testExtractsCookieFromChromiumStyleCurl() throws {
        let input = "curl 'https://claude.ai/api/organizations/x/usage' -H 'accept: */*' -H 'cookie: sessionKey=eyJ123; lastActiveOrg=abc' -H 'user-agent: Mozilla/5.0'"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    func testExtractsCookieFromCurlWithDoubleQuotes() throws {
        let input = "curl \"https://claude.ai/\" -H \"cookie: sessionKey=eyJ123; lastActiveOrg=abc\""
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    // MARK: - cURL multi-line continuation

    func testCollapsesBackslashNewlineContinuations() throws {
        let input = """
        curl 'https://claude.ai/api/.../usage' \\
          -H 'accept: */*' \\
          -H 'cookie: sessionKey=eyJ123; lastActiveOrg=abc' \\
          -H 'user-agent: TestUA'
        """
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    // MARK: - --header long form

    func testExtractsCookieWithLongHeaderForm() throws {
        let input = "curl --header \"Cookie: sessionKey=eyJ123; lastActiveOrg=abc\" 'https://claude.ai/api/.../usage'"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123; lastActiveOrg=abc")
    }

    // MARK: - Mixed-case header name in cURL

    func testHeaderNameMatchIsCaseInsensitive() throws {
        let input = "curl -H 'CooKie: sessionKey=eyJ123' 'https://claude.ai/'"
        XCTAssertEqual(try CookieParser.parse(input).get(), "sessionKey=eyJ123")
    }

    // MARK: - Rejection cases

    func testRejectsEmptyInput() {
        let result = CookieParser.parse("   \n  ")
        guard case .failure(let err) = result, case .empty = err else {
            return XCTFail("expected .empty, got \(result)")
        }
    }

    func testRejectsRawHeaderWithoutSessionKey() {
        let result = CookieParser.parse("foo=bar; baz=qux")
        guard case .failure(let err) = result, case .missingSessionKey = err else {
            return XCTFail("expected .missingSessionKey, got \(result)")
        }
    }

    func testRejectsCookiePrefixWithoutSessionKey() {
        let result = CookieParser.parse("Cookie: foo=bar; baz=qux")
        guard case .failure(let err) = result, case .missingSessionKey = err else {
            return XCTFail("expected .missingSessionKey, got \(result)")
        }
    }

    func testRejectsCurlWithoutCookieHeader() {
        let input = "curl 'https://claude.ai/' -H 'accept: */*' -H 'user-agent: Test'"
        let result = CookieParser.parse(input)
        guard case .failure(let err) = result, case .curlMissingCookieHeader = err else {
            return XCTFail("expected .curlMissingCookieHeader, got \(result)")
        }
    }

    func testRejectsCurlWithCookieHeaderButNoSessionKey() {
        // Cookie header present, but its value doesn't include sessionKey.
        let input = "curl -H 'cookie: foo=bar; baz=qux' 'https://claude.ai/'"
        let result = CookieParser.parse(input)
        guard case .failure(let err) = result, case .missingSessionKey = err else {
            return XCTFail("expected .missingSessionKey, got \(result)")
        }
    }
}
