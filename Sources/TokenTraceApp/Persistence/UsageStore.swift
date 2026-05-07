import Foundation
import OSLog
import SQLite3

enum UsageStoreError: Error, Equatable {
    case openFailed(String)
    case prepareFailed(String)
    case stepFailed(Int32, String)
    case execFailed(String)
}

final class UsageStore {
    private let db: OpaquePointer
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "UsageStore")

    private let SQLITE_TRANSIENT = unsafeBitCast(
        OpaquePointer(bitPattern: -1)!, to: sqlite3_destructor_type.self
    )

    static func defaultDatabaseURL() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = support.appendingPathComponent("dev.louisdeng.tokentrace", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbPath = dir.appendingPathComponent("usage.sqlite")

        // One-time migration from the pre-rename location (when the app was
        // named ClaudeUsage). Move on first launch only; subsequent launches
        // see the new path already populated.
        if !FileManager.default.fileExists(atPath: dbPath.path) {
            let legacyDir = support.appendingPathComponent("dev.louisdeng.claudeusage", isDirectory: true)
            let legacyDB = legacyDir.appendingPathComponent("usage.sqlite")
            if FileManager.default.fileExists(atPath: legacyDB.path) {
                try FileManager.default.moveItem(at: legacyDB, to: dbPath)
                // Best-effort: clean up the now-empty legacy directory.
                try? FileManager.default.removeItem(at: legacyDir)
            }
        }
        return dbPath
    }

    init(url: URL) throws {
        var handle: OpaquePointer?
        let openResult = sqlite3_open_v2(
            url.path,
            &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let opened = handle else {
            let msg = handle.map { String(cString: sqlite3_errmsg($0)) } ?? "code=\(openResult)"
            if let h = handle { sqlite3_close(h) }
            throw UsageStoreError.openFailed(msg)
        }
        self.db = opened

        sqlite3_busy_timeout(db, 200)

        for ddl in Schema.allDDL {
            try execute(ddl)
        }
    }

    deinit {
        sqlite3_close(db)
    }

    func insert(samples: [UsageSample]) {
        guard !samples.isEmpty else { return }
        let sql = "INSERT OR REPLACE INTO samples (ts, bucket, util, resets_at) VALUES (?, ?, ?, ?);"
        for sample in samples {
            do {
                try retryingOnBusy {
                    try insertOne(sample, sql: sql)
                }
            } catch {
                log.error("insert failed for bucket=\(sample.bucket.rawValue, privacy: .public): \(String(describing: error), privacy: .public)")
            }
        }
    }

    private func insertOne(_ sample: UsageSample, sql: String) throws {
        var stmt: OpaquePointer?
        if sqlite3_prepare_v2(db, sql, -1, &stmt, nil) != SQLITE_OK {
            throw UsageStoreError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_int64(stmt, 1, sqlite3_int64(sample.ts.timeIntervalSince1970))
        sqlite3_bind_text(stmt, 2, sample.bucket.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 3, sample.util)
        sqlite3_bind_int64(stmt, 4, sqlite3_int64(sample.resetsAt.timeIntervalSince1970))

        let result = sqlite3_step(stmt)
        if result != SQLITE_DONE {
            throw UsageStoreError.stepFailed(result, String(cString: sqlite3_errmsg(db)))
        }
    }

    func query(bucket: Bucket, from: Date, to: Date) -> [UsageSample] {
        let sql = """
        SELECT ts, util, resets_at FROM samples
        WHERE bucket = ? AND ts >= ? AND ts <= ?
        ORDER BY ts ASC;
        """
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            log.error("query prepare failed: \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
            return []
        }
        defer { sqlite3_finalize(stmt) }

        sqlite3_bind_text(stmt, 1, bucket.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 2, sqlite3_int64(from.timeIntervalSince1970))
        sqlite3_bind_int64(stmt, 3, sqlite3_int64(to.timeIntervalSince1970))

        var rows: [UsageSample] = []
        while true {
            let r = sqlite3_step(stmt)
            if r == SQLITE_ROW {
                let ts = sqlite3_column_int64(stmt, 0)
                let util = sqlite3_column_double(stmt, 1)
                let resetsAt = sqlite3_column_int64(stmt, 2)
                rows.append(UsageSample(
                    ts: Date(timeIntervalSince1970: TimeInterval(ts)),
                    bucket: bucket,
                    util: util,
                    resetsAt: Date(timeIntervalSince1970: TimeInterval(resetsAt))
                ))
            } else if r == SQLITE_DONE {
                break
            } else {
                log.error("query step failed code=\(r): \(String(cString: sqlite3_errmsg(self.db)), privacy: .public)")
                break
            }
        }
        return rows
    }

    func oldestTimestamp() -> Date? {
        let sql = "SELECT MIN(ts) FROM samples;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return nil }
        defer { sqlite3_finalize(stmt) }
        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        if sqlite3_column_type(stmt, 0) == SQLITE_NULL { return nil }
        let ts = sqlite3_column_int64(stmt, 0)
        return Date(timeIntervalSince1970: TimeInterval(ts))
    }

    private func execute(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let msg = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw UsageStoreError.execFailed(msg)
        }
    }

    private func retryingOnBusy(maxAttempts: Int = 3, block: () throws -> Void) throws {
        var attempts = 0
        while true {
            do {
                try block()
                return
            } catch UsageStoreError.stepFailed(let code, _) where code == SQLITE_BUSY || code == SQLITE_LOCKED {
                attempts += 1
                if attempts >= maxAttempts {
                    throw UsageStoreError.stepFailed(code, "retries exhausted")
                }
                Thread.sleep(forTimeInterval: 0.05 * Double(attempts))
            }
        }
    }
}
