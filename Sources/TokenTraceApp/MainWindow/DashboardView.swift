import Charts
import SwiftUI

enum DashboardRange: String, CaseIterable, Identifiable {
    case last24h = "24h"
    case last7d  = "7d"
    case last30d = "30d"
    case all     = "All"

    var id: String { rawValue }

    fileprivate func startDate(now: Date) -> Date? {
        switch self {
        case .last24h: return now.addingTimeInterval(-24 * 3600)
        case .last7d:  return now.addingTimeInterval(-7 * 86400)
        case .last30d: return now.addingTimeInterval(-30 * 86400)
        case .all:     return nil
        }
    }

    fileprivate var trendDescription: String {
        switch self {
        case .last24h: return "Trend across last 24 hours"
        case .last7d:  return "Trend across last 7 days"
        case .last30d: return "Trend across last 30 days"
        case .all:     return "Trend across all time"
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

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            ScrollView {
                VStack(spacing: 14) {
                    ChartCard(
                        title: "5-hour window",
                        subtitle: "Rolling 5-hour usage · resets every 5h",
                        samples: fiveHour,
                        domain: domain
                    )
                    ChartCard(
                        title: "7-day window",
                        subtitle: usageManager.hasWeeklySonnet
                            ? "Weekly usage · overall and Sonnet"
                            : "Weekly usage · resets each Monday",
                        samples: sevenDay,
                        secondarySamples: usageManager.hasWeeklySonnet ? sevenDaySonnet : nil,
                        secondaryLabel: "Sonnet",
                        domain: domain
                    )
                }
                .padding(18)
            }
        }
        .onAppear { reload() }
        .onChange(of: range)                  { _ in reload() }
        .onChange(of: usageManager.latestSample) { _ in reload() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                Text("Dashboard")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                Text(range.trendDescription)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            RangePicker(value: $range)
        }
        .padding(.horizontal, 18)
        .frame(height: 38)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(scheme == .dark
                      ? Color.white.opacity(0.06)
                      : Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Reload

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
        fiveHour       = usageManager.store.query(bucket: .fiveHour,       from: from, to: now)
        sevenDay       = usageManager.store.query(bucket: .sevenDay,       from: from, to: now)
        sevenDaySonnet = usageManager.store.query(bucket: .sevenDaySonnet, from: from, to: now)
    }
}

// MARK: - Range picker (segmented)

private struct RangePicker: View {
    @Binding var value: DashboardRange
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        HStack(spacing: 0) {
            ForEach(DashboardRange.allCases) { option in
                Button {
                    value = option
                } label: {
                    Text(option.rawValue)
                        .font(.system(size: 11, weight: value == option ? .semibold : .medium))
                        .monospacedDigit()
                        .padding(.horizontal, 12)
                        .padding(.vertical, 3)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(value == option
                                      ? (scheme == .dark
                                         ? Color.white.opacity(0.16)
                                         : Color.white.opacity(0.95))
                                      : Color.clear)
                                .shadow(color: value == option
                                        ? Color.black.opacity(0.10) : .clear,
                                        radius: 0.5, y: 0.5)
                        )
                        .foregroundStyle(.primary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(2)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.10)
                      : Color.black.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.04)
                                : Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }
}

// MARK: - Chart card

private struct ChartCard: View {
    let title: String
    let subtitle: String
    let samples: [UsageSample]
    var secondarySamples: [UsageSample]? = nil
    var secondaryLabel: String = ""
    let domain: ClosedRange<Date>

    @Environment(\.colorScheme) private var scheme
    @State private var selectedDate: Date?

