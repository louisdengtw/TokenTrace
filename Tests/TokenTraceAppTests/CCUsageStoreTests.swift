import XCTest
@testable import TokenTraceApp

final class CCUsageStoreTests: XCTestCase {
    private var dbURL: URL!
    private var store: CCUsageStore!

    // Day-aligned base: floor of 1_700_006_400 is itself (it sits exactly on
    // a UTC midnight). Days are 0-indexed: day(0) is that boundary,
    // day(1) one calendar day later, etc.
    private let dayBoundary: TimeInterval = 1_700_006_400

    override func setUpWithError() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CCUsageStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        dbURL = dir.appendingPathComponent("usage.sqlite")
        store = try CCUsageStore(url: dbURL)
    }

    override func tearDownWithError() throws {
        store = nil
        if let dbURL {
            try? FileManager.default.removeItem(at: dbURL.deletingLastPathComponent())
        }
    }

    // MARK: - Helpers

    private func day(_ d: Int) -> Date {
        Date(timeIntervalSince1970: dayBoundary + Double(d * 86400))
    }

    private func msg(
        _ uuid: String,
        cwd: String,
        day d: Int,
        input: Int = 100,
        output: Int = 200,
        cacheCreate: Int = 0,
        cacheRead: Int = 0,
        sidechain: Bool = false
    ) -> CCMessage {
        CCMessage(
            uuid: uuid,
            ts: day(d),  // exact day boundary; floor → day(d)
            cwd: cwd,
            model: "claude-opus-4-7",
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            sessionId: "sess-\(uuid)",
            requestId: nil,
            isSidechain: sidechain,
            filePath: "/fake/\(cwd.hashValue).jsonl"
        )
    }

    // MARK: - insertMessages (8.2)

    func testInsertMessagesReturnsInsertedAndIgnoredCounts() {
        let r1 = msg("u1", cwd: "/a", day: 0)
        let r2 = msg("u2", cwd: "/a", day: 1)
        let result1 = store.insertMessages([r1, r2])
        XCTAssertEqual(result1.inserted, 2)
        XCTAssertEqual(result1.ignored, 0)

        // Re-insert same uuids → both ignored.
        let result2 = store.insertMessages([r1, r2])
        XCTAssertEqual(result2.inserted, 0)
        XCTAssertEqual(result2.ignored, 2)

        // Mix of new + duplicate → 1 inserted, 1 ignored.
        let r3 = msg("u3", cwd: "/b", day: 0)
        let result3 = store.insertMessages([r1, r3])
        XCTAssertEqual(result3.inserted, 1)
        XCTAssertEqual(result3.ignored, 1)
    }

    func testInsertEmptyIsNoOp() {
        let result = store.insertMessages([])
        XCTAssertEqual(result.inserted, 0)
        XCTAssertEqual(result.ignored, 0)
    }

    // MARK: - tokensByProject zero-fill (8.5 / 8.6)

    func testTwoProjectsZeroFillFiveDayRange() {
        // Project /a: days 0, 1, 2
        // Project /b: days 1, 2, 3
        // Range: days 0..=4 (5 boundaries)
        // Expected: both series have 5 buckets each, with zero where absent.
        let inserts: [CCMessage] = [
            msg("a0", cwd: "/a", day: 0),
            msg("a1", cwd: "/a", day: 1),
            msg("a2", cwd: "/a", day: 2),
            msg("b1", cwd: "/b", day: 1),
            msg("b2", cwd: "/b", day: 2),
            msg("b3", cwd: "/b", day: 3),
        ]
        _ = store.insertMessages(inserts)

        let result = store.tokensByProject(
            from: day(0),
            to: day(4),
            bucket: .day
        )
        XCTAssertEqual(result.count, 2)
        for series in result {
            XCTAssertEqual(series.buckets.count, 5, "expected 5 zero-filled buckets for \(series.cwd)")
            // Verify ts boundaries are day-aligned
            for (i, bkt) in series.buckets.enumerated() {
                XCTAssertEqual(bkt.ts, day(i))
            }
        }
        let aSeries = try? XCTUnwrap(result.first { $0.cwd == "/a" })
        let bSeries = try? XCTUnwrap(result.first { $0.cwd == "/b" })

        // /a has data on days 0,1,2 → non-zero; days 3,4 → zero
        XCTAssertGreaterThan(aSeries?.buckets[0].inputTokens ?? 0, 0)
        XCTAssertGreaterThan(aSeries?.buckets[1].inputTokens ?? 0, 0)
        XCTAssertGreaterThan(aSeries?.buckets[2].inputTokens ?? 0, 0)
        XCTAssertEqual(aSeries?.buckets[3].inputTokens, 0)
        XCTAssertEqual(aSeries?.buckets[4].inputTokens, 0)

        // /b symmetric
        XCTAssertEqual(bSeries?.buckets[0].inputTokens, 0)
        XCTAssertGreaterThan(bSeries?.buckets[1].inputTokens ?? 0, 0)
        XCTAssertGreaterThan(bSeries?.buckets[2].inputTokens ?? 0, 0)
        XCTAssertGreaterThan(bSeries?.buckets[3].inputTokens ?? 0, 0)
        XCTAssertEqual(bSeries?.buckets[4].inputTokens, 0)
    }

    func testProjectOutsideRangeIsOmitted() {
        // /c has rows only at day 10; query day 0..=4 — /c must not appear.
        _ = store.insertMessages([
            msg("c0", cwd: "/a", day: 0),
            msg("c1", cwd: "/c", day: 10),
        ])
        let result = store.tokensByProject(from: day(0), to: day(4), bucket: .day)
        XCTAssertEqual(result.map(\.cwd), ["/a"])
    }

    func testEmptyRangeReturnsEmpty() {
        _ = store.insertMessages([msg("x", cwd: "/a", day: 0)])
        let result = store.tokensByProject(from: day(10), to: day(15), bucket: .day)
        XCTAssertEqual(result, [])
    }

    func testInvertedRangeReturnsEmpty() {
        _ = store.insertMessages([msg("x", cwd: "/a", day: 5)])
        let result = store.tokensByProject(from: day(10), to: day(5), bucket: .day)
        XCTAssertEqual(result, [])
    }

    // MARK: - Alias merge (8.4)

    func testAliasMergesTwoCwdsIntoOneSeries() {
        _ = store.insertMessages([
            msg("a0", cwd: "/path/to/main",      day: 0, input: 100),
            msg("a1", cwd: "/path/to/main",      day: 1, input: 200),
            msg("b0", cwd: "/path/to/worktree-x", day: 0, input: 50),
            msg("b1", cwd: "/path/to/worktree-x", day: 2, input: 75),
        ])
        store.setAlias(cwd: "/path/to/main",       displayName: "MyProject")
        store.setAlias(cwd: "/path/to/worktree-x", displayName: "MyProject")

        let result = store.tokensByProject(from: day(0), to: day(2), bucket: .day)
        XCTAssertEqual(result.count, 1, "two cwds sharing an alias should merge into one series")
        let s = result[0]
        XCTAssertEqual(s.displayName, "MyProject")
        XCTAssertEqual(s.buckets.count, 3)
        // Day 0 = 100 + 50 = 150 input
        XCTAssertEqual(s.buckets[0].inputTokens, 150)
        // Day 1 = 200 (only /path/to/main)
        XCTAssertEqual(s.buckets[1].inputTokens, 200)
        // Day 2 = 75 (only /path/to/worktree-x)
        XCTAssertEqual(s.buckets[2].inputTokens, 75)
    }

    func testAliasOverridesSynthesisedLabel() {
        _ = store.insertMessages([msg("x", cwd: "/Users/x/workspace/Foo", day: 0)])
        // Default depth=1 → synthesised label is just the last component.
        var result = store.tokensByProject(from: day(0), to: day(0), bucket: .day)
        XCTAssertEqual(result.first?.displayName, "Foo")
        // With alias → alias used.
        store.setAlias(cwd: "/Users/x/workspace/Foo", displayName: "MyFoo")
        result = store.tokensByProject(from: day(0), to: day(0), bucket: .day)
        XCTAssertEqual(result.first?.displayName, "MyFoo")
    }

    func testSynthesisedLabelAtDepthTwo() {
        _ = store.insertMessages([msg("x", cwd: "/Users/x/workspace/Foo", day: 0)])
        let options = CCUsageStore.QueryOptions(displayNameDepth: 2, mergeWorktrees: true, workspaceRoot: nil)
        let result = store.tokensByProject(from: day(0), to: day(0), bucket: .day, options: options)
        XCTAssertEqual(result.first?.displayName, "workspace/Foo")
    }

    func testSynthesisedLabelOnSingleComponentCwd() {
        _ = store.insertMessages([msg("x", cwd: "/foo", day: 0)])
        let result = store.tokensByProject(from: day(0), to: day(0), bucket: .day)
        // depth=1, single non-empty path component → that component as label.
        XCTAssertEqual(result.first?.displayName, "foo")
    }

    // MARK: - Worktree fold

    func testWorktreesMergeIntoParentByDefault() {
        // Four sources for the same logical project: the parent itself, a
        // .worktree subdirectory, a .worktrees agent worktree, AND a
        // .claude/worktrees/agent-<uuid> path (Claude Code agent task
        // system's worktree convention).
        _ = store.insertMessages([
            msg("a", cwd: "/Users/x/repo", day: 0, input: 100),
            msg("b", cwd: "/Users/x/repo/.worktree/branch", day: 1, input: 200),
            msg("c", cwd: "/Users/x/repo/.worktrees/agent-uuid", day: 2, input: 300),
            msg("d", cwd: "/Users/x/repo/.claude/worktrees/agent-aaaa", day: 3, input: 400),
        ])
        // Default options have mergeWorktrees = true.
        let result = store.tokensByProject(from: day(0), to: day(3), bucket: .day)
        XCTAssertEqual(result.count, 1, "all four cwds should fold into one row")
        let s = result[0]
        XCTAssertEqual(s.displayName, "repo", "displayName uses the parent's last component")
        let totalInput = s.buckets.reduce(0) { $0 + $1.inputTokens }
        XCTAssertEqual(totalInput, 1000, "summed across four sources")
    }

    func testWorktreesKeepSeparateWhenDisabled() {
        _ = store.insertMessages([
            msg("a", cwd: "/Users/x/repo", day: 0),
            msg("b", cwd: "/Users/x/repo/.worktree/branch", day: 0),
        ])
        let opts = CCUsageStore.QueryOptions(displayNameDepth: 1, mergeWorktrees: false, workspaceRoot: nil)
        let result = store.tokensByProject(from: day(0), to: day(0), bucket: .day, options: opts)
        XCTAssertEqual(result.count, 2, "worktree fold disabled → separate rows")
    }

    func testWorkspaceRootFoldsAnyNestedPath() {
        // Any cwd under the configured workspace root folds to <root>/<first-segment>,
        // regardless of whether the nested portion looks like a worktree.
        _ = store.insertMessages([
            msg("a", cwd: "/Users/x/workspace/Foo",                                 day: 0, input: 100),
            msg("b", cwd: "/Users/x/workspace/Foo/scripts/deploy",                  day: 0, input: 200),
            msg("c", cwd: "/Users/x/workspace/Foo/.worktree/branch",                day: 0, input: 300),
            msg("d", cwd: "/Users/x/workspace/Foo/.claude/worktrees/agent-abc",     day: 0, input: 400),
            msg("e", cwd: "/Users/x/workspace/Bar/anything",                        day: 0, input: 50),
            msg("f", cwd: "/opt/cisco/anyconnect/bin",                              day: 0, input: 10),
        ])
        let opts = CCUsageStore.QueryOptions(
            displayNameDepth: 1,
            mergeWorktrees: true,
            workspaceRoot: "/Users/x/workspace"
        )
        let result = store.tokensByProject(from: day(0), to: day(0), bucket: .day, options: opts)
        // Expected: Foo (folds a/b/c/d), Bar (folds e), and the /opt path
        // unchanged because it's outside the workspace root.
        XCTAssertEqual(result.count, 3)
        let foo = try? XCTUnwrap(result.first { $0.displayName == "Foo" })
        XCTAssertEqual(foo?.buckets.reduce(0) { $0 + $1.inputTokens }, 1000)
        let bar = try? XCTUnwrap(result.first { $0.displayName == "Bar" })
        XCTAssertEqual(bar?.buckets.reduce(0) { $0 + $1.inputTokens }, 50)
    }

    func testWorkspaceRootPathExactlyMatchesProjectRoot() {
        // A cwd that IS the project root (one segment past the workspace
        // root, no deeper path) stays as itself.
        _ = store.insertMessages([
            msg("a", cwd: "/Users/x/workspace/Foo", day: 0, input: 100),
        ])
        let opts = CCUsageStore.QueryOptions(
            displayNameDepth: 1,
            mergeWorktrees: true,
            workspaceRoot: "/Users/x/workspace"
        )
        let result = store.tokensByProject(from: day(0), to: day(0), bucket: .day, options: opts)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].cwd, "/Users/x/workspace/Foo")
    }

    func testWorktreeFoldRespectsAliasOnParent() {
        _ = store.insertMessages([
            msg("a", cwd: "/Users/x/repo",                day: 0, input: 100),
            msg("b", cwd: "/Users/x/repo/.worktree/branch", day: 1, input: 200),
        ])
        // Set alias on the parent — both rows should inherit it via the fold.
        store.setAlias(cwd: "/Users/x/repo", displayName: "Repo")
        let result = store.tokensByProject(from: day(0), to: day(1), bucket: .day)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].displayName, "Repo")
    }

    // MARK: - Cross-source oldest (8.7)

    func testOldestCCMessageTimestampEmpty() {
        XCTAssertNil(store.oldestCCMessageTimestamp())
    }

    func testOldestCCMessageTimestampPopulated() {
        _ = store.insertMessages([
            msg("late", cwd: "/a", day: 5),
            msg("early", cwd: "/a", day: 0),
            msg("mid", cwd: "/a", day: 3),
        ])
        let oldest = store.oldestCCMessageTimestamp()
        XCTAssertEqual(oldest, day(0))
    }

    // MARK: - Aliases CRUD (8.8)

    func testAliasesEmptyByDefault() {
        XCTAssertTrue(store.aliases().isEmpty)
    }

    func testSetAliasRoundTrip() {
        store.setAlias(cwd: "/a", displayName: "Alpha")
        store.setAlias(cwd: "/b", displayName: "Beta")
        let aliases = store.aliases()
        XCTAssertEqual(aliases["/a"], "Alpha")
        XCTAssertEqual(aliases["/b"], "Beta")
    }

    func testSetAliasReplacesExisting() {
        store.setAlias(cwd: "/a", displayName: "Alpha")
        store.setAlias(cwd: "/a", displayName: "AlphaRenamed")
        XCTAssertEqual(store.aliases()["/a"], "AlphaRenamed")
    }

    func testRemoveAlias() {
        store.setAlias(cwd: "/a", displayName: "Alpha")
        store.removeAlias(cwd: "/a")
        XCTAssertNil(store.aliases()["/a"])
    }

    func testRemoveAliasOnUnknownCwdIsNoOp() {
        store.removeAlias(cwd: "/never-set")
        XCTAssertTrue(store.aliases().isEmpty)
    }

    // MARK: - observedCwds (8.9)

    func testObservedCwdsEmpty() {
        XCTAssertEqual(store.observedCwds(), [])
    }

    func testObservedCwdsReturnsDistinctSorted() {
        _ = store.insertMessages([
            msg("u1", cwd: "/c", day: 0),
            msg("u2", cwd: "/a", day: 0),
            msg("u3", cwd: "/c", day: 1),  // dup cwd
            msg("u4", cwd: "/b", day: 0),
        ])
        XCTAssertEqual(store.observedCwds(), ["/a", "/b", "/c"])
    }
}
