import XCTest
@testable import TokenTraceApp

final class CCWeightedVolumeTests: XCTestCase {

    func testRepresentativeRecord() {
        // (input, output, cache_create, cache_read) = (100, 50, 200, 1000)
        // → 100·1 + 50·5 + 200·1.25 + 1000·0.1 = 100 + 250 + 250 + 100 = 700
        let result = CCWeightedVolume.weightedTotal(
            input: 100, output: 50, cacheCreation: 200, cacheRead: 1000
        )
        XCTAssertEqual(result, 700.0, accuracy: 0.0001)
    }

    func testCacheHeavyEdge() {
        // Pure cache_read of 100k tokens at 0.1× = 10000
        let result = CCWeightedVolume.weightedTotal(
            input: 0, output: 0, cacheCreation: 0, cacheRead: 100_000
        )
        XCTAssertEqual(result, 10_000.0, accuracy: 0.0001)
    }

    func testZeroRecord() {
        let result = CCWeightedVolume.weightedTotal(
            input: 0, output: 0, cacheCreation: 0, cacheRead: 0
        )
        XCTAssertEqual(result, 0.0, accuracy: 0.0001)
    }

    func testNoSignedOverflowOnLargeInts() {
        // Guard against accidental Int arithmetic before the Double cast: if
        // implementation did `(a + b + c + d).double * weight` it could wrap
        // negative on Int.max. The current implementation casts each term
        // before multiplication, so this should comfortably hold.
        let big = Int.max / 10
        let result = CCWeightedVolume.weightedTotal(
            input: big, output: big, cacheCreation: big, cacheRead: big
        )
        XCTAssertGreaterThan(result, 0)
        XCTAssertFalse(result.isNaN)
        XCTAssertFalse(result.isInfinite)
    }

    func testWeightConstantsMatchSpec() {
        XCTAssertEqual(CCWeightedVolume.inputWeight,         1.0,  accuracy: 0.0001)
        XCTAssertEqual(CCWeightedVolume.outputWeight,        5.0,  accuracy: 0.0001)
        XCTAssertEqual(CCWeightedVolume.cacheCreationWeight, 1.25, accuracy: 0.0001)
        XCTAssertEqual(CCWeightedVolume.cacheReadWeight,     0.1,  accuracy: 0.0001)
    }
}
