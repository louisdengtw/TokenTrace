import SwiftUI

struct PopoverView: View {
    @ObservedObject var usageManager: UsageManager
    let openMainWindow: (MainTab) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Claude Usage")
                .font(.headline)

            if usageManager.sessionExpired {
                Label("Session expired — please re-sign in", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.callout)
            } else if !usageManager.hasFetchedData {
                Text(usageManager.isLoading ? "Loading…" : "Waiting for first poll…")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(orderedBuckets, id: \.self) { bucket in
                    if let sample = usageManager.latestSample[bucket] {
                        BucketRow(label: label(for: bucket), sample: sample)
                    }
                }
            }

            if let message = usageManager.errorMessage, !usageManager.sessionExpired {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            Divider()

            HStack {
                Button("Open Main Window") { openMainWindow(.dashboard) }
                Spacer()
                Button("Settings…") { openMainWindow(.settings) }
            }
        }
        .padding(16)
        .frame(width: 320)
    }

    private var orderedBuckets: [Bucket] {
        var buckets: [Bucket] = [.fiveHour, .sevenDay]
        if usageManager.hasWeeklySonnet {
            buckets.append(.sevenDaySonnet)
        }
        return buckets
    }

    private func label(for bucket: Bucket) -> String {
        switch bucket {
        case .fiveHour: return "5-hour session"
        case .sevenDay: return "7-day overall"
        case .sevenDaySonnet: return "7-day Sonnet"
        }
    }
}

private struct BucketRow: View {
    let label: String
    let sample: UsageSample

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label).font(.subheadline)
                Spacer()
                Text("\(Int(sample.util.rounded()))%")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: min(sample.util, 100), total: 100)
                .progressViewStyle(.linear)
        }
    }
}
