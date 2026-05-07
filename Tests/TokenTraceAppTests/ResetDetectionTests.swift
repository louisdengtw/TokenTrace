import XCTest
@testable import TokenTraceApp

final class ResetDetectionTests: XCTestCase {
    private func sample(t: TimeInterval, resetsAt: TimeInterval) -> UsageSample {
        UsageSample(
            ts: Date(timeIntervalSince1970: t),
            bucket: .fiveHour,
            util: 0,
            resetsAt: Date(timeIntervalSince1970: resetsAt)
        )
    }

    func testEmptyAndSingleSample() {
        XCTAssertEqual(ResetDetection.detect([]), [])
        XCTAssertEqual(ResetDetection.detect([sample(t: 0, resetsAt: 100)]), [])
    }

    func testNoResetWhenAllResetsAtEqual() {
        let samples = [
            sample(t: 0,  resetsAt: 100),
            sample(t: 10, resetsAt: 100),
            sample(t: 20, resetsAt: 100)
        ]
        XCTAssertEqual(ResetDetection.detect(samples), [])
    }

    func testSingleResetBetweenTwoSamples() {
        let samples = [
            sample(t: 100, resetsAt: 200),
            sample(t: 210, resetsAt: 400)
        ]
        let events = ResetDetection.detect(samples)
        XCTAssertEqual(events, [ResetEvent(displayTimestamp: Date(timeIntervalSince1970: 200))])
    }

    func testMultipleConsecutiveResets() {
        let samples = [
            sample(t: 0,   resetsAt: 100),
            sample(t: 110, resetsAt: 200),
            sample(t: 210, resetsAt: 300),
            sample(t: 310, resetsAt: 400)
        ]
        let events = ResetDetection.detect(samples)
        XCTAssertEqual(events, [
            ResetEvent(displayTimestamp: Date(timeIntervalSince1970: 100)),
            ResetEvent(displayTimestamp: Date(timeIntervalSince1970: 200)),
            ResetEvent(displayTimestamp: Date(timeIntervalSince1970: 300))
        ])
    }

    func testNoEventWhenResetsAtDecreases() {
        let samples = [
            sample(t: 0,  resetsAt: 200),
            sample(t: 10, resetsAt: 100)
        ]
        XCTAssertEqual(ResetDetection.detect(samples), [],
                       "Detection only fires on strictly increasing resets_at, not decreases")
    }
}
