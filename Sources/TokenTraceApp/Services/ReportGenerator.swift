import Foundation
import OSLog

// MARK: - Public request / output types

/// What the user wants in the exported report.
struct ReportRequest: Equatable {
    let title: String
    let range: RangeSelection
    let buckets: Set<Bucket>
}

// MARK: - Generator

/// Produces a self-contained HTML report from the local SQLite store.
///
/// Process:
///   1. Resolve the request's `RangeSelection` to absolute `(start, end)` dates
///   2. For each requested bucket (in canonical order): query samples,
///      compute summary stats, detect reset events
///   3. Serialize the per-bucket payload to JSON
///   4. Load the bundled `report.html.template`, substitute sentinel tokens,
///      and inline the bundled Chart.js source
struct ReportGenerator {
    let store: UsageStore
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "ReportGenerator")

    enum Error: Swift.Error {
        case templateNotFound
        case templateReadFailed(underlying: Swift.Error)
        case unresolvedTokens([String])
    }

    /// Canonical section order: the fixed windows, then model-scoped weekly
    /// buckets sorted by model name.
    static func canonicalOrder(_ buckets: Set<Bucket>) -> [Bucket] {
        var ordered: [Bucket] = []
        if buckets.contains(.fiveHour) { ordered.append(.fiveHour) }
        if buckets.contains(.sevenDay) { ordered.append(.sevenDay) }
        let scoped = buckets.compactMap { bucket -> String? in
            guard case .weeklyScoped(let model) = bucket else { return nil }
            return model
        }
        ordered.append(contentsOf: scoped.sorted().map { .weeklyScoped(model: $0) })
        return ordered
    }

    /// Generate the report HTML. `now` is injected for determinism. `dbPath`
    /// is the source path stamped into the footer (cosmetic only).
    func generateHTML(
        request: ReportRequest,
        now: Date = Date(),
        dbPath: String
    ) throws -> String {
        let oldest = store.oldestTimestamp()
        let (start, end) = request.range.resolved(now: now, oldestSample: oldest)

        let orderedBuckets = Self.canonicalOrder(request.buckets)

        var bucketPayloads: [BucketJSON] = []
        for bucket in orderedBuckets {
            bucketPayloads.append(makeBucketPayload(bucket: bucket, start: start, end: end))
        }

        let reportPayload = ReportJSON(
            rangeStart: epochMillis(start),
            rangeEnd: epochMillis(end),
            buckets: bucketPayloads
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        let jsonData = try encoder.encode(reportPayload)
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            preconditionFailure("JSONEncoder produced non-UTF8 output")
        }

        let template = try loadTemplate()
        let chartJS = try ChartJSAsset.bundledContents()
        let logoURI = LogoAsset.bundledDataURI()

        var html = template
        // Smaller substitutions first; __CHART_JS__ last so that the giant
        // payload doesn't get scanned redundantly on each pass.
        html = html.replacingOccurrences(of: "__TITLE__", with: htmlEscape(request.title))
        html = html.replacingOccurrences(of: "__DATE_RANGE__", with: dateRangeString(start: start, end: end))
        html = html.replacingOccurrences(of: "__DURATION_DAYS__", with: "\(durationDays(start: start, end: end))")
        html = html.replacingOccurrences(of: "__GENERATED_AT__", with: generatedAtString(now: now))
        html = html.replacingOccurrences(of: "__DB_PATH__", with: htmlEscape(dbPath))
        html = html.replacingOccurrences(of: "__LOGO_DATA_URI__", with: logoURI)
        html = html.replacingOccurrences(of: "__REPORT_JSON__", with: jsonString)
        html = html.replacingOccurrences(of: "__CHART_JS__", with: chartJS)

        // Sanity: catch any token we forgot to substitute.
        let leftover = Self.sentinelTokens.filter { html.contains($0) }
        if !leftover.isEmpty {
            log.error("Report template still contains unresolved tokens: \(leftover, privacy: .public)")
            throw Error.unresolvedTokens(leftover)
        }
        return html
    }

    // MARK: - Per-bucket payload

    private func makeBucketPayload(bucket: Bucket, start: Date, end: Date) -> BucketJSON {
        let samples = store.query(bucket: bucket, from: start, to: end)
        let resets = ResetDetection.detect(samples).map { epochMillis($0.displayTimestamp) }

        let stats: BucketStatsJSON?
        if samples.isEmpty {
            stats = nil
        } else {
            let utils = samples.map(\.util)
            let peak = utils.max() ?? 0
            let avg = utils.reduce(0, +) / Double(utils.count)
            stats = BucketStatsJSON(
                n: samples.count,
                peak: roundedDisplay(peak),
                avg: roundedDisplay(avg)
            )
        }

        let points = samples.map {
            SamplePoint(ts: epochMillis($0.ts), util: $0.util)
        }

        return BucketJSON(
            id: bucket.key,
            label: label(for: bucket),
            subtitle: subtitle(for: bucket),
            color: color(for: bucket),
            samples: points,
            resets: resets,
            stats: stats
        )
    }

    // MARK: - Bucket display metadata (server-side; template only renders)

    private func label(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour:                 return "5-Hour Window"
        case .sevenDay:                 return "7-Day Window"
        case .weeklyScoped(let model):  return "7-Day Window — \(model)"
        }
    }

    private func subtitle(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour:                 return "Rolling 5-hour usage · resets every 5h"
        case .sevenDay:                 return "Weekly usage · resets each Monday"
        case .weeklyScoped(let model):  return "Weekly \(model) usage · resets each Monday"
        }
    }

    /// Wong (2011) color-blind-safe palette; scoped buckets get a stable
    /// per-model color from `ScopedSeriesColor`.
    private func color(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour:                 return "#0072B2"  // blue
        case .sevenDay:                 return "#D55E00"  // vermillion
        case .weeklyScoped(let model):  return ScopedSeriesColor.hex(for: model)
        }
    }

    // MARK: - Template + formatting helpers

    private func loadTemplate() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "report.html",
            withExtension: "template",
            subdirectory: "Resources"
        ) else {
            throw Error.templateNotFound
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw Error.templateReadFailed(underlying: error)
        }
    }

    private static let sentinelTokens: [String] = [
        "__TITLE__", "__DATE_RANGE__", "__DURATION_DAYS__",
        "__GENERATED_AT__", "__DB_PATH__", "__LOGO_DATA_URI__",
        "__REPORT_JSON__", "__CHART_JS__"
    ]

    private func epochMillis(_ date: Date) -> Int64 {
        Int64(date.timeIntervalSince1970 * 1000)
    }

    private func dateRangeString(start: Date, end: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "\(f.string(from: start)) → \(f.string(from: end))"
    }

    private func durationDays(start: Date, end: Date) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let comps = cal.dateComponents([.day], from: start, to: end)
        return max(1, comps.day ?? 1)
    }

    private func generatedAtString(now: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm"
        return f.string(from: now)
    }

    private func roundedDisplay(_ value: Double) -> String {
        // 60.0 → "60", 10.39 → "10.4"
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    /// Minimal HTML-text escaping for substitution into element bodies and
    /// quoted attribute contexts. Single-quote also escaped (defensive).
    private func htmlEscape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for c in s {
            switch c {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            case "'": out += "&#39;"
            default: out.append(c)
            }
        }
        return out
    }
}

// MARK: - JSON encoding wrappers

private struct ReportJSON: Encodable {
    let rangeStart: Int64
    let rangeEnd: Int64
    let buckets: [BucketJSON]
}

private struct BucketJSON: Encodable {
    let id: String
    let label: String
    let subtitle: String
    let color: String
    let samples: [SamplePoint]
    let resets: [Int64]
    let stats: BucketStatsJSON?
}

private struct BucketStatsJSON: Encodable {
    let n: Int
    let peak: String
    let avg: String
}

/// Encodes as a 2-element JSON array `[ts_ms, util]` so the inline template JS
/// can destructure each point efficiently.
private struct SamplePoint: Encodable {
    let ts: Int64
    let util: Double

    func encode(to encoder: Encoder) throws {
        var c = encoder.unkeyedContainer()
        try c.encode(ts)
        try c.encode(util)
    }
}
