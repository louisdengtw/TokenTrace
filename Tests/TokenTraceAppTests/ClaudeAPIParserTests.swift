import XCTest
@testable import TokenTraceApp

final class ClaudeAPIParserTests: XCTestCase {
    private let pollTime = Date(timeIntervalSince1970: 1_704_067_200) // 2024-01-01T00:00Z

    func testParsesFullProResponseWithAllThreeBuckets() throws {
        let json = """
        {
            "five_hour":         { "utilization": 47.0, "resets_at": "2026-01-01T05:00:00.000Z" },
            "seven_day":         { "utilization": 22.5, "resets_at": "2026-01-08T00:00:00.000Z" },
            "seven_day_sonnet":  { "utilization": 11.0, "resets_at": "2026-01-08T00:00:00.000Z" }
        }
        """
        let data = json.data(using: .utf8)!

        let response = try ClaudeAPI.parseUsage(data: data, at: pollTime)
        XCTAssertEqual(response.samples.count, 3)
        XCTAssertTrue(response.hasWeeklySonnet)

        let buckets = Set(response.samples.map(\.bucket))
        XCTAssertEqual(buckets, [.fiveHour, .sevenDay, .sevenDaySonnet])

        let fiveHour = try XCTUnwrap(response.samples.first(where: { $0.bucket == .fiveHour }))
        XCTAssertEqual(fiveHour.util, 47.0, accuracy: 0.001)
        XCTAssertEqual(fiveHour.ts, pollTime)
    }

    func testParsesNonProResponseWithoutSevenDaySonnet() throws {
        let json = """
        {
            "five_hour":  { "utilization": 12.0, "resets_at": "2026-01-01T05:00:00.000Z" },
            "seven_day":  { "utilization": 5.0,  "resets_at": "2026-01-08T00:00:00.000Z" }
        }
        """
        let data = json.data(using: .utf8)!

        let response = try ClaudeAPI.parseUsage(data: data, at: pollTime)
        XCTAssertEqual(response.samples.count, 2)
        XCTAssertFalse(response.hasWeeklySonnet)
        XCTAssertFalse(response.samples.contains(where: { $0.bucket == .sevenDaySonnet }))
    }

    func testRejectsMalformedResponse() {
        let cases: [String] = [
            "not even json",
            "{}",
            "{\"unrelated\": 1}"
        ]
        for raw in cases {
            let data = raw.data(using: .utf8)!
            XCTAssertThrowsError(try ClaudeAPI.parseUsage(data: data, at: pollTime)) { error in
                guard case ClaudeAPIError.parseError = error else {
                    XCTFail("expected parseError, got \(error) for input: \(raw)")
                    return
                }
            }
        }
    }

    func testToleratesISO8601WithoutFractionalSeconds() throws {
        let json = """
        {
            "five_hour":  { "utilization": 1.0, "resets_at": "2026-01-01T05:00:00Z" },
            "seven_day":  { "utilization": 2.0, "resets_at": "2026-01-08T00:00:00Z" }
        }
        """
        let response = try ClaudeAPI.parseUsage(data: json.data(using: .utf8)!, at: pollTime)
        XCTAssertEqual(response.samples.count, 2)
    }

    func testExtractsOrgIdFromCookie() {
        let cookie = "sessionKey=abc; lastActiveOrg=11111111-2222-3333-4444-555555555555; foo=bar"
        XCTAssertEqual(
            ClaudeAPI.extractOrgIdFromCookie(cookie),
            "11111111-2222-3333-4444-555555555555"
        )
        XCTAssertNil(ClaudeAPI.extractOrgIdFromCookie("sessionKey=abc; foo=bar"))
        XCTAssertNil(ClaudeAPI.extractOrgIdFromCookie("lastActiveOrg=; foo=bar"))
    }
}
