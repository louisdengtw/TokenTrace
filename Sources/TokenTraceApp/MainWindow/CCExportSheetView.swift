import AppKit
import SwiftUI

// Prototype-only stub of the Claude Code export sheet. Demonstrates the
// intended UX for tab-aware Export Report — what a CC export would
// configure — without actually generating a file. Replaced by the real
// implementation when the usage-export capability is extended in a
// follow-up change.

struct CCExportSheetView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Claude Code Activity Report"
    @State private var format: ReportFormat = .pdf
    @State private var range: RangeSelection = .preset(.last7d)
    @State private var includeSubscriptionOverlay: Bool = true
    @State private var includeProjectTotals: Bool = true
    @State private var allProjectsSelected: Bool = true

    private let stubObservedCwds: [String] = [
        "/Users/louisdeng/workspace/TokenTrace",
        "/Users/louisdeng/workspace/bmo-analysis",
        "/Users/louisdeng/workspace/DynaRAG",
        "/Users/louisdeng/workspace/GPSMock",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    field("Title") {
                        TextField("", text: $title)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12))
                    }

                    field("Format") {
                        Picker("", selection: $format) {
                            Text("PDF").tag(ReportFormat.pdf)
                            Text("HTML").tag(ReportFormat.html)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    field("Date range") {
                        RangePickerView(selection: $range, oldestSample: nil)
                    }

                    field("Include") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Project totals + mix breakdown", isOn: $includeProjectTotals)
                            Toggle("Subscription utilisation overlay", isOn: $includeSubscriptionOverlay)
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    }

                    field("Projects") {
                        VStack(alignment: .leading, spacing: 6) {
                            Toggle("All projects", isOn: $allProjectsSelected)
                                .toggleStyle(.checkbox)
                                .font(.system(size: 11))
                            ForEach(stubObservedCwds, id: \.self) { cwd in
                                Text(cwd)
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.leading, 22)
                            }
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }

            Divider()

            footer
        }
        .frame(width: 480, height: 540)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export Claude Code report")
                .font(.system(size: 13, weight: .semibold))
            Text("Generate a portable HTML or PDF report of project-level CC usage")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .font(.system(size: 10))
            Text("Prototype — Save is wired with the data layer in claude-code-usage group 12+")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
            Spacer()
            Button("Cancel") { dismiss() }
                .buttonStyle(.bordered)
            Button("Save…") { }
                .buttonStyle(.borderedProminent)
                .disabled(true)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            content()
        }
    }
}
