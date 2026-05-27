import XCTest
@testable import TokenTraceApp

final class CCReportGeneratorTests: XCTestCase {
    private var dbURL: URL!
    private var ccStore: CCUsageStore!
    private var usageStore: UsageStore!
    private var generator: CCReportGenerator!

    private let dayBoundary: TimeInterval = 1_700_006_400

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCReportGeneratorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("usage.sqlite")
        ccStore = try CCUsageStore(url: dbURL)
        usageStore = try UsageStore(url: dbURL)
        generator = CCReportGenerator(ccStore: ccStore, usageStore: usageStore)
    }

    override func tearDownWithError() throws {
        ccStore = nil
        usageStore = nil
        generator = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
    }

    // MARK: - Fixtures

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSince1970: dayBoundary + Double(d * 86400))
    }

    private func msg(_ uuid: String, cwd: String, day d: Int, input: Int = 100, output: Int = 200) -> CCMessage {
        CCMessage(
            uuid: uuid,
            ts: day(d),
            cwd: cwd,
            model: "claude-opus-4-7",
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: 50,
            cacheReadTokens: 1000,
            sessionId: "s-\(uuid)",
            requestId: nil,
            isSidechain: false,
            filePath: "/fake/\(cwd.hashValue).jsonl"
        )
    }

    private func sample(_ ts: Date, util: Double, bucket: Bucket = .fiveHour) -> UsageSample {
        UsageSample(ts: ts, bucket: bucket, util: util, resetsAt: ts)
    }

    private func defaultRequest(includeOverlay: Bool = true, includeTotals: Bool = true) -> CCReportRequest {
        CCReportRequest(
            title: "Test Report",
            range: .custom(from: day(0), to: day(5)),
            includeOverlay: includeOverlay,
            includeProjectTotals: includeTotals
        )
    }

    // MARK: - Sentinel substitution

    func testAllSentinelsAreSubstituted() throws {
        _ = ccStore.insertMessages([
            msg("a", cwd: "/Users/x/workspace/Foo", day: 0),
            msg("b", cwd: "/Users/x/workspace/Foo", day: 1),
        ])
        usageStore.insert(samples: [
            sample(day(0).addingTimeInterval(3600), util: 25),
            sample(day(1).addingTimeInterval(3600), util: 60),
        ])

        let html = try generator.generateHTML(
            request: defaultRequest(),
            now: day(5),
            dbPath: "/tmp/test.sqlite"
        )

        // No sentinel tokens may remain anywhere in the output.
        for token in [
            "__TITLE__", "__DATE_RANGE__", "__DURATION_DAYS__",
            "__GENERATED_AT__", "__DB_PATH__",
            "__STATS_JSON__", "__SERIES_JSON__", "__PROJECT_TOTALS_JSON__",
            "__INCLUDE_OVERLAY__", "__INCLUDE_TOTALS__",
            "__CHART_JS__",
        ] {
            XCTAssertFalse(html.contains(token), "leftover sentinel: \(token)")
        }
        // Title is substituted into both <title> tag and masthead h1.
        XCTAssertTrue(html.contains("Test Report"))
        // dbPath shows up in the footer.
        XCTAssertTrue(html.contains("/tmp/test.sqlite"))
    }

    func testTitleIsHTMLEscaped() throws {
        _ = ccStore.insertMessages([msg("a", cwd: "/x/y", day: 0)])
        let req = CCReportRequest(
            title: "<script>alert('xss')</script>",
            range: .custom(from: day(0), to: day(1)),
            includeOverlay: false,
            includeProjectTotals: false
        )
        let html = try generator.generateHTML(request: req, now: day(2), dbPath: "/tmp/a.sqlite")
        XCTAssertFalse(html.contains("<script>alert('xss')</script>"),
                       "title should be HTML-escaped before substitution")
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    // MARK: - Include toggles

    func testIncludeOverlayFlagInjectsBoolean() throws {
        _ = ccStore.insertMessages([msg("a", cwd: "/x/y", day: 0)])
        usageStore.insert(samples: [sample(day(0), util: 50)])

        let withOverlay = try generator.generateHTML(
            request: defaultRequest(includeOverlay: true),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertTrue(withOverlay.contains("const INCLUDE_OVERLAY = true;"))

        let withoutOverlay = try generator.generateHTML(
            request: defaultRequest(includeOverlay: false),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertTrue(withoutOverlay.contains("const INCLUDE_OVERLAY = false;"))
    }

    func testIncludeTotalsFlagInjectsBoolean() throws {
        _ = ccStore.insertMessages([msg("a", cwd: "/x/y", day: 0)])

        let withTotals = try generator.generateHTML(
            request: defaultRequest(includeTotals: true),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertTrue(withTotals.contains("const INCLUDE_TOTALS = true;"))

        let withoutTotals = try generator.generateHTML(
            request: defaultRequest(includeTotals: false),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertTrue(withoutTotals.contains("const INCLUDE_TOTALS = false;"))
    }

    // MARK: - Data shape

    func testSeriesJsonContainsProjectBuckets() throws {
        _ = ccStore.insertMessages([
            msg("a", cwd: "/x/y", day: 0, input: 10, output: 20),
            msg("b", cwd: "/x/y", day: 1, input: 30, output: 40),
        ])

        let html = try generator.generateHTML(
            request: defaultRequest(includeOverlay: false, includeTotals: false),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )

        // Output token weight is 5×, so day 1's outputWeighted should be 200.
        // Without strict JSON parsing in test, we look for a known numeric
        // appearance + the projection field name.
        XCTAssertTrue(html.contains("\"outputWeighted\":200"))
        XCTAssertTrue(html.contains("\"inputWeighted\":30"))
        // Series carries a displayName derived at depth=1 from the cwd.
        XCTAssertTrue(html.contains("\"displayName\":\"y\""))
    }

    func testEmptyRangeStillProducesValidReport() throws {
        // No CC rows, no subscription samples.
        let html = try generator.generateHTML(
            request: defaultRequest(),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        // No sentinels left.
        XCTAssertFalse(html.contains("__SERIES_JSON__"))
        // Stats show "—" for top project since none exists.
        XCTAssertTrue(html.contains("\"topProjectLabel\":\"—\""))
        XCTAssertTrue(html.contains("\"peakUtilLabel\":\"0%\""))
        // Series array empty.
        XCTAssertTrue(html.contains("\"series\":[]"))
    }

    func testTopNGroupingProducesOtherBucket() throws {
        // 10 projects, day 0, each with distinct weighted volumes so order is
        // deterministic. Generator's maxIndividualProjects is 8 → 8 shown +
        // 1 "Other (2)" row.
        var rows: [CCMessage] = []
        for i in 0..<10 {
            rows.append(msg(
                "u\(i)",
                cwd: "/x/proj\(i)",
                day: 0,
                input: (10 - i) * 100  // descending so /x/proj0 is top
            ))
        }
        _ = ccStore.insertMessages(rows)

        let html = try generator.generateHTML(
            request: defaultRequest(includeOverlay: false, includeTotals: true),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertTrue(html.contains("\"displayName\":\"Other (2)\""),
                      "top-N grouping should emit one synthesised Other row")
        XCTAssertTrue(html.contains("\"isOther\":true"),
                      "Other row must carry the isOther flag for the template")
    }

    func testStatsTotalAndTopReflectDataAtDepth1() throws {
        // /x/big has the highest weighted volume; default depth=1 makes its
        // display name just "big".
        _ = ccStore.insertMessages([
            msg("big", cwd: "/Users/x/workspace/big", day: 0, input: 1000, output: 1000),
            msg("sml", cwd: "/Users/x/workspace/small", day: 0, input: 10, output: 10),
        ])

        let html = try generator.generateHTML(
            request: defaultRequest(includeOverlay: false, includeTotals: true),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        // Top label should call out "big" by its depth-1 synthesised name.
        XCTAssertTrue(html.contains("\"topProjectLabel\":\"big "))
    }

    func testTokenSentinelDoesntAccidentallyAppearInTemplate() throws {
        // Sanity: the substituted Chart.js + our JSON payloads should never
        // re-introduce a sentinel string (e.g. via a comment in Chart.js).
        // Run a couple of substitutions and grep the final.
        _ = ccStore.insertMessages([msg("a", cwd: "/x/y", day: 0)])
        let html = try generator.generateHTML(
            request: defaultRequest(),
            now: day(5), dbPath: "/tmp/a.sqlite"
        )
        XCTAssertFalse(html.contains("__SERIES_JSON__"))
        XCTAssertFalse(html.contains("__STATS_JSON__"))
        XCTAssertFalse(html.contains("__PROJECT_TOTALS_JSON__"))
    }
}
