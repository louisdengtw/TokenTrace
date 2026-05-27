import Foundation
import OSLog

/// Scans `~/.claude/projects/**/*.jsonl` and writes one row per qualifying
/// assistant turn into `cc_message`. Resumes from per-file byte-offset
/// checkpoints; never re-reads bytes that were already past a confirmed
/// newline. Never decodes `message.content` into a Swift value — the
/// JSONDecoder reads the bytes but only materialises the projection in
/// `JSONLine`.
final class CCUsageIngester {
    private let store: CCUsageStore
    private let projectsRoot: URL
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "CCUsageIngester")

    /// Flush threshold for batched `INSERT OR IGNORE` via `CCUsageStore`. 1000
    /// rows ≈ a few MB of memory and keeps the transaction short enough that
    /// the UI never sees a stall.
    private let flushEvery: Int = 1000

    static var defaultProjectsRoot: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    struct IngestSummary: Equatable, Sendable {
        let filesScanned: Int
        let rowsInserted: Int
        let rowsIgnored: Int
        let divergences: Int
        /// True iff at least one file required an offset-zero scan in this
        /// run (either no checkpoint existed, or the file was truncated /
        /// mtime regressed). Drives the CCUsageView "Indexing…" indicator.
        let coldScanOccurred: Bool
        let elapsed: TimeInterval
    }

    init(store: CCUsageStore, projectsRoot: URL = CCUsageIngester.defaultProjectsRoot) {
        self.store = store
        self.projectsRoot = projectsRoot
    }

    /// Run a full pass on a background queue. Safe to call repeatedly —
    /// previously-processed bytes are skipped via the checkpoint table.
    func ingest() async -> IngestSummary {
        await withCheckedContinuation { (cont: CheckedContinuation<IngestSummary, Never>) in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: self.runSync())
            }
        }
    }

    // MARK: - Core sync implementation

    /// Per-run mutable state. Held on the stack of `runSync` and mutated by
    /// `ingestFile` via `inout`. `seenUuidPayloads` is scoped to a single
    /// ingest run so divergence is detected across files (not just within
    /// one file).
    private struct Accumulator {
        var inserted: Int = 0
        var ignored: Int = 0
        var divergences: Int = 0
        var coldScanOccurred: Bool = false
        var seenUuidPayloads: [String: Int] = [:]
    }

    private func runSync() -> IngestSummary {
        let start = Date()
        let files = walkProjectsRoot()
        var acc = Accumulator()

        for url in files {
            ingestFile(at: url, into: &acc)
        }

        return IngestSummary(
            filesScanned: files.count,
            rowsInserted: acc.inserted,
            rowsIgnored: acc.ignored,
            divergences: acc.divergences,
            coldScanOccurred: acc.coldScanOccurred,
            elapsed: Date().timeIntervalSince(start)
        )
    }

    // MARK: - File walk (task 9.2)

    private func walkProjectsRoot() -> [URL] {
        let fm = FileManager.default
        guard fm.fileExists(atPath: projectsRoot.path) else { return [] }

        guard let enumerator = fm.enumerator(
            at: projectsRoot,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var out: [URL] = []
        for case let url as URL in enumerator {
            guard url.pathExtension == "jsonl" else { continue }
            // Resolve regular-file-ness so we skip symlinks-to-directories etc.
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
            guard values?.isRegularFile == true else { continue }
            out.append(url)
        }
        return out
    }

    // MARK: - Per-file ingest (tasks 9.3 / 9.4 / 9.8 / 9.10)

    private func ingestFile(at url: URL, into acc: inout Accumulator) {
        let fm = FileManager.default
        let attrs: [FileAttributeKey: Any]
        do {
            attrs = try fm.attributesOfItem(atPath: url.path)
        } catch {
            log.error("stat failed for \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        let fileSize = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        let mtime    = Int64((attrs[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)

        // Resume vs cold-scan decision (task 9.3).
        var startOffset: Int64 = 0
        var wasColdScan = true
        if let cp = store.checkpoint(forFile: url.path),
           fileSize >= cp.byteOffset,
           mtime >= cp.mtime {
            startOffset = cp.byteOffset
            wasColdScan = false
        }
        if wasColdScan { acc.coldScanOccurred = true }

        // No new bytes since last run — nothing to do.
        if startOffset >= fileSize { return }

        // Read tail. NB: this reads the file's tail into memory; a 100 MB
        // JSONL fits comfortably; multi-GB users would want chunked reads
        // (revisit if performance complaints surface).
        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: UInt64(startOffset))
        } catch {
            log.error("seek failed for \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        let tail: Data
        do {
            tail = try handle.readToEnd() ?? Data()
        } catch {
            log.error("read failed for \(url.path, privacy: .public): \(String(describing: error), privacy: .public)")
            return
        }

        // Partial-line safety (task 9.4): consume only up to and including the
        // last `\n`. If no newline is present at all, the file's tail is one
        // incomplete line — leave it for the next run.
        let newlineByte: UInt8 = 0x0A
        guard let lastNewlineRel = tail.lastIndex(of: newlineByte) else { return }
        let consumableEnd = tail.distance(from: tail.startIndex, to: lastNewlineRel) + 1
        let consumable = tail.prefix(consumableEnd)

        // Parse + buffer + flush in batches.
        var batch: [CCMessage] = []
        batch.reserveCapacity(flushEvery)

        for lineSlice in consumable.split(separator: newlineByte, omittingEmptySubsequences: true) {
            let lineData = Data(lineSlice)
            guard let parsed = parseAssistantLine(lineData, filePath: url.path) else { continue }

            // Cross-run divergence detection (task 9.9): if the same uuid has
            // a different payload-hash than we've already seen this run,
            // count it. INSERT OR IGNORE will keep first-seen at the DB.
            if let prev = acc.seenUuidPayloads[parsed.message.uuid] {
                if prev != parsed.payloadHash {
                    acc.divergences += 1
                }
            } else {
                acc.seenUuidPayloads[parsed.message.uuid] = parsed.payloadHash
            }

            batch.append(parsed.message)
            if batch.count >= flushEvery {
                let r = store.insertMessages(batch)
                acc.inserted += r.inserted
                acc.ignored  += r.ignored
                batch.removeAll(keepingCapacity: true)
            }
        }
        if !batch.isEmpty {
            let r = store.insertMessages(batch)
            acc.inserted += r.inserted
            acc.ignored  += r.ignored
        }

        // Persist checkpoint at the last newline position (task 9.10).
        let newAbsoluteOffset = startOffset + Int64(consumableEnd)
        store.setCheckpoint(
            forFile: url.path,
            byteOffset: newAbsoluteOffset,
            fileSize: fileSize,
            mtime: mtime
        )
    }

    // MARK: - JSON parsing (tasks 9.5 / 9.6 / 9.7)

    /// Privacy projection: declares only the fields the ingester needs. The
    /// `message.content` key is intentionally absent — `JSONDecoder` reads
    /// past those bytes but never materialises them as a Swift `String` or
    /// `Data`.
    private struct JSONLine: Decodable {
        let type: String?
        let uuid: String?
        let timestamp: String?
        let cwd: String?
        let sessionId: String?
        let requestId: String?
        let isSidechain: Bool?
        let message: MessagePayload?

        struct MessagePayload: Decodable {
            let model: String?
            let usage: UsagePayload?
        }

        struct UsagePayload: Decodable {
            let inputTokens: Int?
            let outputTokens: Int?
            let cacheCreationInputTokens: Int?
            let cacheReadInputTokens: Int?

            enum CodingKeys: String, CodingKey {
                case inputTokens                = "input_tokens"
                case outputTokens               = "output_tokens"
                case cacheCreationInputTokens   = "cache_creation_input_tokens"
                case cacheReadInputTokens       = "cache_read_input_tokens"
            }
        }
    }

    private struct ParsedLine {
        let message: CCMessage
        let payloadHash: Int
    }

    private func parseAssistantLine(_ data: Data, filePath: String) -> ParsedLine? {
        let decoder = JSONDecoder()
        guard let line = try? decoder.decode(JSONLine.self, from: data) else { return nil }

        // Filter (task 9.5).
        guard line.type == "assistant" else { return nil }
        guard let msg = line.message,
              let model = msg.model,
              model != "<synthetic>",
              let usage = msg.usage else {
            return nil
        }
        guard let uuid = line.uuid,
              let tsString = line.timestamp,
              let ts = Self.parseISO8601(tsString),
              let cwd = line.cwd,
              let sessionId = line.sessionId else {
            return nil
        }

        // Outer usage fields only (task 9.7) — iterations[] is ignored.
        let input       = usage.inputTokens                ?? 0
        let output      = usage.outputTokens               ?? 0
        let cacheCreate = usage.cacheCreationInputTokens   ?? 0
        let cacheRead   = usage.cacheReadInputTokens       ?? 0

        let m = CCMessage(
            uuid: uuid,
            ts: ts,
            cwd: cwd,
            model: model,
            inputTokens: input,
            outputTokens: output,
            cacheCreationTokens: cacheCreate,
            cacheReadTokens: cacheRead,
            sessionId: sessionId,
            requestId: line.requestId,
            isSidechain: line.isSidechain ?? false,
            filePath: filePath
        )

        // Cheap fingerprint of the payload for in-run divergence detection.
        // Wrapping arithmetic so giant token counts don't trap.
        let payloadHash = (input &* 31) &+ (output &* 17) &+ (cacheCreate &* 13) &+ (cacheRead &* 7)

        return ParsedLine(message: m, payloadHash: payloadHash)
    }

    /// Parse the CC JSONL's timestamp format (e.g. `2026-05-13T16:50:04.149Z`).
    /// JSONDecoder's built-in .iso8601 does not accept fractional seconds.
    private static func parseISO8601(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
