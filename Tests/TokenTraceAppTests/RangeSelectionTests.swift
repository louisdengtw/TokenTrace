import XCTest
@testable import TokenTraceApp

final class RangeSelectionTests: XCTestCase {

    // MARK: - 90d preset (claude-code-usage group 6)

    func testLast90dInAllCases() {
        // The picker UI relies on .allCases ordering: 24h · 7d · 30d · 90d · All
        let order = RangePreset.allCases
        XCTAssertEqual(order, [.last24h, .last7d, .last30d, .last90d, .all])
    }

    func testLast90dLabel() {
        XCTAssertEqual(RangePreset.last90d.label, "90d")
    }

    func testLast90dResolves() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        let (start, end) = RangeSelection.preset(.last90d)
            .resolved(now: now, oldestSample: nil)
        XCTAssertEqual(end, now)
        XCTAssertEqual(start, now.addingTimeInterval(-90 * 86400))
    }

    func testLast90dTrendDescription() {
        XCTAssertEqual(
            RangeSelection.preset(.last90d).trendDescription,
            "Trend across last 90 days"
        )
    }

    // MARK: - Codable round-trip with the new case

    func testLast90dCodableRoundTrip() throws {
        let original = RangeSelection.preset(.last90d)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(RangeSelection.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    // MARK: - Backward compatibility — older AppSettings payload without 90d

    func testOlderPayloadWithout90dStillDecodes() throws {
        // Pre-90d AppSettings payloads might store last7d/last30d/etc; all of
        // these must still decode (no version field exists, so we rely on the
        // raw-value enum tolerating new cases without breaking old strings).
        for raw in ["last24h", "last7d", "last30d", "all"] {
            let payload = """
            { "kind": "preset", "preset": "\(raw)" }
            """.data(using: .utf8)!
            let decoded = try JSONDecoder().decode(RangeSelection.self, from: payload)
            switch decoded {
            case .preset(let p):
                XCTAssertEqual(p.rawValue, raw)
            default:
                XCTFail("expected preset for \(raw)")
            }
        }
    }

    // MARK: - Existing preset resolutions still correct after the insertion

    func testOtherPresetsUnaffected() {
        let now = Date(timeIntervalSince1970: 1_900_000_000)
        XCTAssertEqual(
            RangeSelection.preset(.last24h).resolved(now: now, oldestSample: nil).start,
            now.addingTimeInterval(-24 * 3600)
        )
        XCTAssertEqual(
            RangeSelection.preset(.last7d).resolved(now: now, oldestSample: nil).start,
            now.addingTimeInterval(-7 * 86400)
        )
        XCTAssertEqual(
            RangeSelection.preset(.last30d).resolved(now: now, oldestSample: nil).start,
            now.addingTimeInterval(-30 * 86400)
        )
    }
}
