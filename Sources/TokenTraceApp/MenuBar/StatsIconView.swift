import AppKit
import SwiftUI

/// Stats-style menu bar icon: three stacked label/percentage columns.
/// Rendered to an `NSImage` via `ImageRenderer` and assigned to the `NSStatusBarButton`.
struct StatsIconView: View {
    /// One model-scoped weekly column, labeled by the first three letters of
    /// the server-provided model name (e.g. "FAB" for Fable).
    struct ScopedColumn: Identifiable {
        let model: String
        let value: Double?
        var id: String { model }
        var label: String { String(model.prefix(3)).uppercased() }
    }

    /// `nil` percentages render as a dash placeholder so the icon stays
    /// the same width before the first poll has landed.
    let fiveHour: Double?
    let sevenDay: Double?
    var scopedColumns: [ScopedColumn] = []

    /// `ImageRenderer` does not honor `.environment(\.colorScheme)`, so the
    /// caller passes the current scheme explicitly to drive label / value contrast.
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 7) {
            column(label: "5H",  value: fiveHour)
            column(label: "7D",  value: sevenDay)
            ForEach(scopedColumns) { scoped in
                column(label: scoped.label, value: scoped.value)
            }
        }
        .padding(.horizontal, 1)
    }

    @ViewBuilder
    private func column(label: String, value: Double?) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 8, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(labelColor)
            Text(format(value))
                .font(.system(size: 10, weight: .semibold))
                .tracking(-0.2)
                .foregroundStyle(valueColor(for: value))
                .monospacedDigit()
        }
    }

    private func format(_ value: Double?) -> String {
        guard let value else { return "—" }
        return "\(Int(value.rounded()))%"
    }

    private var labelColor: Color {
        scheme == .dark ? Color.white.opacity(0.65) : Color.black.opacity(0.55)
    }

    private func valueColor(for value: Double?) -> Color {
        guard let value else {
            return scheme == .dark ? Color.white.opacity(0.55) : Color.black.opacity(0.45)
        }
        return UsageColor.color(for: value, scheme: scheme)
    }
}

/// Threshold-based usage color shared across status item, popover, and dashboard.
/// Mirrors the values agreed in the `claude.ai/design` mockups.
enum UsageColor {
    static func color(for percentage: Double, scheme: ColorScheme) -> Color {
        let pct = Int(percentage.rounded())
        if pct >= 90 {
            return scheme == .dark
                ? Color(red: 1.00,  green: 0.412, blue: 0.380)   // #FF6961
                : Color(red: 0.898, green: 0.282, blue: 0.302)   // #E5484D
        }
        if pct >= 75 {
            return scheme == .dark
                ? Color(red: 1.00,  green: 0.702, blue: 0.251)   // #FFB340
                : Color(red: 0.910, green: 0.576, blue: 0.047)   // #E8930C
        }
        if pct >= 50 {
            return scheme == .dark
                ? Color(red: 1.00,  green: 0.839, blue: 0.039)   // #FFD60A
                : Color(red: 0.722, green: 0.525, blue: 0.043)   // #B8860B
        }
        return scheme == .dark
            ? Color(red: 0.204, green: 0.780, blue: 0.349)       // #34C759
            : Color(red: 0.157, green: 0.651, blue: 0.271)       // #28A745
    }
}
