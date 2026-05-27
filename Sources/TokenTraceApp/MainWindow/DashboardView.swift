import Charts
import SwiftUI

struct DashboardView: View {
    @ObservedObject var usageManager: UsageManager

    @State private var range: RangeSelection = AppSettings.dashboardRangeSelection
    @State private var fiveHour: [UsageSample] = []
    @State private var sevenDay: [UsageSample] = []
    @State private var sevenDaySonnet: [UsageSample] = []
    @State private var domain: ClosedRange<Date> = Date()...Date()
    @State private var selectedTab: DashboardTabKey = .subscription
    @State private var showingCCExport: Bool = false

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if isDevBuild {
                TabView(selection: $selectedTab) {
                    subscriptionContent
                        .tabItem { Text("Subscription") }
                        .tag(DashboardTabKey.subscription)
                    CCUsageView(domain: domain)
                        .tabItem { Text("Claude Code") }
                        .tag(DashboardTabKey.claudeCode)
                }
            } else {
                subscriptionContent
            }
        }
        .onAppear { reload() }
        .onChange(of: range) { newValue in
            AppSettings.dashboardRangeSelection = newValue
            reload()
        }
        .onChange(of: usageManager.latestSample) { _ in reload() }
        .sheet(isPresented: $showingCCExport) {
            CCExportSheetView()
        }
    }

    // The TabView wrapper is gated behind the `.dev` bundle ID so the
    // production build is untouched while the Claude Code tab is still
    // in prototype form. Removed when claude-code-usage group 11 lands
    // the proper TabView refactor.
    private var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    private var exportButtonLabel: String {
        (isDevBuild && selectedTab == .claudeCode) ? "Export Claude Code…" : "Export Report…"
    }

    private var exportButtonHelp: String {
        (isDevBuild && selectedTab == .claudeCode)
            ? "Export the visible range as a CC project-breakdown report"
            : "Export the visible range to a portable HTML or PDF report"
    }

    private var subscriptionContent: some View {
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

    // MARK: - Toolbar

    private var toolbar: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Dashboard")
                    .font(.system(size: 14, weight: .semibold))
                    .tracking(-0.1)
                Spacer()
                Button {
                    if isDevBuild && selectedTab == .claudeCode {
                        showingCCExport = true
                    } else {
                        NotificationCenter.default.post(name: .exportReportRequested, object: nil)
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 10, weight: .semibold))
                        Text(exportButtonLabel)
                    }
                    .fixedSize()
                }
                .buttonStyle(PillButtonStyle(variant: .standard, size: .small))
                .help(exportButtonHelp)
            }
            HStack {
                Spacer()
                RangePickerView(
                    selection: $range,
                    oldestSample: usageManager.store.oldestTimestamp()
                )
                .fixedSize()
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
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
        let (from, to) = range.resolved(
            now: now,
            oldestSample: usageManager.store.oldestTimestamp()
        )
        domain = from...to
        fiveHour       = usageManager.store.query(bucket: .fiveHour,       from: from, to: to)
        sevenDay       = usageManager.store.query(bucket: .sevenDay,       from: from, to: to)
        sevenDaySonnet = usageManager.store.query(bucket: .sevenDaySonnet, from: from, to: to)
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
        let yMax = adaptiveYMax(primary: samples, secondary: secondarySamples)

        VStack(alignment: .leading, spacing: 12) {
            header(displaySample: nearestPrimary, primaryColor: primaryColor)

            if samples.isEmpty && (secondarySamples?.isEmpty ?? true) {
                emptyState
            } else {
                chartBody(
                    primaryColor: primaryColor,
                    resets: resets,
                    nearestPrimary: nearestPrimary,
                    yMax: yMax
                )
                .frame(height: 168)
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.03)
                      : Color.white.opacity(0.72))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private func header(displaySample: UsageSample?, primaryColor: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Circle()
                        .fill(primaryColor)
                        .frame(width: 6, height: 6)
                        .alignmentGuide(.firstTextBaseline) { d in d[VerticalAlignment.center] + 2 }
                    Text(title)
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.06)
                }
                statsLine
            }
            Spacer(minLength: 12)
            HStack(alignment: .lastTextBaseline, spacing: 1) {
                Text("\(Int((displaySample?.util ?? 0).rounded()))")
                    .font(.system(size: 26, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .tracking(-0.8)
                Text("%")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 1)
            }
        }
    }

    private var statsLine: some View {
        let utils = samples.map(\.util)
        let peak = utils.max() ?? 0
        let avg  = utils.isEmpty ? 0 : utils.reduce(0, +) / Double(utils.count)

        return HStack(spacing: 0) {
            statChip(label: "Peak", value: "\(Int(peak.rounded()))%")
            divider
            statChip(label: "Avg",  value: formatAvg(avg))
            divider
            statChip(label: "n",    value: "\(samples.count)")
            if secondarySamples != nil {
                divider
                statChip(label: secondaryLabel, value: "\(secondarySamples?.count ?? 0)")
            }
        }
    }

    private var divider: some View {
        Text("·")
            .font(.system(size: 10))
            .foregroundStyle(scheme == .dark
                             ? Color.white.opacity(0.20)
                             : Color.black.opacity(0.20))
            .padding(.horizontal, 6)
    }

    private func statChip(label: String, value: String) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
    }

    private func formatAvg(_ value: Double) -> String {
        value < 10 ? String(format: "%.1f%%", value) : "\(Int(value.rounded()))%"
    }

    private func adaptiveYMax(primary: [UsageSample], secondary: [UsageSample]?) -> Double {
        let all = primary.map(\.util) + (secondary?.map(\.util) ?? [])
        let observed = all.max() ?? 0
        if observed <= 20 { return 25 }
        if observed <= 45 { return 50 }
        if observed <= 70 { return 75 }
        return 100
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
                           nearestPrimary: UsageSample?,
                           yMax: Double) -> some View {
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
        .chartYScale(domain: 0...yMax)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: yAxisValues(max: yMax)) { value in
                AxisGridLine(stroke: StrokeStyle(
                    lineWidth: 0.5,
                    dash: (value.as(Double.self) == 0 ? [] : [2, 4])
                ))
                .foregroundStyle(scheme == .dark
                                 ? Color.white.opacity(0.05)
                                 : Color.black.opacity(0.05))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(scheme == .dark
                                             ? Color.white.opacity(0.38)
                                             : Color.black.opacity(0.42))
                    }
                }
            }
        }
        .chartXAxis {
            xAxisMarks
        }
        .chartXSelectionIfAvailable(value: $selectedDate)
    }

    // Computed axis configuration

    private func yAxisValues(max: Double) -> [Double] {
        switch max {
        case 25:  return [0, 25]
        case 50:  return [0, 25, 50]
        case 75:  return [0, 50]
        default:  return [0, 50, 100]
        }
    }

    /// Hide the hour component once the visible range exceeds ~2 days; the
    /// stamp gets long and pointless at that scale.
    @AxisContentBuilder
    private var xAxisMarks: some AxisContent {
        let spanDays = domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400
        if spanDays <= 2 {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month().day().hour())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.42)
                                     : Color.black.opacity(0.45))
            }
        } else {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.42)
                                     : Color.black.opacity(0.45))
            }
        }
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

// Identifier for the two-tab dev-build layout. Stored on a local @State today;
// will be persisted via AppSettings.lastDashboardTab in claude-code-usage group 11.
enum DashboardTabKey: String, Hashable {
    case subscription
    case claudeCode
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