    var body: some View {
        let resets = ResetDetection.detect(samples)
        let primaryColor = chartColor(samples: samples)
        let nearestPrimary = selectedDate.flatMap { findNearest(to: $0, in: samples) }
            ?? samples.last

        VStack(alignment: .leading, spacing: 10) {
            header(displaySample: nearestPrimary)

            if samples.isEmpty && (secondarySamples?.isEmpty ?? true) {
                emptyState
            } else {
                chartBody(
                    primaryColor: primaryColor,
                    resets: resets,
                    nearestPrimary: nearestPrimary
                )
                .frame(height: 200)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.white.opacity(0.6))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.08)
                                : Color.black.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    private func header(displaySample: UsageSample?) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.06)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text("\(Int((displaySample?.util ?? 0).rounded()))")
                    .font(.system(size: 22, weight: .light, design: .monospaced))
                    .monospacedDigit()
                    .tracking(-0.5)
                Text("%")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
            Text("No data yet — wait for the first poll")
                .foregroundStyle(.secondary)
        }
        .frame(height: 200)
    }

    private func chartBody(primaryColor: Color,
                           resets: [ResetEvent],
                           nearestPrimary: UsageSample?) -> some View {
        Chart {
            // Area fill (primary series)
            ForEach(samples, id: \.ts) { sample in
                AreaMark(
                    x: .value("Time", sample.ts),
                    y: .value("Util %", sample.util)
                )
                .foregroundStyle(LinearGradient(
                    colors: [primaryColor.opacity(0.30), primaryColor.opacity(0.02)],
                    startPoint: .top, endPoint: .bottom
                ))
                .interpolationMethod(.monotone)
            }

            // Primary line
            ForEach(samples, id: \.ts) { sample in
                LineMark(
                    x: .value("Time", sample.ts),
                    y: .value("Util %", sample.util),
                    series: .value("Series", "Primary")
                )
                .foregroundStyle(primaryColor)
                .lineStyle(StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
                .interpolationMethod(.monotone)
            }

            // Optional secondary line (Sonnet on the 7-day chart)
            if let secondary = secondarySamples {
                let secondaryColor = chartColor(samples: secondary).opacity(0.85)
                ForEach(secondary, id: \.ts) { sample in
                    LineMark(
                        x: .value("Time", sample.ts),
                        y: .value("Util %", sample.util),
                        series: .value("Series", secondaryLabel)
                    )
                    .foregroundStyle(secondaryColor)
                    .lineStyle(StrokeStyle(lineWidth: 1.4, lineCap: .round, lineJoin: .round, dash: [3, 2]))
                    .interpolationMethod(.monotone)
                }
            }

            // Reset markers
            ForEach(resets, id: \.displayTimestamp) { event in
                RuleMark(x: .value("Reset", event.displayTimestamp))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.20)
                                     : Color.black.opacity(0.20))
            }

            // Hover crosshair + dot
            if let nearestPrimary {
                RuleMark(x: .value("Cursor", nearestPrimary.ts))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.30)
                                     : Color.black.opacity(0.25))
                PointMark(
                    x: .value("Time", nearestPrimary.ts),
                    y: .value("Util %", nearestPrimary.util)
                )
                .foregroundStyle(scheme == .dark
                                 ? Color(red: 0.118, green: 0.118, blue: 0.125)
                                 : Color.white)
                .symbolSize(80)
                PointMark(
                    x: .value("Time", nearestPrimary.ts),
                    y: .value("Util %", nearestPrimary.util)
                )
                .foregroundStyle(primaryColor)
                .symbolSize(35)
            }
        }
        .chartYScale(domain: 0...100)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine(stroke: StrokeStyle(
                    lineWidth: 0.5,
                    dash: (value.as(Double.self) == 0 ? [] : [2, 3])
                ))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(scheme == .dark
                                             ? Color.white.opacity(0.45)
                                             : Color.black.opacity(0.45))
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month().day().hour())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.45)
                                     : Color.black.opacity(0.45))
            }
        }
        .chartXSelectionIfAvailable(value: $selectedDate)
    }

    private func chartColor(samples: [UsageSample]) -> Color {
        guard let last = samples.last else {
            return scheme == .dark
                ? Color(red: 0.204, green: 0.780, blue: 0.349)   // green
                : Color(red: 0.157, green: 0.651, blue: 0.271)
        }
        return UsageColor.color(for: last.util, scheme: scheme)
    }
}

// MARK: - Helpers

private func findNearest(to target: Date, in samples: [UsageSample]) -> UsageSample? {
    guard !samples.isEmpty else { return nil }
    return samples.min(by: {
        abs($0.ts.timeIntervalSince(target)) < abs($1.ts.timeIntervalSince(target))
    })
}

private extension View {
    /// `chartXSelection(value:)` ships in macOS 14. On 13 the chart renders
    /// without interactive selection (the header readout still shows the latest sample).
    @ViewBuilder
    func chartXSelectionIfAvailable(value: Binding<Date?>) -> some View {
        if #available(macOS 14.0, *) {
            self.chartXSelection(value: value)
        } else {
            self
        }
    }
}
