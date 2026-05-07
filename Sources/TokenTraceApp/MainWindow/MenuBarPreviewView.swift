import SwiftUI

struct MenuBarPreviewView: View {
    @ObservedObject var usageManager: UsageManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Menu Bar Preview")
                .font(.title2.bold())

            VStack(alignment: .leading, spacing: 6) {
                Text("Live preview of the status item")
                    .font(.headline)
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.xaxis")
                        .foregroundStyle(menuBarColor)
                        .imageScale(.large)
                    Text(menuBarTitle)
                        .font(.body.monospacedDigit())
                        .foregroundStyle(menuBarColor)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Latest sample")
                    .font(.headline)
                if !usageManager.hasFetchedData {
                    Text(usageManager.isLoading
                         ? "Polling…"
                         : "No data yet — paste a cookie in Settings to begin polling.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(orderedBuckets, id: \.self) { bucket in
                        if let sample = usageManager.latestSample[bucket] {
                            BucketLine(label: label(for: bucket), sample: sample)
                        }
                    }
                }
            }

            Spacer()
        }
        .padding(20)
    }

    private var orderedBuckets: [Bucket] {
        var b: [Bucket] = [.fiveHour, .sevenDay]
        if usageManager.hasWeeklySonnet { b.append(.sevenDaySonnet) }
        return b
    }

    private func label(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour: return "5-hour session"
        case .sevenDay: return "7-day overall"
        case .sevenDaySonnet: return "7-day Sonnet"
        }
    }

    private var menuBarTitle: String {
        if usageManager.sessionExpired { return "⚠" }
        guard let s = usageManager.latestSample[.fiveHour], usageManager.hasFetchedData else {
            return "—"
        }
        return "\(Int(s.util.rounded()))%"
    }

    private var menuBarColor: Color {
        if usageManager.sessionExpired { return .orange }
        guard let s = usageManager.latestSample[.fiveHour], usageManager.hasFetchedData else {
            return .secondary
        }
        let pct = Int(s.util.rounded())
        switch pct {
        case ...50: return .green
        case 51...75: return .yellow
        case 76...90: return .orange
        default: return .red
        }
    }
}

private struct BucketLine: View {
    let label: String
    let sample: UsageSample
    var body: some View {
        HStack {
            Text(label)
                .frame(width: 140, alignment: .leading)
                .foregroundStyle(.secondary)
            ProgressView(value: min(sample.util, 100), total: 100)
            Text("\(Int(sample.util.rounded()))%")
                .font(.body.monospacedDigit())
                .frame(width: 44, alignment: .trailing)
        }
    }
}
