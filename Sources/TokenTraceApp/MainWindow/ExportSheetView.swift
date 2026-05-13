import AppKit
import SwiftUI

/// Modal sheet for producing a self-contained usage report (HTML or PDF).
///
/// Per the usage-export spec this sheet is **stateless across opens** — every
/// time the user invokes it, fields reset to fixed defaults (title, format,
/// last-7d, `five_hour` + `seven_day` selected). It deliberately does NOT
/// read or write `AppSettings` to prevent silent reuse of a previous period.
struct ExportSheetView: View {
    @ObservedObject var usageManager: UsageManager
    @Environment(\.dismiss) private var dismiss

    @State private var title: String = "Claude Usage Report"
    @State private var format: ReportFormat = .pdf
    @State private var range: RangeSelection = .preset(.last7d)
    @State private var fiveHourEnabled: Bool = true
    @State private var sevenDayEnabled: Bool = true
    @State private var sonnetEnabled: Bool = false

    @State private var saveError: String?
    @State private var isSaving: Bool = false

    // Cached for "All" preset resolution and validation.
    private var oldestSample: Date? { usageManager.store.oldestTimestamp() }

    private var selectedBuckets: Set<Bucket> {
        var s: Set<Bucket> = []
        if fiveHourEnabled { s.insert(.fiveHour) }
        if sevenDayEnabled { s.insert(.sevenDay) }
        if sonnetEnabled   { s.insert(.sevenDaySonnet) }
        return s
    }

    private var totalSamplesInRange: Int {
        let (start, end) = range.resolved(now: Date(), oldestSample: oldestSample)
        return selectedBuckets.reduce(0) { running, bucket in
            running + usageManager.store.query(bucket: bucket, from: start, to: end).count
        }
    }

    private enum SaveBlockReason: Equatable {
        case noBuckets
        case noSamples
    }

    private var saveBlock: SaveBlockReason? {
        if selectedBuckets.isEmpty { return .noBuckets }
        if totalSamplesInRange == 0 { return .noSamples }
        return nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            field(label: "Title") {
                TextField("", text: $title)
                    .textFieldStyle(.roundedBorder)
            }
            field(label: "Format") {
                Picker("", selection: $format) {
                    ForEach(ReportFormat.allCases) { f in
                        Text(f.label).tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 200)
            }
            field(label: "Range") {
                RangePickerView(selection: $range, oldestSample: oldestSample)
            }
            field(label: "Buckets") {
                VStack(alignment: .leading, spacing: 4) {
                    Toggle("5-hour Window",          isOn: $fiveHourEnabled)
                    Toggle("7-day Window",           isOn: $sevenDayEnabled)
                    Toggle("7-day Window — Sonnet",  isOn: $sonnetEnabled)
                }
                .toggleStyle(.checkbox)
            }
            if let block = saveBlock {
                blockHint(block)
            }
            if let saveError {
                Text(saveError)
                    .foregroundStyle(.red)
                    .font(.system(size: 11))
                    .lineLimit(3)
            }
            actions
        }
        .padding(22)
        .frame(width: 460)
    }

    // MARK: - Subviews

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export Usage Report")
                .font(.system(size: 16, weight: .semibold))
                .tracking(-0.2)
            Text("Generate a self-contained report from your local usage data.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func field<Content: View>(
        label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.4)
            content()
        }
    }

    private func blockHint(_ reason: SaveBlockReason) -> some View {
        let text: String = {
            switch reason {
            case .noBuckets: return "Select at least one bucket"
            case .noSamples: return "No samples in the selected range"
            }
        }()
        return HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private var actions: some View {
        HStack {
            if isSaving {
                ProgressView()
                    .controlSize(.small)
                Text("Rendering…")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
                .disabled(isSaving)
            Button("Save…") { saveTapped() }
                .keyboardShortcut(.defaultAction)
                .disabled(saveBlock != nil || isSaving)
        }
    }

    // MARK: - Save

    private func saveTapped() {
        saveError = nil
        let (start, end) = range.resolved(now: Date(), oldestSample: oldestSample)
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.utType]
        panel.nameFieldStringValue = defaultFilename(start: start, end: end, format: format)
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false

        let result = panel.runModal()
        guard result == .OK, let url = panel.url else {
            // User cancelled. Spec: keep sheet open with selections preserved.
            return
        }

        let request = ReportRequest(
            title: title.isEmpty ? "Claude Usage Report" : title,
            range: range,
            buckets: selectedBuckets
        )
        let dbPath = (try? UsageStore.defaultDatabaseURL().path) ?? "(unknown)"
        let generator = ReportGenerator(store: usageManager.store)
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
        return "claude-usage-report-\(f.string(from: start))_to_\(f.string(from: end)).\(format.fileExtension)"
    }
}
