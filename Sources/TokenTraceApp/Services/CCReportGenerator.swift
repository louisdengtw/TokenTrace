import Foundation
import OSLog

// MARK: - Public request / data types

/// User-configured shape of a Claude Code export.
struct CCReportRequest: Equatable {
    let title: String
    let range: RangeSelection
    let includeOverlay: Bool
    let includeProjectTotals: Bool
}

/// Produces a portable HTML (and PDF, via `PDFRenderer`) report for the
/// Claude Code tab. Mirrors `ReportGenerator`'s sentinel-token substitution
/// approach so the two report variants stay siblings.
///
/// Pipeline:
///   1. Resolve the request's range using both stores' oldest timestamps
///      (so "All" spans subscription samples + cc_message rows).
///   2. Query `CCUsageStore.tokensByProject` with the user's display
///      preferences (depth + worktree fold).
///   3. Apply the same Top-N + "Other" grouping the live tab uses so the
///      exported chart reads the same way.
///   4. Compute totals, model split, colours, and per-bucket weighted
///      contributions for each component.
///   5. Substitute into `cc-report.html.template`.
struct CCReportGenerator {
    let ccStore: CCUsageStore
    let usageStore: UsageStore
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "CCReportGenerator")

    enum Error: Swift.Error {
        case templateNotFound
        case templateReadFailed(underlying: Swift.Error)
        case unresolvedTokens([String])
    }

    /// Default Top-N before folding the rest into "Other (N)". Matches the
    /// live tab's `maxIndividualProjects`.
    static let maxIndividualProjects = 8

    /// Fixed palette ordered by row index (matches CCUsageView.palette).
    private static let palette: [String] = [
        "#4F8DEF",   // blue
        "#45B07D",   // green
        "#8F6BD6",   // purple
        "#F09E2E",   // amber
        "#D94D8C",   // pink
        "#33999E",   // teal
    ]

    private static let otherCwdSentinel = "__cc_other__"

    // MARK: - Entry point

    func generateHTML(
        request: CCReportRequest,
        now: Date = Date(),
        dbPath: String
    ) throws -> String {
        let oldestSub = usageStore.oldestTimestamp()
        let oldestCC  = ccStore.oldestCCMessageTimestamp()
        let oldest = earliest(oldestSub, oldestCC)
        let (start, end) = request.range.resolved(now: now, oldestSample: oldest)
        let bucket = autoBucket(from: start, to: end)

        let options = CCUsageStore.QueryOptions(
            displayNameDepth: AppSettings.ccProjectNameDepth,
            mergeWorktrees: AppSettings.ccMergeWorktrees
        )
        let rawProjects = ccStore.tokensByProject(from: start, to: end, bucket: bucket, options: options)
        let series = groupTopN(rawProjects, n: Self.maxIndividualProjects)

        // Per-series aggregate (totals + model split) — identical math to the
        // live tab's `computeAggregates`.
        var rows: [TotalsRowJSON] = []
        var grandTotalWeighted: Double = 0
        for (i, p) in series.enumerated() {
            let color = Self.color(forIndex: i, cwd: p.cwd)
            let totalIn  = p.buckets.reduce(0) { $0 + $1.inputTokens }
            let totalOut = p.buckets.reduce(0) { $0 + $1.outputTokens }
            let totalCc  = p.buckets.reduce(0) { $0 + $1.cacheCreationTokens }
            let totalCr  = p.buckets.reduce(0) { $0 + $1.cacheReadTokens }
            let weighted = p.buckets.reduce(0.0) { $0 + $1.weightedTotal }
            grandTotalWeighted += weighted

            var opusRatio: Double = 0
            if p.cwd != Self.otherCwdSentinel {
                let models = ccStore.modelBreakdown(
                    forCwd: p.cwd,
                    from: start, to: end,
                    includeWorktrees: AppSettings.ccMergeWorktrees
                )
                let totalW = models.reduce(0.0) { $0 + $1.weighted }
                let opusW = models
                    .filter { $0.model.lowercased().contains("opus") }
                    .reduce(0.0) { $0 + $1.weighted }
                opusRatio = totalW > 0 ? opusW / totalW : 0
            }

            rows.append(TotalsRowJSON(
                cwd: p.cwd,
                displayName: p.displayName,
                color: color,
                weighted: weighted,
                weightedFormatted: formatVolume(weighted),
                pct: 0,            // backfilled once grandTotalWeighted is known
                inputWeighted:         Double(totalIn)  * 1.0,
                outputWeighted:        Double(totalOut) * 5.0,
                cacheCreationWeighted: Double(totalCc)  * 1.25,
                cacheReadWeighted:     Double(totalCr)  * 0.1,
                totalRaw: Double(totalIn + totalOut + totalCc + totalCr),
                opusPct: Int((opusRatio * 100).rounded()),
                isOther: p.cwd == Self.otherCwdSentinel
            ))
        }
        rows = rows.map { row in
            var copy = row
            copy.pct = grandTotalWeighted > 0
                ? Int((row.weighted / grandTotalWeighted * 100).rounded())
                : 0
            return copy
        }
        let leadingWeighted = rows.first?.weighted ?? 1

        // Per-series per-bucket data for the chart (component-weighted).
        let seriesJSON: [SeriesJSON] = series.enumerated().map { (i, p) in
            SeriesJSON(
                cwd: p.cwd,
                displayName: p.displayName,
                color: Self.color(forIndex: i, cwd: p.cwd),
                buckets: p.buckets.map { b in
                    BucketJSON(
                        ts: epochMillis(b.ts),
                        inputWeighted:         Double(b.inputTokens)         * 1.0,
                        outputWeighted:        Double(b.outputTokens)        * 5.0,
                        cacheCreationWeighted: Double(b.cacheCreationTokens) * 1.25,
                        cacheReadWeighted:     Double(b.cacheReadTokens)     * 0.1
                    )
                }
            )
        }

        // Subscription overlay (optional).
        var fiveHourPoints: [UtilPointJSON] = []
        var sevenDayPoints: [UtilPointJSON] = []
        if request.includeOverlay {
            fiveHourPoints = usageStore.query(bucket: .fiveHour, from: start, to: end).map {
                UtilPointJSON(ts: epochMillis($0.ts), util: $0.util)
            }
            sevenDayPoints = usageStore.query(bucket: .sevenDay, from: start, to: end).map {
                UtilPointJSON(ts: epochMillis($0.ts), util: $0.util)
            }
        }

        // Stats strip values.
        let topLabel: String
        if let first = rows.first, grandTotalWeighted > 0 {
            topLabel = "\(first.displayName) \(first.pct)%"
        } else {
            topLabel = "—"
        }
        let peakUtil = fiveHourPoints.map(\.util).max() ?? 0
        let statsJSON = StatsJSON(
            totalWeightedFormatted: formatVolume(grandTotalWeighted),
            topProjectLabel: topLabel,
            peakUtilLabel: "\(Int(peakUtil.rounded()))%"
        )

        let reportJSON = ReportJSON(
            rangeStart: epochMillis(start),
            rangeEnd: epochMillis(end),
            series: seriesJSON,
            fiveHour: fiveHourPoints,
            sevenDay: sevenDayPoints
        )
        let totalsJSON = TotalsJSON(
            leadingWeighted: leadingWeighted,
            rows: rows
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = []

        let reportEncoded = try encoder.encode(reportJSON)
        let statsEncoded  = try encoder.encode(statsJSON)
        let totalsEncoded = try encoder.encode(totalsJSON)

        guard
            let reportStr = String(data: reportEncoded, encoding: .utf8),
            let statsStr  = String(data: statsEncoded,  encoding: .utf8),
            let totalsStr = String(data: totalsEncoded, encoding: .utf8)
        else {
            preconditionFailure("JSONEncoder produced non-UTF8 output")
        }

        // Render.
        let template = try loadTemplate()
        let chartJS = try ChartJSAsset.bundledContents()

        var html = template
        html = html.replacingOccurrences(of: "__TITLE__",                with: htmlEscape(request.title), options: .literal)
        html = html.replacingOccurrences(of: "__DATE_RANGE__",           with: dateRangeString(start: start, end: end))
        html = html.replacingOccurrences(of: "__DURATION_DAYS__",        with: "\(durationDays(start: start, end: end))")
        html = html.replacingOccurrences(of: "__GENERATED_AT__",         with: generatedAtString(now: now))
        html = html.replacingOccurrences(of: "__DB_PATH__",              with: htmlEscape(dbPath))
        html = html.replacingOccurrences(of: "__STATS_JSON__",           with: statsStr)
        html = html.replacingOccurrences(of: "__SERIES_JSON__",          with: reportStr)
        html = html.replacingOccurrences(of: "__PROJECT_TOTALS_JSON__",  with: totalsStr)
        html = html.replacingOccurrences(of: "__INCLUDE_OVERLAY__",      with: request.includeOverlay ? "true" : "false")
        html = html.replacingOccurrences(of: "__INCLUDE_TOTALS__",       with: request.includeProjectTotals ? "true" : "false")
        html = html.replacingOccurrences(of: "__CHART_JS__",             with: chartJS)

        let leftover = Self.sentinelTokens.filter { html.contains($0) }
        if !leftover.isEmpty {
            log.error("CC report template still contains unresolved tokens: \(leftover, privacy: .public)")
            throw Error.unresolvedTokens(leftover)
        }
        return html
    }

    // MARK: - Top-N + "Other" grouping (mirrors CCUsageView)

    private func groupTopN(
        _ all: [CCUsageStore.ProjectSeries],
        n: Int
    ) -> [CCUsageStore.ProjectSeries] {
        guard all.count > n else { return all }
        let top = Array(all.prefix(n))
        let rest = Array(all.dropFirst(n))
        guard !rest.isEmpty else { return top }

        var summed: [Date: (Int, Int, Int, Int)] = [:]
        for s in rest {
            for b in s.buckets {
                var prev = summed[b.ts] ?? (0, 0, 0, 0)
                prev.0 += b.inputTokens
                prev.1 += b.outputTokens
                prev.2 += b.cacheCreationTokens
                prev.3 += b.cacheReadTokens
                summed[b.ts] = prev
            }
        }
        let buckets = summed
            .sorted { $0.key < $1.key }
            .map { (ts, v) in
                CCUsageStore.ProjectBucket(
                    ts: ts,
                    inputTokens: v.0,
                    outputTokens: v.1,
                    cacheCreationTokens: v.2,
                    cacheReadTokens: v.3
                )
            }
        let other = CCUsageStore.ProjectSeries(
            cwd: Self.otherCwdSentinel,
            displayName: "Other (\(rest.count))",
            buckets: buckets
        )
        return top + [other]
    }

    // MARK: - Helpers

    private static func color(forIndex i: Int, cwd: String) -> String {
        if cwd == otherCwdSentinel { return "#9B9B9B" }
        return palette[i % palette.count]
    }

    private func autoBucket(from: Date, to: Date) -> CCUsageStore.TimeBucket {
        let days = to.timeIntervalSince(from) / 86400
        if days <= 1 { return .hour }
        if days <= 30 { return .day }
        return .week
    }

    private func earliest(_ a: Date?, _ b: Date?) -> Date? {
        switch (a, b) {
        case (nil, nil):       return nil
        case (let x?, nil):    return x
        case (nil, let x?):    return x
        case (let x?, let y?): return min(x, y)
        }
    }

    private func loadTemplate() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "cc-report.html",
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
        "__GENERATED_AT__", "__DB_PATH__",
        "__STATS_JSON__", "__SERIES_JSON__", "__PROJECT_TOTALS_JSON__",
        "__INCLUDE_OVERLAY__", "__INCLUDE_TOTALS__",
        "__CHART_JS__",
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

    private func formatVolume(_ v: Double) -> String {
        switch v {
        case ..<1000:           return "\(Int(v))"
        case ..<1_000_000:      return "\(Int(v / 1000))K"
        default:                return String(format: "%.1fM", v / 1_000_000)
        }
    }

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
    let series: [SeriesJSON]
    let fiveHour: [UtilPointJSON]
    let sevenDay: [UtilPointJSON]
}

private struct SeriesJSON: Encodable {
    let cwd: String
    let displayName: String
    let color: String
    let buckets: [BucketJSON]
}

private struct BucketJSON: Encodable {
    let ts: Int64
    let inputWeighted: Double
    let outputWeighted: Double
    let cacheCreationWeighted: Double
    let cacheReadWeighted: Double
}

private struct UtilPointJSON: Encodable {
    let ts: Int64
    let util: Double
}

private struct StatsJSON: Encodable {
    let totalWeightedFormatted: String
    let topProjectLabel: String
    let peakUtilLabel: String
}

private struct TotalsJSON: Encodable {
    let leadingWeighted: Double
    let rows: [TotalsRowJSON]
}

private struct TotalsRowJSON: Encodable {
    let cwd: String
    let displayName: String
    let color: String
    let weighted: Double
    let weightedFormatted: String
    var pct: Int
    let inputWeighted: Double
    let outputWeighted: Double
    let cacheCreationWeighted: Double
    let cacheReadWeighted: Double
    let totalRaw: Double
    let opusPct: Int
    let isOther: Bool
}
