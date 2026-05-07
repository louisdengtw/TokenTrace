import SwiftUI

struct PopoverView: View {
    @ObservedObject var usageManager: UsageManager
    let openMainWindow: (MainTab) -> Void

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(spacing: 0) {
            header
            content
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
            Spacer(minLength: 0)
            footer
        }
        .frame(width: 320, height: 280)
        .background(.ultraThinMaterial)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Text("ClaudeUsage")
                .font(.system(size: 12, weight: .semibold))
                .tracking(-0.06)

            if usageManager.hasWeeklySonnet {
                Text("PRO+")
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(scheme == .dark
                        ? Color(red: 0.353, green: 0.784, blue: 0.980)   // #5AC8FA
                        : Color(red: 0.000, green: 0.400, blue: 0.800))  // #0066CC
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        RoundedRectangle(cornerRadius: 3)
                            .fill(scheme == .dark
                                ? Color(red: 0.039, green: 0.518, blue: 1.00).opacity(0.20)
                                : Color(red: 0.000, green: 0.478, blue: 1.00).opacity(0.12))
                    )
            }

            Spacer()

            HStack(spacing: 4) {
                Circle()
                    .fill(syncIndicatorColor)
                    .frame(width: 5, height: 5)
                Text(syncLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, 9)
        .padding(.horizontal, 12)
        .padding(.bottom, 7)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if usageManager.sessionExpired {
            inlineNotice(
                title: "Session expired",
                detail: "Open Settings to paste a fresh cookie.",
                tint: scheme == .dark ? .orange : .orange
            )
        } else if !usageManager.hasFetchedData {
            inlineNotice(
                title: usageManager.isLoading ? "Loading…" : "Waiting for first poll…",
                detail: usageManager.sessionCookie.isEmpty
                    ? "Paste your claude.ai cookie in Settings to begin."
                    : "Polling every 5 minutes.",
                tint: .secondary
            )
        } else {
            VStack(spacing: 5) {
                ForEach(orderedBuckets, id: \.self) { bucket in
                    if let sample = usageManager.latestSample[bucket] {
                        BucketCard(
                            label: cardLabel(for: bucket),
                            sample: sample,
                            sparkline: sparkline(for: bucket),
                            scheme: scheme
                        )
                    }
                }
            }
        }
    }

    private func inlineNotice(title: String, detail: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.system(size: 12, weight: .medium)).foregroundStyle(tint)
            Text(detail).font(.system(size: 11)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 8) {
            Button("Open Main Window") {
                openMainWindow(.dashboard)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
            .frame(maxWidth: .infinity)

            Button("Settings…") {
                openMainWindow(.settings)
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(scheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.black.opacity(0.08))
                .frame(height: 0.5)
        }
    }

    // MARK: - Helpers

    private var orderedBuckets: [Bucket] {
        var buckets: [Bucket] = [.fiveHour, .sevenDay]
        if usageManager.hasWeeklySonnet { buckets.append(.sevenDaySonnet) }
        return buckets
    }

    private func cardLabel(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour:        return "5-hour"
        case .sevenDay:        return "7-day"
        case .sevenDaySonnet:  return "Sonnet"
        }
    }

    private func sparkline(for bucket: Bucket) -> [Double] {
        let now = Date()
        let from: Date
        switch bucket {
        case .fiveHour:
            from = now.addingTimeInterval(-2 * 3600)
        case .sevenDay, .sevenDaySonnet:
            from = now.addingTimeInterval(-24 * 3600)
        }
        let recent = usageManager.store.query(bucket: bucket, from: from, to: now).suffix(12)
        return recent.map(\.util)
    }

    private var syncIndicatorColor: Color {
        if usageManager.sessionExpired { return .orange }
        if usageManager.errorMessage != nil { return .red }
        if usageManager.hasFetchedData { return Color(red: 0.204, green: 0.780, blue: 0.349) }
        return .secondary
    }

    private var syncLabel: String {
        if let sample = usageManager.latestSample[.fiveHour] {
            return relativeAgo(from: sample.ts)
        }
        if usageManager.isLoading { return "syncing…" }
        return "—"
    }

    private func relativeAgo(from date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "\(seconds)s ago" }
        let minutes = seconds / 60
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        return "\(hours / 24)d ago"
    }
}

// MARK: - Bucket card

private struct BucketCard: View {
    let label: String
    let sample: UsageSample
    let sparkline: [Double]
    let scheme: ColorScheme

    private static let segmentCount = 28

    var body: some View {
        let pct = Int(sample.util.rounded())
        let color = UsageColor.color(for: sample.util, scheme: scheme)

        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 6) {
                Text(label)
                    .font(.system(size: 11.5, weight: .medium))
                    .tracking(-0.06)

                Spacer()

                if sparkline.count >= 2 {
                    Sparkline(values: sparkline, color: color)
                        .frame(width: 44, height: 12)
                }

                Text("\(pct)%")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .monospacedDigit()
                    .foregroundStyle(pct >= 75 ? color : Color.primary)
                    .frame(minWidth: 30, alignment: .trailing)
            }

            HStack(spacing: 1.5) {
                ForEach(0..<Self.segmentCount, id: \.self) { i in
                    let filled = Double(i) < (sample.util / 100.0) * Double(Self.segmentCount)
                    RoundedRectangle(cornerRadius: 1)
                        .fill(filled
                              ? color
                              : (scheme == .dark
                                 ? Color.white.opacity(0.08)
                                 : Color.black.opacity(0.06)))
                        .frame(height: 6)
                }
            }

            Text("resets \(resetCountdown)")
                .font(.system(size: 10, design: .monospaced))
                .tracking(0.05)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(scheme == .dark
                      ? Color.white.opacity(0.04)
                      : Color.black.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(scheme == .dark
                                ? Color.white.opacity(0.06)
                                : Color.black.opacity(0.06), lineWidth: 0.5)
                )
        )
    }

    private var resetCountdown: String {
        let secondsAhead = sample.resetsAt.timeIntervalSinceNow
        if secondsAhead <= 0 { return "now" }
        let totalMinutes = Int(secondsAhead / 60)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours <= 0 {
            return "in \(minutes)m"
        }
        if hours < 24 {
            return "in \(hours)h \(minutes)m"
        }
        let days = hours / 24
        let remHours = hours % 24
        return "in \(days)d \(remHours)h"
    }
}

// MARK: - Sparkline

private struct Sparkline: View {
    let values: [Double]
    let color: Color

    var body: some View {
        GeometryReader { geo in
            Path { path in
                guard values.count >= 2 else { return }
                let maxValue = max(values.max() ?? 1, 1)
                let stepX = geo.size.width / CGFloat(values.count - 1)
                for (index, value) in values.enumerated() {
                    let x = CGFloat(index) * stepX
                    let y = geo.size.height - (CGFloat(value) / CGFloat(maxValue)) * (geo.size.height - 1) - 0.5
                    if index == 0 {
                        path.move(to: CGPoint(x: x, y: y))
                    } else {
                        path.addLine(to: CGPoint(x: x, y: y))
                    }
                }
            }
            .stroke(color.opacity(0.85), style: StrokeStyle(lineWidth: 1, lineCap: .round, lineJoin: .round))
        }
    }
}
