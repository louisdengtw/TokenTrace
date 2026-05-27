import Charts
import SwiftUI

struct CCUsageView: View {
    let domain: ClosedRange<Date>

    @Environment(\.colorScheme) private var scheme
    @State private var selectedDate: Date?

    // MARK: - Stub data sourcing

    private var rangeDays: Int {
        max(1, Int(domain.upperBound.timeIntervalSince(domain.lowerBound) / 86400))
    }

    private var projects: [CCProjectSeries] {
        CCUsagePreviewData.projects(now: domain.upperBound, days: min(rangeDays, 30))
    }

    private var fiveHour: [UsageSample] {
        CCUsagePreviewData.subscriptionFiveHour(now: domain.upperBound, days: min(rangeDays, 30))
    }

    private var sevenDay: [UsageSample] {
        CCUsagePreviewData.subscriptionSevenDay(now: domain.upperBound, days: min(rangeDays, 30))
    }

    // MARK: - Aggregates

    private var aggregates: [ProjectAggregate] {
        projects.map { p in
            ProjectAggregate(
                project: p,
                weighted: p.buckets.reduce(0.0) { $0 + $1.weightedTotal },
                inputTokens:           p.buckets.reduce(0) { $0 + $1.inputTokens },
                outputTokens:          p.buckets.reduce(0) { $0 + $1.outputTokens },
                cacheCreationTokens:   p.buckets.reduce(0) { $0 + $1.cacheCreationTokens },
                cacheReadTokens:       p.buckets.reduce(0) { $0 + $1.cacheReadTokens }
            )
        }.sorted { $0.weighted > $1.weighted }
    }

    private var grandTotalWeighted: Double {
        aggregates.reduce(0) { $0 + $1.weighted }
    }

