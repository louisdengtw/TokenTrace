import XCTest
@testable import TokenTraceApp

final class UsageStoreTests: XCTestCase {
    private var dbURL: URL!

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenTraceStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("usage.sqlite")
    }

    override func tearDownWithError() throws {
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
    }

    func testFreshDatabaseIsCreated() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: dbURL.path))
        _ = try UsageStore(url: dbURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path))
    }

    func testInsertQueryRoundtrip() throws {
        let store = try UsageStore(url: dbURL)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let resetsAt = now.addingTimeInterval(3600)
        let sample = UsageSample(ts: now, bucket: .fiveHour, util: 42.5, resetsAt: resetsAt)

        store.insert(samples: [sample])

        let rows = store.query(
            bucket: .fiveHour,
            from: now.addingTimeInterval(-1),
            to: now.addingTimeInterval(1)
        )
        XCTAssertEqual(rows.count, 1)
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.util, 42.5, accuracy: 0.001)
        XCTAssertEqual(row.ts.timeIntervalSince1970,
                       now.timeIntervalSince1970, accuracy: 0.5)
        XCTAssertEqual(row.resetsAt.timeIntervalSince1970,
                       resetsAt.timeIntervalSince1970, accuracy: 0.5)
    }

    func testInsertOrReplaceOnDuplicateKey() throws {
        let store = try UsageStore(url: dbURL)
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let r1 = ts.addingTimeInterval(3600)
        let first = UsageSample(ts: ts, bucket: .fiveHour, util: 30, resetsAt: r1)
        let second = UsageSample(ts: ts, bucket: .fiveHour, util: 80, resetsAt: r1)

        store.insert(samples: [first])
        store.insert(samples: [second])

        let rows = store.query(bucket: .fiveHour, from: ts, to: ts)
        XCTAssertEqual(rows.count, 1, "PRIMARY KEY (ts, bucket) duplicate should REPLACE, not insert")
        let row = try XCTUnwrap(rows.first)
        XCTAssertEqual(row.util, 80, accuracy: 0.001)
    }

    func testEmptyRangeReturnsEmptyArray() throws {
        let store = try UsageStore(url: dbURL)
        let rows = store.query(
            bucket: .sevenDay,
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 100)
        )
        XCTAssertEqual(rows, [])
    }

    func testDifferentBucketsAtSameTimestampCoexist() throws {
        let store = try UsageStore(url: dbURL)
        let ts = Date(timeIntervalSince1970: 1_700_000_000)
        let r = ts.addingTimeInterval(3600)
        store.insert(samples: [
            UsageSample(ts: ts, bucket: .fiveHour, util: 10, resetsAt: r),
            UsageSample(ts: ts, bucket: .sevenDay, util: 20, resetsAt: r),
            UsageSample(ts: ts, bucket: .sevenDaySonnet, util: 30, resetsAt: r)
        ])
        XCTAssertEqual(store.query(bucket: .fiveHour, from: ts, to: ts).first?.util, 10)
        XCTAssertEqual(store.query(bucket: .sevenDay, from: ts, to: ts).first?.util, 20)
        XCTAssertEqual(store.query(bucket: .sevenDaySonnet, from: ts, to: ts).first?.util, 30)
    }

    func testQueryReturnsRowsInAscendingOrder() throws {
        let store = try UsageStore(url: dbURL)
        let base = Date(timeIntervalSince1970: 1_700_000_000)
        let r = base.addingTimeInterval(3600)
        store.insert(samples: [
            UsageSample(ts: base.addingTimeInterval(60), bucket: .fiveHour, util: 5, resetsAt: r),
            UsageSample(ts: base.addingTimeInterval(0),  bucket: .fiveHour, util: 1, resetsAt: r),
            UsageSample(ts: base.addingTimeInterval(30), bucket: .fiveHour, util: 3, resetsAt: r)
        ])
        let rows = store.query(bucket: .fiveHour, from: base, to: base.addingTimeInterval(120))
        XCTAssertEqual(rows.map(\.util), [1, 3, 5])
    }
}
