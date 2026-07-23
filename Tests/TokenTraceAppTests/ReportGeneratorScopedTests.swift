import XCTest
@testable import TokenTraceApp

/// Locks the dynamic-scoped-limits report behavior: scoped buckets render
/// their own section with the model name, in canonical order, with the
/// per-model color; legacy Sonnet rows feed the Sonnet section.
final class ReportGeneratorScopedTests: XCTestCase {
    private var dbURL: URL!
    private var store: UsageStore!

    private let base = Date(timeIntervalSince1970: 1_752_000_000)

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ReportGeneratorScopedTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("usage.sqlite")
        store = try UsageStore(url: dbURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
    }

    func testScopedBucketRendersOwnSectionInCanonicalOrder() throws {
        let r = base.addingTimeInterval(3600)
        store.insert(samples: [
            UsageSample(ts: base, bucket: .fiveHour, util: 10, resetsAt: r),
            UsageSample(ts: base, bucket: .sevenDay, util: 20, resetsAt: r),
            UsageSample(ts: base, bucket: .weeklyScoped(model: "Fable"), util: 5, resetsAt: r)
        ])
        try store.executeForTesting("""
        INSERT INTO samples (ts, bucket, util, resets_at)
        VALUES (\(Int(base.timeIntervalSince1970)), 'seven_day_sonnet', 33,
                \(Int(r.timeIntervalSince1970)));
        """)

        let request = ReportRequest(
            title: "Scoped Test",
            range: .custom(from: base.addingTimeInterval(-60), to: base.addingTimeInterval(60)),
            buckets: [.fiveHour, .sevenDay,
                      .weeklyScoped(model: "Fable"), .weeklyScoped(model: "Sonnet")]
        )
        let html = try ReportGenerator(store: store)
            .generateHTML(request: request, now: base.addingTimeInterval(120), dbPath: dbURL.path)

        if let out = ProcessInfo.processInfo.environment["SCOPED_REPORT_DUMP"] {
            try html.write(to: URL(fileURLWithPath: out), atomically: true, encoding: .utf8)
        }

        XCTAssertTrue(html.contains("7-Day Window — Fable"))
        XCTAssertTrue(html.contains("7-Day Window — Sonnet"))
        XCTAssertTrue(html.contains("weekly_scoped:Fable"))
        XCTAssertTrue(html.contains(ScopedSeriesColor.hex(for: "Fable")))
        // Legacy row feeds the Sonnet section's samples ([ts, util] pairs).
        XCTAssertTrue(html.contains("\(Int(base.timeIntervalSince1970) * 1000),33"))

        // Canonical order: fixed windows first, scoped sorted by model name.
        let order = ["5-Hour Window", "7-Day Window\"", "7-Day Window — Fable", "7-Day Window — Sonnet"]
            .compactMap { html.range(of: $0)?.lowerBound }
        XCTAssertEqual(order, order.sorted())
    }
}
