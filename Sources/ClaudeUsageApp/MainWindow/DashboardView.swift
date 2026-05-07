import Charts
import SwiftUI

enum DashboardRange: String, CaseIterable, Identifiable {
    case last24h = "24h"
    case last7d = "7d"
    case last30d = "30d"
    case all = "All"

    var id: String { rawValue }

    /// Returns the start of the visible window. `.all` returns nil (caller substitutes
    /// the oldest sample's timestamp, or now-24h when the store is empty).
    func startDate(now: Date) -> Date? {
        switch self {
        case .last24h: return now.addingTimeInterval(-24 * 3600)
        case .last7d:  return now.addingTimeInterval(-7 * 86400)
        case .last30d: return now.addingTimeInterval(-30 * 86400)
        case .all:     return nil
        }
    }
}

struct DashboardView: View {
    @ObservedObject var usageManager: UsageManager

    @State private var range: DashboardRange = .last7d
    @State private var fiveHour: [UsageSample] = []
    @State private var sevenDay: [UsageSample] = []
    @State private var sevenDaySonnet: [UsageSample] = []
    @State private var domain: ClosedRange<Date> = Date()...Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Dashboard").font(.title2.bold())
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(DashboardRange.allCases) { r in
                        Text(r.rawValue).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
            }

            FiveHourChart(samples: fiveHour, domain: domain)
                .frame(maxWidth: .infinity, minHeight: 200)

            SevenDayChart(
                overall: sevenDay,
                sonnet: sevenDaySonnet,
                domain: domain
            )
            .frame(maxWidth: .infinity, minHeight: 200)

            Spacer(minLength: 0)
        }
        .padding(20)
        .onAppear { reload() }
        .onChange(of: range) { _ in reload() }
        .onChange(of: usageManager.latestSample) { _ in reload() }
    }

    private func reload() {
        let now = Date()
        let from: Date
        if let r = range.startDate(now: now) {
            from = r
        } else if let oldest = usageManager.store.oldestTimestamp() {
            from = oldest
        } else {
            from = now.addingTimeInterval(-86400)
        }
        domain = from...now
        fiveHour = usageManager.store.query(bucket: .fiveHour, from: from, to: now)
        sevenDay = usageManager.store.query(bucket: .sevenDay, from: from, to: now)
        sevenDaySonnet = usageManager.store.query(bucket: .sevenDaySonnet, from: from, to: now)
    }
}

// MARK: - Charts

private struct FiveHourChart: View {
    let samples: [UsageSample]
    let domain: ClosedRange<Date>
    @State private var selected: Date?

    var body: some View {
        ChartContainer(title: "5-hour Session Utilization", isEmpty: samples.isEmpty) {
            let resets = ResetDetection.detect(samples)
            let nearestSample = selected.flatMap { nearest(to: $0, in: samples) }

            Chart {
                ForEach(samples, id: \.ts) { sample in
                    LineMark(
                        x: .value("Time", sample.ts),
                        y: .value("Util %", sample.util)
                    )
                    .interpolationMethod(.monotone)
                }

                ForEach(resets, id: \.displayTimestamp) { event in
                    RuleMark(x: .value("Reset", event.displayTimestamp))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.gray.opacity(0.6))
                }

                if let nearestSample {
                    RuleMark(x: .value("Cursor", nearestSample.ts))
                        .foregroundStyle(.secondary.opacity(0.4))
                    PointMark(
                        x: .value("Time", nearestSample.ts),
                        y: .value("Util %", nearestSample.util)
                    )
                    .symbolSize(80)
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: domain)
            .chartXSelectionIfAvailable(value: $selected)
            .overlay(alignment: .topTrailing) {
                if let nearestSample {
                    Tooltip(time: nearestSample.ts, lines: [("Session", nearestSample.util)])
                }
            }
        }
    }
}

private struct SevenDayChart: View {
    let overall: [UsageSample]
    let sonnet: [UsageSample]
    let domain: ClosedRange<Date>
    @State private var selected: Date?

