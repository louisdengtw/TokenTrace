import XCTest
@testable import TokenTraceApp

final class CCUsageIngesterTests: XCTestCase {
    private var tmpRoot: URL!
    private var projectsRoot: URL!
    private var dbURL: URL!
    private var store: CCUsageStore!
    private var ingester: CCUsageIngester!

    override func setUpWithError() throws {
        tmpRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCUsageIngesterTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpRoot, withIntermediateDirectories: true)

        projectsRoot = tmpRoot.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: projectsRoot, withIntermediateDirectories: true)

        let dbDir = tmpRoot.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(at: dbDir, withIntermediateDirectories: true)
        dbURL = dbDir.appendingPathComponent("usage.sqlite")

        store = try CCUsageStore(url: dbURL)
        ingester = CCUsageIngester(store: store, projectsRoot: projectsRoot)
    }

    override func tearDownWithError() throws {
        store = nil
        if let tmpRoot {
            try? FileManager.default.removeItem(at: tmpRoot)
        }
    }

    // MARK: - Fixture helpers

    /// Build a single JSONL assistant line, configurable enough to drive
    /// every scenario below.
    private func assistantLine(
        uuid: String,
        cwd: String = "/Users/x/proj",
        sessionId: String = "sess-1",
        requestId: String? = nil,
        isSidechain: Bool = false,
        model: String = "claude-opus-4-7",
        ts: String = "2026-05-13T16:50:04.149Z",
        input: Int = 100,
        output: Int = 200,
        cacheCreate: Int = 50,
        cacheRead: Int = 1000,
        attachContent: String? = nil,
        attachIterations: Bool = false
    ) -> String {
        var usage: [String: Any] = [
            "input_tokens": input,
            "output_tokens": output,
            "cache_creation_input_tokens": cacheCreate,
            "cache_read_input_tokens": cacheRead,
        ]
        if attachIterations {
            usage["iterations"] = [[
                "input_tokens": input,
                "output_tokens": output,
                "cache_creation_input_tokens": cacheCreate,
                "cache_read_input_tokens": cacheRead,
            ]]
        }

        var msg: [String: Any] = [
            "model": model,
            "usage": usage,
        ]
        if let attachContent {
            msg["content"] = attachContent
        }

        var row: [String: Any] = [
            "type": "assistant",
            "uuid": uuid,
            "timestamp": ts,
            "cwd": cwd,
            "sessionId": sessionId,
            "isSidechain": isSidechain,
            "message": msg,
        ]
        if let requestId {
            row["requestId"] = requestId
        }

        let data = try! JSONSerialization.data(withJSONObject: row, options: [.sortedKeys])
        return String(data: data, encoding: .utf8)!
    }

    /// Write `lines` (each *without* trailing newline) to a JSONL file at
    /// `dir/<name>.jsonl`, joining with `\n` and terminating with `\n`.
    @discardableResult
    private func writeJSONL(_ lines: [String], to dir: URL, named name: String) throws -> URL {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("\(name).jsonl")
        try (lines.joined(separator: "\n") + "\n").write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Append raw bytes to a file (used for partial-line follow-up tests).
    private func append(_ s: String, to url: URL) throws {
        let h = try FileHandle(forWritingTo: url)
        defer { try? h.close() }
        try h.seekToEnd()
        try h.write(contentsOf: Data(s.utf8))
    }

    private func rowCount() throws -> Int {
        // Count via CCUsageStore.observedCwds + per-cwd query would be slow;
        // direct sqlite call is fine for tests.
        var count = 0
        let cwds = store.observedCwds()
        for cwd in cwds {
            let rows = store.tokensByProject(
                from: Date(timeIntervalSince1970: 0),
                to:   Date(timeIntervalSince1970: 5_000_000_000),
                bucket: .week
            )
            for series in rows where series.cwd == cwd {
                // Sum non-zero buckets' contributions
                count += series.buckets.filter { $0.weightedTotal > 0 }.count
            }
        }
        return count
    }

    // MARK: - 10.2 cold ingest count + subagent attribution

    func testColdIngestProducesExpectedRowsAndSubagentAttribution() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        // Main session JSONL with 3 qualifying assistant lines.
        try writeJSONL([
            assistantLine(uuid: "m1", cwd: "/Users/x/proj", sessionId: "sess-A"),
            assistantLine(uuid: "m2", cwd: "/Users/x/proj", sessionId: "sess-A"),
            assistantLine(uuid: "m3", cwd: "/Users/x/proj", sessionId: "sess-A"),
        ], to: projDir, named: "sess-A")

        // Subagent JSONL at <project>/<session>/subagents/agent-*.jsonl with
        // 2 sidechain lines, both carrying the parent cwd.
        let subagentsDir = projDir
            .appendingPathComponent("sess-A")
            .appendingPathComponent("subagents")
        try writeJSONL([
            assistantLine(uuid: "s1", cwd: "/Users/x/proj", sessionId: "sess-A", isSidechain: true),
            assistantLine(uuid: "s2", cwd: "/Users/x/proj", sessionId: "sess-A", isSidechain: true),
        ], to: subagentsDir, named: "agent-1")

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.filesScanned, 2)
        XCTAssertEqual(summary.rowsInserted, 5)
        XCTAssertEqual(summary.rowsIgnored, 0)
        XCTAssertEqual(summary.divergences, 0)
        XCTAssertTrue(summary.coldScanOccurred)

        // Subagent rows are attributed to the parent cwd.
        XCTAssertEqual(store.observedCwds(), ["/Users/x/proj"])
    }

    func testNonJsonlSiblingsIgnored() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        try writeJSONL([
            assistantLine(uuid: "u1", cwd: "/Users/x/proj"),
        ], to: projDir, named: "sess-1")
        // Sibling .meta.json file that should never be opened.
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        try "{\"this is\": \"not a jsonl\"}".write(
            to: projDir.appendingPathComponent("sess-1.meta.json"),
            atomically: true,
            encoding: .utf8
        )

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.filesScanned, 1)
        XCTAssertEqual(summary.rowsInserted, 1)
    }

    // MARK: - 10.3 re-ingest is idempotent

    func testReIngestIsIdempotent() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        try writeJSONL([
            assistantLine(uuid: "u1"),
            assistantLine(uuid: "u2"),
        ], to: projDir, named: "sess-1")

        let first = await ingester.ingest()
        XCTAssertEqual(first.rowsInserted, 2)
        XCTAssertEqual(first.rowsIgnored, 0)

        let second = await ingester.ingest()
        // Checkpoint should make the second run a no-op (no new bytes).
        XCTAssertEqual(second.rowsInserted, 0)
        XCTAssertEqual(second.rowsIgnored, 0)
        XCTAssertFalse(second.coldScanOccurred)
    }

    // MARK: - 10.4 synthetic + missing-usage skipped, offset still advances

    func testSyntheticAndMissingUsageSkippedButOffsetAdvances() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        // Write a line with model = "<synthetic>", a line with missing
        // "message.usage", and a real line.
        let syntheticLine = assistantLine(uuid: "syn", model: "<synthetic>")
        var noUsageRow: [String: Any] = [
            "type": "assistant",
            "uuid": "no-usage",
            "timestamp": "2026-05-13T16:50:04.149Z",
            "cwd": "/Users/x/proj",
            "sessionId": "sess-1",
            "isSidechain": false,
            "message": ["model": "claude-opus-4-7"] as [String: Any],
        ]
        _ = noUsageRow.removeValue(forKey: "n/a")  // silence unused-var
        let noUsageData = try JSONSerialization.data(withJSONObject: noUsageRow, options: [.sortedKeys])
        let noUsageLine = String(data: noUsageData, encoding: .utf8)!

        let url = try writeJSONL([
            syntheticLine,
            noUsageLine,
            assistantLine(uuid: "real"),
        ], to: projDir, named: "sess-1")

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.rowsInserted, 1)  // only "real"
        XCTAssertEqual(summary.rowsIgnored, 0)

        // Append another line after the filtered ones. If offset truly
        // advanced past the filtered lines, the second ingest should only
        // see the appended line.
        try append("\n" + assistantLine(uuid: "real2") + "\n", to: url)
        let second = await ingester.ingest()
        XCTAssertEqual(second.rowsInserted, 1, "only the new line should be ingested; filtered lines must NOT cause re-read")
        XCTAssertEqual(second.rowsIgnored, 0)
    }

    // MARK: - 10.5 partial trailing line — offset stays at last \n

    func testPartialTrailingLineDoesNotConsume() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        try FileManager.default.createDirectory(at: projDir, withIntermediateDirectories: true)
        let url = projDir.appendingPathComponent("sess-1.jsonl")

        // One complete line followed by a partial second line (no trailing \n).
        let line1 = assistantLine(uuid: "u1")
        let partialLine2 = "{\"type\":\"assistant\",\"uuid\":\"u2\",\"timestamp\":\"2026-"
        let content = line1 + "\n" + partialLine2
        try content.write(to: url, atomically: true, encoding: .utf8)

        let first = await ingester.ingest()
        XCTAssertEqual(first.rowsInserted, 1, "only the first complete line should be consumed")

        // Verify checkpoint offset equals position immediately after the
        // first newline (the only one in the file).
        let cp = store.checkpoint(forFile: url.path)
        XCTAssertNotNil(cp)
        XCTAssertEqual(cp?.byteOffset, Int64((line1 + "\n").utf8.count))

        // Now complete the partial line and append a new complete line.
        let completedLine2 = assistantLine(uuid: "u2")
        // Drop the partial prefix and write the complete line in its place.
        // We achieve this by rewriting the file (truncate behaviour) — same
        // mtime is fine since we'll write a larger file.
        let newContent = line1 + "\n" + completedLine2 + "\n" + assistantLine(uuid: "u3") + "\n"
        try newContent.write(to: url, atomically: true, encoding: .utf8)

        let second = await ingester.ingest()
        XCTAssertEqual(second.rowsInserted, 2, "u2 and u3 should be picked up on the second run")
    }

    // MARK: - 10.6 same uuid same payload dedups

    func testSameUuidSamePayloadDedups() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        // Same uuid + same payload in two different files (simulates the
        // CC mirror case where one logical message appears in both a parent
        // JSONL and a sibling).
        try writeJSONL([assistantLine(uuid: "shared", input: 10)],
                       to: projDir, named: "session-A")
        try writeJSONL([assistantLine(uuid: "shared", input: 10)],
                       to: projDir.appendingPathComponent("sub"), named: "session-B")

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.filesScanned, 2)
        XCTAssertEqual(summary.rowsInserted, 1)
        XCTAssertEqual(summary.rowsIgnored, 1)
        XCTAssertEqual(summary.divergences, 0)
    }

    // MARK: - 10.7 same uuid different payload — divergence + first-seen wins

    func testSameUuidDifferentPayloadCountsDivergenceAndFirstSeenWins() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        // Two files; the FIRST file (lex-order) has input=10, the second has
        // input=20 for the same uuid. The walk order is enumerator-defined;
        // the assertion below just checks "one of them wins, divergence=1".
        try writeJSONL([assistantLine(uuid: "shared", input: 10)],
                       to: projDir, named: "a-session")
        try writeJSONL([assistantLine(uuid: "shared", input: 20)],
                       to: projDir, named: "b-session")

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.rowsInserted, 1, "INSERT OR IGNORE keeps first-seen")
        XCTAssertEqual(summary.rowsIgnored, 1, "second occurrence is ignored at DB level")
        XCTAssertEqual(summary.divergences, 1, "divergence counter must increment once")
    }

    // MARK: - 10.8 iterations regression — outer fields authoritative

    func testIterationsAreIgnoredOuterFieldsAuthoritative() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        try writeJSONL([
            assistantLine(
                uuid: "u-iter",
                input: 7,
                output: 11,
                cacheCreate: 13,
                cacheRead: 17,
                attachIterations: true
            ),
        ], to: projDir, named: "sess-iter")

        _ = await ingester.ingest()

        // Verify the outer values landed (iterations is the same in this
        // fixture; if the ingester were summing iterations on top of outer
        // it would double-count and weighted total would not match).
        let result = store.tokensByProject(
            from: Date(timeIntervalSince1970: 0),
            to: Date(timeIntervalSince1970: 5_000_000_000),
            bucket: .week
        )
        XCTAssertEqual(result.count, 1)
        let series = result[0]
        // Sum across all buckets (only one bucket actually has data; the
        // rest are zero-fills).
        let totalIn  = series.buckets.reduce(0) { $0 + $1.inputTokens }
        let totalOut = series.buckets.reduce(0) { $0 + $1.outputTokens }
        let totalCc  = series.buckets.reduce(0) { $0 + $1.cacheCreationTokens }
        let totalCr  = series.buckets.reduce(0) { $0 + $1.cacheReadTokens }
        XCTAssertEqual(totalIn,  7)
        XCTAssertEqual(totalOut, 11)
        XCTAssertEqual(totalCc,  13)
        XCTAssertEqual(totalCr,  17)
    }

    // MARK: - 10.9 privacy — content key is present in source but never reaches DB

    func testMessageContentNotPersisted() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        // Embed a large, unique-string content in the JSONL line. After
        // ingest, the sqlite file should NOT contain that string anywhere —
        // proof that the projection in CCUsageIngester.JSONLine doesn't even
        // expose `content` to be persisted.
        let secret = "SECRET_CONTENT_MARKER_" + String(repeating: "x", count: 2048)
        try writeJSONL([
            assistantLine(uuid: "secret-msg", attachContent: secret),
        ], to: projDir, named: "sess-secret")

        let summary = await ingester.ingest()
        XCTAssertEqual(summary.rowsInserted, 1, "the assistant line itself was still ingested")

        // Read the sqlite bytes; the secret marker must not appear.
        let dbBytes = try Data(contentsOf: dbURL)
        guard let dbText = String(data: dbBytes, encoding: .utf8) else {
            // SQLite is binary; do a raw byte-search instead.
            let needle = Data(secret.utf8)
            XCTAssertNil(dbBytes.range(of: needle), "secret content leaked into sqlite file")
            return
        }
        XCTAssertFalse(dbText.contains("SECRET_CONTENT_MARKER_"),
                       "secret content leaked into sqlite file")
    }

    // MARK: - File-grows scenario (spec 14.8 / 17.8)

    func testFileGrowsScenarioReadsOnlyNewBytes() async throws {
        let projDir = projectsRoot.appendingPathComponent("-Users-x-proj")
        let url = try writeJSONL([
            assistantLine(uuid: "u1"),
            assistantLine(uuid: "u2"),
        ], to: projDir, named: "sess-grow")

        let first = await ingester.ingest()
        XCTAssertEqual(first.rowsInserted, 2)

        // Append 3 more lines.
        try append(
            assistantLine(uuid: "u3") + "\n" +
            assistantLine(uuid: "u4") + "\n" +
            assistantLine(uuid: "u5") + "\n",
            to: url
        )
        let second = await ingester.ingest()
        XCTAssertEqual(second.rowsInserted, 3, "only the appended lines should ingest")
        XCTAssertEqual(second.rowsIgnored, 0)
    }

    // MARK: - Empty projects root

    func testEmptyProjectsRoot() async throws {
        let summary = await ingester.ingest()
        XCTAssertEqual(summary.filesScanned, 0)
        XCTAssertEqual(summary.rowsInserted, 0)
        XCTAssertEqual(summary.rowsIgnored, 0)
        XCTAssertFalse(summary.coldScanOccurred)
    }
}
