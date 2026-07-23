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
        XCTAssertEqual(response.scopedModels, ["Sonnet"])

        let buckets = Set(response.samples.map(\.bucket))
        XCTAssertEqual(buckets, [.fiveHour, .sevenDay, .weeklyScoped(model: "Sonnet")])

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
        XCTAssertTrue(response.scopedModels.isEmpty)
        XCTAssertFalse(response.samples.contains(where: { $0.bucket == .weeklyScoped(model: "Sonnet") }))
    }

    func testParsesLimitsArrayWithScopedFable() throws {
        let json = """
        {
            "five_hour":        { "utilization": 1.0, "resets_at": "2026-07-23T09:59:59.726886+00:00" },
            "seven_day":        { "utilization": 3.0, "resets_at": "2026-07-25T01:59:59.726914+00:00" },
            "seven_day_sonnet": null,
            "seven_day_opus":   null,
            "limits": [
                { "kind": "session",       "group": "session", "percent": 1, "resets_at": "2026-07-23T09:59:59.726886+00:00", "scope": null, "is_active": false },
                { "kind": "weekly_all",    "group": "weekly",  "percent": 3, "resets_at": "2026-07-25T01:59:59.726914+00:00", "scope": null, "is_active": false },
                { "kind": "weekly_scoped", "group": "weekly",  "percent": 5, "resets_at": "2026-07-25T01:59:59.727215+00:00",
                  "scope": { "model": { "id": null, "display_name": "Fable" }, "surface": null }, "is_active": true }
            ]
        }
        """
        let response = try ClaudeAPI.parseUsage(data: json.data(using: .utf8)!, at: pollTime)

        XCTAssertEqual(response.scopedModels, ["Fable"])
        XCTAssertEqual(response.samples.count, 3)

        // Fixed windows come from the float top-level objects, not limits[].
        let fiveHour = try XCTUnwrap(response.samples.first(where: { $0.bucket == .fiveHour }))
        XCTAssertEqual(fiveHour.util, 1.0, accuracy: 0.001)

        let fable = try XCTUnwrap(response.samples.first(where: { $0.bucket == .weeklyScoped(model: "Fable") }))
        XCTAssertEqual(fable.util, 5.0, accuracy: 0.001)
        // Null seven_day_sonnet tombstone must not produce a Sonnet series.
        XCTAssertFalse(response.samples.contains(where: { $0.bucket == .weeklyScoped(model: "Sonnet") }))
    }

    func testFallsBackToLimitsWhenTopLevelKeysMissing() throws {
        let json = """
        {
            "limits": [
                { "kind": "session",    "group": "session", "percent": 40, "resets_at": "2026-07-23T09:59:59Z", "scope": null },
                { "kind": "weekly_all", "group": "weekly",  "percent": 12, "resets_at": "2026-07-25T01:59:59Z", "scope": null }
            ]
        }
        """
        let response = try ClaudeAPI.parseUsage(data: json.data(using: .utf8)!, at: pollTime)
        XCTAssertEqual(response.samples.count, 2)
        let fiveHour = try XCTUnwrap(response.samples.first(where: { $0.bucket == .fiveHour }))
        XCTAssertEqual(fiveHour.util, 40.0, accuracy: 0.001)
    }

    func testSkipsScopedLimitWithoutModelName() throws {
        let json = """
        {
            "five_hour": { "utilization": 1.0, "resets_at": "2026-07-23T09:59:59Z" },
            "seven_day": { "utilization": 3.0, "resets_at": "2026-07-25T01:59:59Z" },
            "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 9, "resets_at": "2026-07-25T01:59:59Z",
                  "scope": { "model": null, "surface": "cowork" } }
            ]
        }
        """
        let response = try ClaudeAPI.parseUsage(data: json.data(using: .utf8)!, at: pollTime)
        XCTAssertEqual(response.samples.count, 2)
        XCTAssertTrue(response.scopedModels.isEmpty)
    }

    func testLimitsWinOverLegacySonnetKeyForSameModel() throws {
        let json = """
        {
            "five_hour":        { "utilization": 1.0,  "resets_at": "2026-07-23T09:59:59Z" },
            "seven_day":        { "utilization": 3.0,  "resets_at": "2026-07-25T01:59:59Z" },
            "seven_day_sonnet": { "utilization": 99.0, "resets_at": "2026-07-25T01:59:59Z" },
            "limits": [
                { "kind": "weekly_scoped", "group": "weekly", "percent": 5, "resets_at": "2026-07-25T01:59:59Z",
                  "scope": { "model": { "id": null, "display_name": "Sonnet" }, "surface": null } }
            ]
        }
        """
        let response = try ClaudeAPI.parseUsage(data: json.data(using: .utf8)!, at: pollTime)
        XCTAssertEqual(response.scopedModels, ["Sonnet"])
        let sonnet = response.samples.filter { $0.bucket == .weeklyScoped(model: "Sonnet") }
        XCTAssertEqual(sonnet.count, 1)
        XCTAssertEqual(sonnet[0].util, 5.0, accuracy: 0.001)
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