    var body: some View {
        ChartContainer(
            title: "7-day Weekly Utilization",
            isEmpty: overall.isEmpty && sonnet.isEmpty
        ) {
            let resets = ResetDetection.detect(overall)
            let tooltipModel = selected.flatMap {
                buildSevenDayTooltip(at: $0, overall: overall, sonnet: sonnet)
            }

            Chart {
                ForEach(overall, id: \.ts) { sample in
                    LineMark(
                        x: .value("Time", sample.ts),
                        y: .value("Util %", sample.util),
                        series: .value("Series", "Overall")
                    )
                    .foregroundStyle(by: .value("Series", "Overall"))
                    .interpolationMethod(.monotone)
                }
                ForEach(sonnet, id: \.ts) { sample in
                    LineMark(
                        x: .value("Time", sample.ts),
                        y: .value("Util %", sample.util),
                        series: .value("Series", "Sonnet")
                    )
                    .foregroundStyle(by: .value("Series", "Sonnet"))
                    .interpolationMethod(.monotone)
                }

                ForEach(resets, id: \.displayTimestamp) { event in
                    RuleMark(x: .value("Reset", event.displayTimestamp))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        .foregroundStyle(.gray.opacity(0.6))
                }

                if let tooltipModel {
                    RuleMark(x: .value("Cursor", tooltipModel.anchor))
                        .foregroundStyle(.secondary.opacity(0.4))
                }
            }
            .chartYScale(domain: 0...100)
            .chartXScale(domain: domain)
            .chartXSelectionIfAvailable(value: $selected)
            .chartLegend(position: .top, alignment: .trailing)
            .overlay(alignment: .topTrailing) {
                if let tooltipModel {
                    Tooltip(time: tooltipModel.anchor, lines: tooltipModel.lines)
                }
            }
        }
    }
}

private struct SevenDayTooltipModel {
    let anchor: Date
    let lines: [(String, Double)]
}

private func buildSevenDayTooltip(
    at target: Date,
    overall: [UsageSample],
    sonnet: [UsageSample]
) -> SevenDayTooltipModel? {
    let overallNearest = nearest(to: target, in: overall)
    let sonnetNearest = nearest(to: target, in: sonnet)
    var lines: [(String, Double)] = []
    if let overallNearest { lines.append(("Overall", overallNearest.util)) }
    if let sonnetNearest { lines.append(("Sonnet", sonnetNearest.util)) }
    guard !lines.isEmpty, let anchor = overallNearest?.ts ?? sonnetNearest?.ts else {
        return nil
    }
    return SevenDayTooltipModel(anchor: anchor, lines: lines)
}

private extension View {
    /// `chartXSelection(value:)` ships in macOS 14. On 13 we render the chart
    /// without interactive selection (tooltips degrade quietly).
    @ViewBuilder
    func chartXSelectionIfAvailable(value: Binding<Date?>) -> some View {
        if #available(macOS 14.0, *) {
            self.chartXSelection(value: value)
        } else {
            self
        }
    }
}

// MARK: - Helpers

private func nearest(to target: Date, in samples: [UsageSample]) -> UsageSample? {
    guard !samples.isEmpty else { return nil }
    return samples.min(by: {
        abs($0.ts.timeIntervalSince(target)) < abs($1.ts.timeIntervalSince(target))
    })
}

private struct ChartContainer<Content: View>: View {
    let title: String
    let isEmpty: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            if isEmpty {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.06))
                    Text("No data yet — wait for the first poll")
                        .foregroundStyle(.secondary)
                }
            } else {
                content()
            }
        }
    }
}

private struct Tooltip: View {
    let time: Date
    let lines: [(String, Double)]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(time.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.bold())
            ForEach(lines, id: \.0) { name, value in
                HStack {
                    Text(name).foregroundStyle(.secondary)
                    Text("\(Int(value.rounded()))%")
                        .font(.body.monospacedDigit())
                }
            }
        }
        .padding(8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
        .padding(8)
    }
}
