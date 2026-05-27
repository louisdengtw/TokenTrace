import Foundation
import SwiftUI

// Prototype-only stub data for the Claude Code tab. Will be deleted in
// claude-code-usage tasks 12.8 once CCUsageStore plumbing lands.

struct CCProjectSeries: Identifiable {
    let id: String
    let displayName: String
    let baseColor: Color
    /// Stub-only fraction in [0, 1] of weighted volume attributed to Opus
    /// (remainder is Sonnet). Real data layer will derive this from
    /// `cc_message.model` row totals.
    let opusRatio: Double
    let buckets: [CCBucket]
}

struct CCBucket: Identifiable {
    let id: Date
    let ts: Date
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int

    var weightedTotal: Double {
        Double(inputTokens) * 1.0
            + Double(outputTokens) * 5.0
            + Double(cacheCreationTokens) * 1.25
            + Double(cacheReadTokens) * 0.1
    }

    init(ts: Date, input: Int, output: Int, cacheCreation: Int, cacheRead: Int) {
        self.id = ts
        self.ts = ts
        self.inputTokens = input
        self.outputTokens = output
        self.cacheCreationTokens = cacheCreation
        self.cacheReadTokens = cacheRead
    }
}

enum CCUsagePreviewData {
    static func projects(now: Date = Date(), days: Int = 7) -> [CCProjectSeries] {
        let startOfToday = Calendar.current.startOfDay(for: now)
        let day: (Int) -> Date = { i in
            Calendar.current.date(byAdding: .day, value: -(days - 1 - i), to: startOfToday)!
        }

        // Intensity profiles chosen so each project peaks on different days,
        // and the subscription utilisation peaks visibly correlate with one
        // project (TokenTrace on day 0 and day d-1). This makes the hover
        // payoff demonstrable without explanation.
        let ttProfile: [Double] = stride(from: 0, to: days, by: 1).map { i in
            let i = Double(i)
            let last = Double(days - 1)
            if i == 0 { return 4.5 }
            if i == last { return 5.5 }
            if i == last - 1 { return 0.4 }
            return 0.3
        }
        let bmoProfile: [Double] = stride(from: 0, to: days, by: 1).map { i in
            let mid = Double(days) / 2.0
            return max(0.1, 3.5 - abs(Double(i) - mid) * 1.2)
        }
        let dynaProfile: [Double] = Array(repeating: 0.8, count: days)
        let gpsProfile: [Double] = stride(from: 0, to: days, by: 1).map { i in
            i % 2 == 0 ? 1.4 : 0.4
        }

        return [
            project(
                id: "/Users/louisdeng/workspace/TokenTrace",
                name: "TokenTrace",
                color: Color(red: 0.31, green: 0.55, blue: 0.94),
                opusRatio: 0.95,
                days: days,
                day: day,
                profile: ttProfile
            ),
            project(
                id: "/Users/louisdeng/workspace/bmo-analysis",
                name: "bmo-analysis",
                color: Color(red: 0.27, green: 0.69, blue: 0.49),
                opusRatio: 0.30,
                days: days,
                day: day,
                profile: bmoProfile
            ),
            project(
                id: "/Users/louisdeng/workspace/DynaRAG",
                name: "DynaRAG",
                color: Color(red: 0.56, green: 0.42, blue: 0.84),
                opusRatio: 0.65,
                days: days,
                day: day,
                profile: dynaProfile
            ),
            project(
                id: "/Users/louisdeng/workspace/GPSMock",
                name: "GPSMock",
                color: Color(red: 0.94, green: 0.62, blue: 0.18),
                opusRatio: 0.85,
                days: days,
                day: day,
                profile: gpsProfile
            ),
        ]
    }

    static func subscriptionFiveHour(now: Date = Date(), days: Int = 7) -> [UsageSample] {
        // 5h samples — 6/day. Peaks line up with TokenTrace activity peaks.
        let startOfToday = Calendar.current.startOfDay(for: now)
        var samples: [UsageSample] = []
        for i in 0..<(days * 6) {
            let ts = Calendar.current.date(
                byAdding: .hour,
                value: -((days - 1) * 24) + (i * 4),
                to: startOfToday
            )!
            let daysFromStart = Double(i) / 6.0
            let dayPos = daysFromStart.truncatingRemainder(dividingBy: Double(days))
            let last = Double(days - 1)
            // Mirror TokenTrace's peaks: day 0 high, day last high, middle low
            let base = dayPos == 0 ? 70.0 : (dayPos >= last - 0.5 ? 85.0 : 35.0)
            let jitter = Double((i * 13) % 7) - 3.0
            samples.append(UsageSample(ts: ts, bucket: .fiveHour, util: max(0, min(100, base + jitter)), resetsAt: ts))
        }
        return samples
    }

    static func subscriptionSevenDay(now: Date = Date(), days: Int = 7) -> [UsageSample] {
        // 7d bucket — slowly ramps. Stable mid-range.
        let startOfToday = Calendar.current.startOfDay(for: now)
        var samples: [UsageSample] = []
        for i in 0..<(days * 4) {
            let ts = Calendar.current.date(
                byAdding: .hour,
                value: -((days - 1) * 24) + (i * 6),
                to: startOfToday
            )!
            let progress = Double(i) / Double(days * 4)
            let util = 40.0 + progress * 35.0
            samples.append(UsageSample(ts: ts, bucket: .sevenDay, util: util, resetsAt: ts))
        }
        return samples
    }

    private static func project(
        id: String,
        name: String,
        color: Color,
        opusRatio: Double,
        days: Int,
        day: (Int) -> Date,
        profile: [Double]
    ) -> CCProjectSeries {
        // Component ratios are realistic: cache_read dwarfs raw counts but
        // its 0.1 weight keeps it from dominating weighted total.
        let buckets: [CCBucket] = (0..<days).map { i in
            let p = profile[i]
            return CCBucket(
                ts: day(i),
                input: Int(900 * p),
                output: Int(1800 * p),
                cacheCreation: Int(11_000 * p),
                cacheRead: Int(48_000 * p)
            )
        }
        return CCProjectSeries(id: id, displayName: name, baseColor: color, opusRatio: opusRatio, buckets: buckets)
    }
}