    private var stackedMaxPerBucket: Double {
        guard let firstProject = projects.first else { return 1 }
        let allTimestamps = firstProject.buckets.map(\.ts)
        var maxStacked = 0.0
        for ts in allTimestamps {
            let stacked = projects.reduce(0.0) { acc, p in
                acc + (p.buckets.first { $0.ts == ts }?.weightedTotal ?? 0)
            }
            maxStacked = max(maxStacked, stacked)
        }
        return max(maxStacked, 1)
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                statsStrip
                chartCard
                projectTotalsCard
            }
            .padding(18)
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Claude Code activity")
                .font(.system(size: 13, weight: .semibold))
                .tracking(-0.06)
            Spacer()
            Button { } label: {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10, weight: .semibold))
                    Text("Refresh")
                }
                .fixedSize()
            }
            .buttonStyle(PillButtonStyle(variant: .standard, size: .small))
            .disabled(true)
            .help("Re-scan ~/.claude/projects/ (stub — wired in claude-code-usage group 12)")

            Button { } label: {
                Text("Manage projects…").fixedSize()
            }
            .buttonStyle(PillButtonStyle(variant: .standard, size: .small))
            .disabled(true)
            .help("Set per-project display aliases (stub — sheet built in group 13)")

            Image(systemName: "info.circle")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .help("\"Weighted token volume\" is a relative attribution proxy derived from Anthropic API pricing ratios (input ×1, output ×5, cache_create ×1.25, cache_read ×0.1). It is NOT a direct measure of subscription quota burn; the two Y axes are not on the same scale by construction.")
        }
    }

    // MARK: - Stats strip

    private var statsStrip: some View {
        HStack(spacing: 0) {
            stat(label: "Total", value: formatVolume(grandTotalWeighted))
            statDivider
            stat(label: "Top", value: topProjectLabel)
            statDivider
            stat(label: "Peak 5h util", value: peakUtilLabel)
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(cardBackground)
    }

    private var topProjectLabel: String {
        guard let top = aggregates.first, grandTotalWeighted > 0 else { return "—" }
        let pct = Int((top.weighted / grandTotalWeighted * 100).rounded())
        return "\(top.project.displayName) \(pct)%"
    }

    private var peakUtilLabel: String {
        let peak = fiveHour.map(\.util).max() ?? 0
        return "\(Int(peak.rounded()))%"
    }

    private func stat(label: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(value)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
        }
    }

    private var statDivider: some View {
        Text("·")
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .padding(.horizontal, 10)
    }

    // MARK: - Chart card

    private var chartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            chartSubtitle
            chart
                .frame(height: 280)
            chartLegend
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(cardBackground)
    }

    private var chartSubtitle: some View {
        HStack(spacing: 6) {
            Text("Weighted token volume by project")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
            Text("Subscription utilisation overlaid")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var chart: some View {
        let yMax = stackedMaxPerBucket

        Chart {
            ForEach(projects) { project in
                ForEach(project.buckets) { bucket in
                    AreaMark(
                        x: .value("Time", bucket.ts),
                        y: .value("Weighted tokens", bucket.weightedTotal)
                    )
                    .foregroundStyle(by: .value("Project", project.displayName))
                    .interpolationMethod(.monotone)
                }
            }

            ForEach(fiveHour, id: \.ts) { s in
                LineMark(
                    x: .value("Time", s.ts),
                    y: .value("Util", s.util * yMax / 100),
                    series: .value("Series", "5h")
                )
                .foregroundStyle(.primary.opacity(0.85))
                .lineStyle(StrokeStyle(lineWidth: 1.4))
            }

            ForEach(sevenDay, id: \.ts) { s in
                LineMark(
                    x: .value("Time", s.ts),
                    y: .value("Util", s.util * yMax / 100),
                    series: .value("Series", "7d")
                )
                .foregroundStyle(.primary.opacity(0.55))
                .lineStyle(StrokeStyle(lineWidth: 1.4, dash: [4, 3]))
            }

            if let selectedDate {
                RuleMark(x: .value("Selected", selectedDate))
                    .foregroundStyle(.secondary.opacity(0.35))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }
        }
        .chartForegroundStyleScale(
            domain: projects.map(\.displayName),
            range:  projects.map(\.baseColor)
        )
        .chartYScale(domain: 0...yMax)
        .chartXScale(domain: domain)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, yMax / 2, yMax]) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [2, 4]))
                    .foregroundStyle(scheme == .dark
                                     ? Color.white.opacity(0.06)
                                     : Color.black.opacity(0.06))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(formatVolume(v))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            AxisMarks(position: .trailing, values: [0, yMax / 2, yMax]) { value in
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int((v / yMax * 100).rounded()))%")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisValueLabel(format: .dateTime.month().day())
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .chartXSelection(value: $selectedDate)
        .chartLegend(.hidden)
        .chartOverlay { proxy in
            GeometryReader { geo in
                if let date = selectedDate, let xOffset = proxy.position(forX: date) {
                    tooltipOverlay(date: date, xOffset: xOffset, plotSize: geo.size, yMax: yMax)
                }
            }
        }
    }

    private func tooltipOverlay(date: Date, xOffset: CGFloat, plotSize: CGSize, yMax: Double) -> some View {
        let nearestPerProject: [(name: String, color: Color, weighted: Double, bucket: CCBucket?)] = projects.map { p in
            let nearest = p.buckets.min { abs($0.ts.timeIntervalSince(date)) < abs($1.ts.timeIntervalSince(date)) }
            return (p.displayName, p.baseColor, nearest?.weightedTotal ?? 0, nearest)
        }
        let ordered = nearestPerProject.sorted { $0.weighted > $1.weighted }
        let top = ordered.first?.bucket
        let nearestFive = fiveHour.min { abs($0.ts.timeIntervalSince(date)) < abs($1.ts.timeIntervalSince(date)) }
        let nearestSeven = sevenDay.min { abs($0.ts.timeIntervalSince(date)) < abs($1.ts.timeIntervalSince(date)) }

        let cardWidth: CGFloat = 230
        let xClamped = max(8, min(plotSize.width - cardWidth - 8, xOffset + 12))

        return VStack(alignment: .leading, spacing: 6) {
            Text(date, format: .dateTime.month().day().hour().minute())
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider().opacity(0.4)

            VStack(alignment: .leading, spacing: 3) {
                ForEach(ordered, id: \.name) { row in
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(row.color)
                            .frame(width: 8, height: 8)
                        Text(row.name).font(.system(size: 10))
                        Spacer()
                        Text(formatVolume(row.weighted))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let top {
                Divider().opacity(0.4)
                Text("Top: \(ordered.first?.name ?? "") components")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
                componentRow(label: "input",         tokens: top.inputTokens)
                componentRow(label: "output",        tokens: top.outputTokens)
                componentRow(label: "cache create",  tokens: top.cacheCreationTokens)
                componentRow(label: "cache read",    tokens: top.cacheReadTokens)
            }

            if nearestFive != nil || nearestSeven != nil {
                Divider().opacity(0.4)
                HStack(spacing: 12) {
                    if let s = nearestFive {
                        Text("5h: \(Int(s.util.rounded()))%")
                            .font(.system(size: 10, design: .monospaced))
                    }
                    if let s = nearestSeven {
                        Text("7d: \(Int(s.util.rounded()))%")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .frame(width: cardWidth, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(.thickMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color.primary.opacity(0.12), lineWidth: 0.5)
                )
        )
        .offset(x: xClamped, y: 0)
    }

    private func componentRow(label: String, tokens: Int) -> some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            Spacer()
            Text(formatTokenCount(tokens))
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var chartLegend: some View {
        HStack(spacing: 0) {
            HStack(spacing: 14) {
                ForEach(projects) { p in
                    HStack(spacing: 5) {
                        RoundedRectangle(cornerRadius: 2).fill(p.baseColor).frame(width: 9, height: 9)
                        Text(p.displayName).font(.system(size: 10))
                    }
                }
            }
            Spacer()
            HStack(spacing: 12) {
                HStack(spacing: 5) {
                    Rectangle().fill(Color.primary.opacity(0.85)).frame(width: 14, height: 1.5)
                    Text("5h util").font(.system(size: 10)).foregroundStyle(.secondary)
                }
                HStack(spacing: 5) {
                    DashedLineSwatch()
                    Text("7d util").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Project totals card

    private var projectTotalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Text("Project totals in range")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text("·").font(.system(size: 10)).foregroundStyle(.tertiary)
                Text("sorted by weighted volume")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            mixLegend
            columnHeaders
            VStack(spacing: 8) {
                ForEach(aggregates, id: \.project.id) { agg in
                    projectTotalRow(agg: agg, leadingWeighted: aggregates.first?.weighted ?? 1)
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 14)
        .background(cardBackground)
    }

    private var mixLegend: some View {
        HStack(spacing: 10) {
            Text("MIX")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.tertiary)
                .textCase(.uppercase)
                .tracking(0.5)
            mixLegendChip("input",         opacity: 0.95)
            mixLegendChip("output",        opacity: 0.70)
            mixLegendChip("cache_create",  opacity: 0.42)
            mixLegendChip("cache_read",    opacity: 0.18)
            Spacer()
            Text("share of weighted volume")
                .font(.system(size: 9))
                .foregroundStyle(.tertiary)
        }
    }

    private func mixLegendChip(_ label: String, opacity: Double) -> some View {
        HStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(Color.secondary.opacity(opacity))
                .frame(width: 9, height: 9)
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }

    private var columnHeaders: some View {
        HStack(spacing: 12) {
            columnLabel("Project").frame(width: 110, alignment: .leading)
            Spacer()                                                          // bar takes remaining space
            columnLabel("Weighted").frame(width: 60, alignment: .trailing)
            columnLabel("%").frame(width: 32, alignment: .trailing)
            columnLabel("Mix").frame(width: 80, alignment: .center)
            columnLabel("Model").frame(width: 130, alignment: .trailing)
        }
    }

    private func columnLabel(_ s: String) -> some View {
        Text(s)
            .font(.system(size: 9, weight: .medium))
            .foregroundStyle(.tertiary)
            .textCase(.uppercase)
            .tracking(0.5)
    }

    private func projectTotalRow(agg: ProjectAggregate, leadingWeighted: Double) -> some View {
        let pct = grandTotalWeighted > 0 ? Int((agg.weighted / grandTotalWeighted * 100).rounded()) : 0
        let opusPct = Int((agg.project.opusRatio * 100).rounded())

        return HStack(spacing: 12) {
            Text(agg.project.displayName)
                .font(.system(size: 11))
                .frame(width: 110, alignment: .leading)
                .lineLimit(1)
                .truncationMode(.middle)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(scheme == .dark
                              ? Color.white.opacity(0.05)
                              : Color.black.opacity(0.05))
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(agg.project.baseColor.opacity(0.85))
                        .frame(width: geo.size.width * (agg.weighted / max(leadingWeighted, 1)))
                }
            }
            .frame(height: 8)

            Text(formatVolume(agg.weighted))
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.primary)
                .frame(width: 60, alignment: .trailing)

            Text("\(pct)%")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 32, alignment: .trailing)

            ComponentMiniBar(
                input: agg.inputTokens,
                output: agg.outputTokens,
                cacheCreation: agg.cacheCreationTokens,
                cacheRead: agg.cacheReadTokens,
                color: agg.project.baseColor
            )
            .frame(width: 80, height: 6)
            .help("Share of weighted volume by component (input×1 + output×5 + cache_create×1.25 + cache_read×0.1)")

            Text("Opus \(opusPct)% · Sonnet \(100 - opusPct)%")
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 130, alignment: .trailing)
        }
    }

    // MARK: - Shared chrome

    private var cardBackground: some View {
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
    }

    // MARK: - Formatters

    private func formatVolume(_ v: Double) -> String {
        switch v {
        case ..<1000:           return "\(Int(v))"
        case ..<1_000_000:      return "\(Int(v / 1000))K"
        default:                return String(format: "%.1fM", v / 1_000_000)
        }
    }

    private func formatTokenCount(_ n: Int) -> String {
        let v = Double(n)
        switch v {
        case ..<1000:           return "\(n)"
        case ..<1_000_000:      return "\(Int(v / 1000))K"
        default:                return String(format: "%.1fM", v / 1_000_000)
        }
    }
}

// MARK: - Subviews

private struct ProjectAggregate {
    let project: CCProjectSeries
    let weighted: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
}

private struct ComponentMiniBar: View {
    let input: Int
    let output: Int
    let cacheCreation: Int
    let cacheRead: Int
    let color: Color

    // Each component contributes to the *weighted* total via the pricing-ratio
    // weights (input ×1, output ×5, cache_create ×1.25, cache_read ×0.1). The
    // bar shows that share so it matches the headline metric of the card;
    // raw-token ratio would be dominated by cache_read and would not reflect
    // where the project's weighted volume actually comes from.
    var body: some View {
        let wIn  = Double(input)         * 1.0
        let wOut = Double(output)        * 5.0
        let wCc  = Double(cacheCreation) * 1.25
        let wCr  = Double(cacheRead)     * 0.1
        let total = wIn + wOut + wCc + wCr

        GeometryReader { geo in
            if total > 0 {
                HStack(spacing: 0) {
                    Rectangle().fill(color.opacity(0.95))
                        .frame(width: geo.size.width * wIn  / total)
                    Rectangle().fill(color.opacity(0.70))
                        .frame(width: geo.size.width * wOut / total)
                    Rectangle().fill(color.opacity(0.42))
                        .frame(width: geo.size.width * wCc  / total)
                    Rectangle().fill(color.opacity(0.18))
                        .frame(width: geo.size.width * wCr  / total)
                }
                .clipShape(RoundedRectangle(cornerRadius: 1.5, style: .continuous))
            } else {
                Rectangle().fill(.secondary.opacity(0.1))
            }
        }
    }
}

private struct DashedLineSwatch: View {
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<3, id: \.self) { _ in
                Rectangle().fill(Color.primary.opacity(0.55)).frame(width: 3, height: 1.5)
            }
        }
        .frame(width: 14, alignment: .leading)
    }
}
