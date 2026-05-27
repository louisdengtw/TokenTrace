import Foundation
import OSLog
import SQLite3

/// Persistence layer for ingested Claude Code messages. Wraps the `cc_message`,
/// `cc_ingest_checkpoint`, and `project_alias` tables. Opens its own sqlite3
/// handle (separate from `UsageStore`'s) on the same DB file; SQLite serialises
/// concurrent connections internally.
final class CCUsageStore {
    private let db: OpaquePointer
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "CCUsageStore")

    private let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1)!, to: sqlite3_destructor_type.self
    )

    // MARK: - Nested types

    /// Aggregation granularity for `tokensByProject`.
    enum TimeBucket: String, Sendable, CaseIterable {
        case hour
        case day
        case week

        /// Number of seconds per bucket. SQLite floor expression is
        /// `(ts / seconds) * seconds`.
        var seconds: Int {
            switch self {
            case .hour: return 3600
            case .day:  return 86400
            // 604800 = 7d. NB: this aligns to Thursday boundaries because the
            // unix epoch (1970-01-01) was a Thursday. Acceptable for v1
            // attribution charts; revisit if ISO-week alignment becomes
            // user-visible.
            case .week: return 604800
            }
        }
    }

    struct ProjectBucket: Equatable, Sendable {
        let ts: Date
        let inputTokens: Int
        let outputTokens: Int
        let cacheCreationTokens: Int
        let cacheReadTokens: Int

        var weightedTotal: Double {
            CCWeightedVolume.weightedTotal(
                input: inputTokens,
                output: outputTokens,
                cacheCreation: cacheCreationTokens,
                cacheRead: cacheReadTokens
            )
        }
    }

    struct ProjectSeries: Equatable, Sendable {
        /// Representative cwd for the series. When alias-merging (or worktree
        /// folding via `QueryOptions.mergeWorktrees`) collapses multiple cwds
        /// into one series, this is the first cwd seen for that group — used
        /// for downstream queries (e.g. `modelBreakdown(forCwd:)`).
        let cwd: String
        let displayName: String
        let buckets: [ProjectBucket]
    }

    /// Controls how `tokensByProject` shapes its output.
    struct QueryOptions: Equatable, Sendable {
        /// Number of trailing path components used when synthesising a
        /// project's display name from its `cwd`. 1 → `"TokenTrace"`,
        /// 2 → `"workspace/TokenTrace"`.
        let displayNameDepth: Int

        /// When true, cwds containing a `.worktree` / `.worktrees` /
        /// `.claude/worktrees` path segment fold into the parent path
        /// during aggregation, so all worktrees of a repo share one row.
        /// Also enables the `workspaceRoot` short-circuit below.
        let mergeWorktrees: Bool

        /// Optional `~`-expanded workspace root. When set AND
        /// `mergeWorktrees` is on, any cwd under this root folds to
        /// `<root>/<first-segment>` regardless of nesting depth. Catches
        /// every kind of nested directory (worktrees, build dirs, scripts,
        /// `.claude/...`) for free without pattern-matching the segment.
        let workspaceRoot: String?

        static let `default` = QueryOptions(
            displayNameDepth: 1,
            mergeWorktrees: true,
            workspaceRoot: nil
        )
    }

    // MARK: - Lifecycle

    init(url: URL) throws {
        var handle: OpaquePointer?
        let result = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let opened = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code=\(result)"
            if let h = handle { sqlite3_close(h) }
            throw UsageStoreError.openFailed(msg)
        }
        self.db = opened
        sqlite3_busy_timeout(db, 200)
        // DDL is idempotent (CREATE IF NOT EXISTS); harmless to re-run even
        // when UsageStore has already executed it on the same file.
        for ddl in Schema.allDDL {
            try execute(ddl)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    // MARK: - Insert (task 8.2)

    /// Insert messages in a single transaction, deduping on `uuid` via
    /// `INSERT OR IGNORE`. Returns counts so the ingester's divergence
    /// counter can attribute correctly.
    @discardableResult
    func insertMessages(_ rows: [CCMessage]) -> (inserted: Int, ignored: Int) {
        guard !rows.isEmpty else { return (0, 0) }

        do {
            try execute("BEGIN IMMEDIATE;")
        } catch {
            log.error("insertMessages: BEGIN failed: \(String(describing: error), privacy: .public)")
            return (0, 0)
        }

        let sql = """
        INSERT OR IGNORE INTO cc_message
            (uuid, ts, cwd, model,
             input_tokens, output_tokens, cache_creation_tokens, cache_read_tokens,
             session_id, request_id, is_sidechain, file_path)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("insertMessages: prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            try? execute("ROLLBACK;")
            return (0, 0)
        }
        defer { sqlite3_finalize(stmt) }

        var inserted = 0
        var ignored = 0

        for r in rows {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)

            sqlite3_bind_text  (stmt, 1,  r.uuid,                       -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64 (stmt, 2,  sqlite3_int64(r.ts.timeIntervalSince1970))
            sqlite3_bind_text  (stmt, 3,  r.cwd,                        -1, SQLITE_TRANSIENT)
            sqlite3_bind_text  (stmt, 4,  r.model,                      -1, SQLITE_TRANSIENT)
            sqlite3_bind_int64 (stmt, 5,  sqlite3_int64(r.inputTokens))
            sqlite3_bind_int64 (stmt, 6,  sqlite3_int64(r.outputTokens))
            sqlite3_bind_int64 (stmt, 7,  sqlite3_int64(r.cacheCreationTokens))
            sqlite3_bind_int64 (stmt, 8,  sqlite3_int64(r.cacheReadTokens))
            sqlite3_bind_text  (stmt, 9,  r.sessionId,                  -1, SQLITE_TRANSIENT)
            if let req = r.requestId {
                sqlite3_bind_text(stmt, 10, req,                        -1, SQLITE_TRANSIENT)
            } else {
                sqlite3_bind_null(stmt, 10)
            }
            sqlite3_bind_int   (stmt, 11, r.isSidechain ? 1 : 0)
            sqlite3_bind_text  (stmt, 12, r.filePath,                   -1, SQLITE_TRANSIENT)

            let step = sqlite3_step(stmt)
            if step != SQLITE_DONE {
                log.error("insertMessages: step failed code=\(step): \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
                continue
            }
            // `sqlite3_changes` returns rows affected by the *last* statement.
            // For INSERT OR IGNORE, this is 1 on insert, 0 on dedup.
            if sqlite3_changes(db) == 1 {
                inserted += 1
            } else {
                ignored += 1
            }
        }

        try? execute("COMMIT;")
        return (inserted, ignored)
    }

    // MARK: - Query (tasks 8.3 / 8.4 / 8.5 / 8.6)

    /// Per-project token aggregates over `[from, to]` at the given bucket
    /// granularity. Results are alias-merged (multiple cwds sharing a display
    /// name collapse into one series with per-bucket sums) and zero-filled
    /// (each returned series has a bucket entry at every boundary in the
    /// range; absent buckets are all-zero). Projects with zero data anywhere
    /// in the range are omitted entirely.
    func tokensByProject(
        from: Date,
        to: Date,
        bucket: TimeBucket,
        options: QueryOptions = .default
    ) -> [ProjectSeries] {
        guard from <= to else { return [] }

        // Single SQL pass: floor ts into bucket boundaries and sum the four
        // token columns per (cwd, bucket).
        let bucketSeconds = bucket.seconds
        let sql = """
        SELECT
            cwd,
            (ts / \(bucketSeconds)) * \(bucketSeconds) AS bucket_ts,
            SUM(input_tokens),
            SUM(output_tokens),
            SUM(cache_creation_tokens),
            SUM(cache_read_tokens)
        FROM cc_message
        WHERE ts >= ? AND ts <= ?
        GROUP BY cwd, bucket_ts
        ORDER BY cwd, bucket_ts;
        """

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("tokensByProject prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, sqlite3_int64(from.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(to.timeIntervalSince1970))

        // First pass: collect raw buckets keyed by cwd. Use Int64 timestamps
        // as the bucket key for exact equality (avoids Date-equality drift).
        var perCwd: [String: [Int64: ProjectBucket]] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cwd       = String(cString: sqlite3_column_text(stmt, 0))
            let bucketTs  = sqlite3_column_int64(stmt, 1)
            let sumIn     = Int(sqlite3_column_int64(stmt, 2))
            let sumOut    = Int(sqlite3_column_int64(stmt, 3))
            let sumCc     = Int(sqlite3_column_int64(stmt, 4))
            let sumCr     = Int(sqlite3_column_int64(stmt, 5))

            let b = ProjectBucket(
                ts: Date(timeIntervalSince1970: TimeInterval(bucketTs)),
                inputTokens: sumIn,
                outputTokens: sumOut,
                cacheCreationTokens: sumCc,
                cacheReadTokens: sumCr
            )
            perCwd[cwd, default: [:]][bucketTs] = b
        }

        if perCwd.isEmpty { return [] }

        // Optional worktree fold: cwds with a `.worktree` / `.worktrees` /
        // `.claude/worktrees` segment, or any cwd nested under a configured
        // workspace root, collapse to the parent path. Done before alias
        // lookup so an alias set on the parent applies to all its worktrees.
        var perEffectiveCwd: [String: (representativeCwd: String, buckets: [Int64: ProjectBucket])] = [:]
        for (cwd, buckets) in perCwd {
            let effective = options.mergeWorktrees ? normaliseForWorktree(cwd, options: options) : cwd
            if var existing = perEffectiveCwd[effective] {
                for (ts, bkt) in buckets {
                    if let prev = existing.buckets[ts] {
                        existing.buckets[ts] = ProjectBucket(
                            ts: prev.ts,
                            inputTokens:         prev.inputTokens         + bkt.inputTokens,
                            outputTokens:        prev.outputTokens        + bkt.outputTokens,
                            cacheCreationTokens: prev.cacheCreationTokens + bkt.cacheCreationTokens,
                            cacheReadTokens:     prev.cacheReadTokens     + bkt.cacheReadTokens
                        )
                    } else {
                        existing.buckets[ts] = bkt
                    }
                }
                perEffectiveCwd[effective] = existing
            } else {
                // Use the normalised path as the representative when a fold
                // collapsed multiple sources (effective != cwd). For non-fold
                // cases this is identical to the original cwd. Tooltip and
                // downstream queries get the parent path, not the
                // first-worktree path.
                perEffectiveCwd[effective] = (representativeCwd: effective, buckets: buckets)
            }
        }

        // Alias resolution + merge-by-displayName.
        let aliasMap = aliases()
        var perDisplay: [String: (key: String, buckets: [Int64: ProjectBucket])] = [:]
        for (effectiveCwd, entry) in perEffectiveCwd {
            let displayName = aliasMap[effectiveCwd]
                ?? synthesiseDisplayName(from: effectiveCwd, depth: options.displayNameDepth)
            if var existing = perDisplay[displayName] {
                for (ts, bkt) in entry.buckets {
                    if let prev = existing.buckets[ts] {
                        existing.buckets[ts] = ProjectBucket(
                            ts: prev.ts,
                            inputTokens:         prev.inputTokens         + bkt.inputTokens,
                            outputTokens:        prev.outputTokens        + bkt.outputTokens,
                            cacheCreationTokens: prev.cacheCreationTokens + bkt.cacheCreationTokens,
                            cacheReadTokens:     prev.cacheReadTokens     + bkt.cacheReadTokens
                        )
                    } else {
                        existing.buckets[ts] = bkt
                    }
                }
                perDisplay[displayName] = existing
            } else {
                perDisplay[displayName] = (key: entry.representativeCwd, buckets: entry.buckets)
            }
        }

        // Zero-fill across all bucket boundaries in [from, to].
        let allBoundaries = bucketBoundaries(from: from, to: to, secondsPerBucket: bucketSeconds)
        var out: [ProjectSeries] = []
        for (displayName, entry) in perDisplay {
            var rendered: [ProjectBucket] = []
            rendered.reserveCapacity(allBoundaries.count)
            for boundary in allBoundaries {
                if let real = entry.buckets[boundary] {
                    rendered.append(real)
                } else {
                    rendered.append(ProjectBucket(
                        ts: Date(timeIntervalSince1970: TimeInterval(boundary)),
                        inputTokens: 0,
                        outputTokens: 0,
                        cacheCreationTokens: 0,
                        cacheReadTokens: 0
                    ))
                }
            }
            out.append(ProjectSeries(
                cwd: entry.key,
                displayName: displayName,
                buckets: rendered
            ))
        }
        // Stable ordering for callers + tests: descending by series total
        // weighted volume, then by cwd ascending as tiebreaker.
        out.sort {
            let aTotal = $0.buckets.reduce(0.0) { $0 + $1.weightedTotal }
            let bTotal = $1.buckets.reduce(0.0) { $0 + $1.weightedTotal }
            if aTotal != bTotal { return aTotal > bTotal }
            return $0.cwd < $1.cwd
        }
        return out
    }

    /// All bucket-floor boundaries from the floor of `from` to the floor of
    /// `to`, inclusive, stepping by `secondsPerBucket`.
    private func bucketBoundaries(from: Date, to: Date, secondsPerBucket: Int) -> [Int64] {
        let startSec = Int64(from.timeIntervalSince1970)
        let endSec   = Int64(to.timeIntervalSince1970)
        let step     = Int64(secondsPerBucket)
        let floorStart = (startSec / step) * step
        let floorEnd   = (endSec / step) * step
        guard floorEnd >= floorStart else { return [] }
        var out: [Int64] = []
        var ts = floorStart
        while ts <= floorEnd {
            out.append(ts)
            ts += step
        }
        return out
    }

    private func synthesiseDisplayName(from cwd: String, depth: Int = 1) -> String {
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let comps = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        let d = max(1, depth)
        guard comps.count >= d else { return cwd }
        return comps.suffix(d).joined(separator: "/")
    }

    /// Strip a worktree segment from `cwd`, returning the parent repo path.
    ///
    /// Resolution order:
    ///   1. If `options.workspaceRoot` is set and `cwd` lives under it,
    ///      fold to `<root>/<first-segment>` — the project's repo root.
    ///      Catches arbitrary nesting (worktrees, build dirs, scripts).
    ///   2. Single-segment patterns: `.worktree` and `.worktrees`.
    ///   3. Two-segment pattern: `.claude/worktrees` (Claude Code agent
    ///      task system convention).
    ///
    /// Pathological cases (the worktree segment is the first component of
    /// the path, leaving an empty parent) keep the original cwd unchanged.
    private func normaliseForWorktree(_ cwd: String, options: QueryOptions) -> String {
        // 1. Workspace-root short-circuit.
        if let root = options.workspaceRoot, !root.isEmpty {
            let prefix = root + "/"
            if cwd.hasPrefix(prefix) {
                let tail = cwd.dropFirst(prefix.count)
                if let slash = tail.firstIndex(of: "/") {
                    let projectName = tail[..<slash]
                    if !projectName.isEmpty {
                        return root + "/" + String(projectName)
                    }
                }
                // No deeper path; the cwd IS the project root itself.
                return cwd
            }
        }

        let comps = cwd.split(separator: "/", omittingEmptySubsequences: false)

        // 2. Single-segment patterns: `.worktree` and `.worktrees`.
        if let idx = comps.firstIndex(where: { $0 == ".worktree" || $0 == ".worktrees" }) {
            if let parent = nonEmptyParent(comps, before: idx) {
                return parent
            }
        }

        // 3. Two-segment pattern: `.claude/worktrees` (consecutive). Fold
        //    to the parent of `.claude`, i.e. the repo root.
        if let dotClaudeIdx = comps.firstIndex(of: ".claude"),
           comps.index(after: dotClaudeIdx) < comps.endIndex,
           comps[comps.index(after: dotClaudeIdx)] == "worktrees" {
            if let parent = nonEmptyParent(comps, before: dotClaudeIdx) {
                return parent
            }
        }

        return cwd
    }

    private func nonEmptyParent(_ comps: [Substring], before idx: Int) -> String? {
        let parent = comps[..<idx].joined(separator: "/")
        if parent.isEmpty || parent == "/" { return nil }
        return parent
    }

    // MARK: - Per-project model breakdown (used by the CC tab's totals card)

    /// Per-model weighted-volume totals for a single project over `[from, to]`.
    /// Returned tuples sum the same `(input·1 + output·5 + cache_create·1.25
    /// + cache_read·0.1)` formula used elsewhere. Caller normalises to a
    /// percentage if needed.
    ///
    /// When `includeWorktrees` is true (the default), `cwd` is treated as a
    /// parent and any rows whose cwd lives under `<cwd>/.worktree/...` or
    /// `<cwd>/.worktrees/...` are aggregated in too — matching the way
    /// `tokensByProject` folds worktrees by default. Callers that disabled
    /// the fold there should pass `false` here for consistency.
    func modelBreakdown(
        forCwd cwd: String,
        from: Date,
        to: Date,
        includeWorktrees: Bool = true
    ) -> [(model: String, weighted: Double)] {
        // Universal descendant match `<cwd>/%` captures every nested path:
        // `.worktree(s)`, `.claude/worktrees`, workspace-root descendants,
        // and any other nesting. Replaces the previous two specific LIKE
        // patterns which missed everything else.
        let sql: String
        if includeWorktrees {
            sql = """
            SELECT model,
                   SUM( input_tokens          * 1.0
                      + output_tokens         * 5.0
                      + cache_creation_tokens * 1.25
                      + cache_read_tokens     * 0.1 )
            FROM cc_message
            WHERE (cwd = ?1 OR cwd LIKE ?2)
              AND ts >= ?3 AND ts <= ?4
            GROUP BY model
            ORDER BY 2 DESC;
            """
        } else {
            sql = """
            SELECT model,
                   SUM( input_tokens          * 1.0
                      + output_tokens         * 5.0
                      + cache_creation_tokens * 1.25
                      + cache_read_tokens     * 0.1 )
            FROM cc_message
            WHERE cwd = ?1 AND ts >= ?3 AND ts <= ?4
            GROUP BY model
            ORDER BY 2 DESC;
            """
        }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text (stmt, 1, cwd, -1, SQLITE_TRANSIENT)
        if includeWorktrees {
            sqlite3_bind_text(stmt, 2, cwd + "/%", -1, SQLITE_TRANSIENT)
        }
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(from.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 4, sqlite3_int64(to.timeIntervalSince1970))

        var out: [(model: String, weighted: Double)] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let model = String(cString: sqlite3_column_text(stmt, 0))
            let weighted = sqlite3_column_double(stmt, 1)
            out.append((model: model, weighted: weighted))
        }
        return out
    }

    // MARK: - Cross-source oldest (task 8.7)

    func oldestCCMessageTimestamp() -> Date? {
        let sql = "SELECT MIN(ts) FROM cc_message;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        let ts = sqlite3_column_int64(stmt, 0)
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    // MARK: - Aliases (task 8.8)

    func aliases() -> [String: String] {
        let sql = "SELECT cwd, display_name FROM project_alias;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [:] }
        defer { sqlite3_finalize(stmt) }
        var out: [String: String] = [:]
        while sqlite3_step(stmt) == SQLITE_ROW {
            let cwd = String(cString: sqlite3_column_text(stmt, 0))
            let display = String(cString: sqlite3_column_text(stmt, 1))
            out[cwd] = display
        }
        return out
    }

    func setAlias(cwd: String, displayName: String) {
        let sql = "INSERT OR REPLACE INTO project_alias (cwd, display_name) VALUES (?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cwd,         -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, displayName, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    func removeAlias(cwd: String) {
        let sql = "DELETE FROM project_alias WHERE cwd = ?;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, cwd, -1, SQLITE_TRANSIENT)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Ingest checkpoints (used by CCUsageIngester, group 9)

    struct CheckpointRecord: Equatable, Sendable {
        let filePath: String
        let byteOffset: Int64
        let fileSize: Int64
        let mtime: Int64
    }

    /// Canonicalise a file path before using it as the checkpoint key, so that
    /// symlinked roots (notably macOS's `/var/folders → /private/var/folders`)
    /// don't store and look up checkpoints under different strings.
    private func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().path
    }

    /// Read the checkpoint for one file, if any.
    func checkpoint(forFile path: String) -> CheckpointRecord? {
        let canonical = canonicalPath(path)
        let sql = """
        SELECT byte_offset, file_size, mtime
        FROM cc_ingest_checkpoint
        WHERE file_path = ?;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, canonical, -1, SQLITE_TRANSIENT)
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return CheckpointRecord(
            filePath: canonical,
            byteOffset: sqlite3_column_int64(stmt, 0),
            fileSize:   sqlite3_column_int64(stmt, 1),
            mtime:      sqlite3_column_int64(stmt, 2)
        )
    }

    /// Upsert a checkpoint for one file. Persisted after the ingester reaches
    /// EOF on a file, where `byteOffset` is the position of the last newline
    /// it consumed.
    func setCheckpoint(
        forFile path: String,
        byteOffset: Int64,
        fileSize: Int64,
        mtime: Int64
    ) {
        let canonical = canonicalPath(path)
        let sql = """
        INSERT OR REPLACE INTO cc_ingest_checkpoint
            (file_path, byte_offset, file_size, mtime)
        VALUES (?, ?, ?, ?);
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text (stmt, 1, canonical,  -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, byteOffset)
        sqlite3_bind_int64(stmt, 3, fileSize)
        sqlite3_bind_int64(stmt, 4, mtime)
        _ = sqlite3_step(stmt)
    }

    // MARK: - Observed cwds (task 8.9)

    /// Distinct cwds after worktree fold — the list the alias sheet should
    /// show so users set aliases on the parent path (not on individual
    /// `.worktree(s)` / `.claude/worktrees` / workspace-root descendants
    /// that are folded away during aggregation). When fold is disabled in
    /// `options`, returns the raw cwds.
    func effectiveCwds(options: QueryOptions) -> [String] {
        let raw = observedCwds()
        guard options.mergeWorktrees else { return raw }
        let folded = Set(raw.map { normaliseForWorktree($0, options: options) })
        return folded.sorted()
    }

    func observedCwds() -> [String] {
        let sql = "SELECT DISTINCT cwd FROM cc_message ORDER BY cwd;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        var out: [String] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            out.append(String(cString: sqlite3_column_text(stmt, 0)))
        }
        return out
    }

    // MARK: - Plumbing

    private func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw UsageStoreError.execFailed(msg)
        }
    }
}
