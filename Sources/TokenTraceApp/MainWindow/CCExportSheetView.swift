import AppKit
import SwiftUI

struct CCExportSheetView: View {
    @ObservedObject var usageManager: UsageManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Claude Code Activity Report"
    @State private var format: ReportFormat = .pdf
    @State private var range: RangeSelection = .preset(.last7d)
    @State private var includeSubscriptionOverlay: Bool = true
    @State private var includeProjectTotals: Bool = true

    @State private var isSaving: Bool = false
    @State private var saveError: String?

    private var ccStore: CCUsageStore { usageManager.ccStore }
    private var usageStore: UsageStore { usageManager.store }

    /// The earlier of either store's oldest record, so the `All` preset
    /// resolves correctly and the cwd list reflects the full range.
    private var oldestSample: Date? {
        let a = usageStore.oldestTimestamp()
        let b = ccStore.oldestCCMessageTimestamp()
        switch (a, b) {
        case (nil, nil):       return nil
        case (let x?, nil):    return x
        case (nil, let x?):    return x
        case (let x?, let y?): return min(x, y)
        }
    }

    private var resolvedRange: (start: Date, end: Date) {
        range.resolved(now: Date(), oldestSample: oldestSample)
    }

    private var bucketForRange: CCUsageStore.TimeBucket {
        let days = resolvedRange.end.timeIntervalSince(resolvedRange.start) / 86400
        if days <= 1 { return .hour }
        if days <= 30 { return .day }
        return .week
    }

    /// Cwds observed within the selected range. Re-derived from
    /// `tokensByProject` (which already applies worktree fold + alias merge)
    /// so the displayed list matches what will be in the report.
    private var observedCwdsInRange: [String] {
        let options = CCUsageStore.QueryOptions(
            displayNameDepth: AppSettings.ccProjectNameDepth,
            mergeWorktrees: AppSettings.ccMergeWorktrees,
            workspaceRoot: AppSettings.ccProjectWorkspaceRootExpanded
        )
        let series = ccStore.tokensByProject(
            from: resolvedRange.start,
            to: resolvedRange.end,
            bucket: bucketForRange,
            options: options
        )
        return series.map { $0.displayName }
    }

    private var hasDataInRange: Bool {
        !observedCwdsInRange.isEmpty
    }

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
                        RangePickerView(selection: $range, oldestSample: oldestSample)
                    }

                    field("Include") {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Project totals + mix breakdown", isOn: $includeProjectTotals)
                            Toggle("Subscription utilisation overlay", isOn: $includeSubscriptionOverlay)
                        }
                        .toggleStyle(.checkbox)
                        .font(.system(size: 11))
                    }

                    field("Projects in range (\(observedCwdsInRange.count))") {
                        projectsList
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

    @ViewBuilder
    private var projectsList: some View {
        if observedCwdsInRange.isEmpty {
            Text("No Claude Code activity in the selected range.")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(observedCwdsInRange, id: \.self) { name in
                    Text(name)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                }
                Text("All observed projects in the selected range are included. Per-project filtering is not in v1.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if isSaving {
                ProgressView().controlSize(.small)
                Text("Rendering…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else if let saveError {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                    .font(.system(size: 11))
                Text(saveError)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            Button("Save…") { saveTapped() }
                .keyboardShortcut(.defaultAction)
                .disabled(!hasDataInRange || isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    private func saveTapped() {
        saveError = nil
        let (start, end) = resolvedRange

        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = defaultFilename(start: start, end: end, format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let result = panel.runModal()
        guard result == .OK, let url = panel.url else {
            // User cancelled — keep sheet open with selections preserved.
            return
        }

        let request = CCReportRequest(
            title: title.isEmpty ? "Claude Code Activity Report" : title,
            range: range,
            includeOverlay: includeSubscriptionOverlay,
            includeProjectTotals: includeProjectTotals
        )
        let dbPath = (try? UsageStore.defaultDatabaseURL().path) ?? "(unknown)"
        let generator = CCReportGenerator(ccStore: ccStore, usageStore: usageStore)
        let chosenFormat = format

        isSaving = true
        Task { @MainActor in
            defer { isSaving = false }
            do {
                let html = try generator.generateHTML(request: request, dbPath: dbPath)
                switch chosenFormat {
                case .html:
                    try html.write(to: url, atomically: true, encoding: .utf8)
                case .pdf:
                    let pdfData = try await PDFRenderer.renderHTMLToPDF(html: html)
                    try pdfData.write(to: url, options: .atomic)
                }
                NSWorkspace.shared.open(url)
                dismiss()
            } catch {
                saveError = "Could not save report: \(error.localizedDescription)"
            }
        }
    }

    private func defaultFilename(start: Date, end: Date, format: ReportFormat) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return "claude-code-report-\(f.string(from: start))_to_\(f.string(from: end)).\(format.fileExtension)"
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
