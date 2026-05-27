#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import TokenTraceApp

/// Renders CCUsageView at a few narrow widths with the maximum-N project
/// load (so the legend's overflow risk is realistic) to verify spec
/// scenario 16.3 — "chart legend should wrap or scroll instead of
/// overflowing."
///
/// Like the empty-state snapshot test, this is render-only — always
/// passes if the view doesn't crash. Inspect the PNGs visually.
final class CCUsageViewResizeSnapshotTests: XCTestCase {
    private var ccDBURL: URL!
    private var subDBURL: URL!
    private var ccStore: CCUsageStore!
    private var usageStore: UsageStore!
    private var ingester: CCUsageIngester!

    private let domainStart = Date(timeIntervalSince1970: 1_747_267_200)
    private let domainEnd   = Date(timeIntervalSince1970: 1_748_217_600)

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
        ccDBURL = tmp.appendingPathComponent("resize-cc-\(UUID().uuidString).sqlite")
        subDBURL = tmp.appendingPathComponent("resize-sub-\(UUID().uuidString).sqlite")
        ccStore = try CCUsageStore(url: ccDBURL)
        usageStore = try UsageStore(url: subDBURL)
        ingester = CCUsageIngester(store: ccStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ccDBURL)
        try? FileManager.default.removeItem(at: subDBURL)
    }

    /// Insert 8 distinct projects with believable name lengths — matches the
    /// `maxIndividualProjects` cap so the legend has the full chip count
    /// (anything more would fold into "Other (N)").
    private func insertEightProjects() {
        let projects = [
            "TokenTrace", "DynaRAG", "bmo-analysis", "telemetry-pipeline",
            "ClaudeUsageBar", "tinker-notebook", "ops-runbooks", "infra-grafana"
        ]
        var rows: [CCMessage] = []
        for (pIdx, name) in projects.enumerated() {
            for i in 0..<6 {
                rows.append(CCMessage(
                    uuid: "\(name)-\(i)-\(UUID().uuidString)",
                    ts: domainStart.addingTimeInterval(Double(i) * 86400 + 3600),
                    cwd: "/Users/x/workspace/\(name)",
                    model: i % 2 == 0 ? "claude-opus-4-7" : "claude-sonnet-4-6",
                    inputTokens: 300 + i * 40 + pIdx * 50,
                    outputTokens: 900 + i * 60 + pIdx * 40,
                    cacheCreationTokens: 60,
                    cacheReadTokens: 1500,
                    sessionId: "s-\(name)-\(i)",
                    requestId: nil,
                    isSidechain: false,
                    filePath: "/fixture/\(name)/s\(i).jsonl"
                ))
            }
        }
        _ = ccStore.insertMessages(rows)
    }

    private func insertUtilSamples() {
        for i in 0..<11 {
            let ts = domainStart.addingTimeInterval(Double(i) * 86400 + 3 * 3600)
            let util = 30 + Double(i % 5) * 12
            usageStore.insert(samples: [
                UsageSample(ts: ts, bucket: .fiveHour, util: util,
                            resetsAt: ts.addingTimeInterval(5 * 3600))
            ])
        }
    }

    @MainActor
    private func render(width: CGFloat, label: String) throws {
        let height: CGFloat = 760
        let view = ZStack {
            Color(red: 0.11, green: 0.11, blue: 0.12)
            CCUsageView(
                domain: domainStart...domainEnd,
                ccStore: ccStore,
                ccIngester: ingester,
                usageStore: usageStore
            )
        }
        .preferredColorScheme(.dark)
        .frame(width: width, height: height)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("Could not create bitmap rep for \(label)")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode PNG for \(label)")
        }
        let outURL = URL(fileURLWithPath: "/tmp/cc-resize-\(label).png")
        try png.write(to: outURL)
    }

    @MainActor
    func test_resizes_with_full_project_load() throws {
        insertEightProjects()
        insertUtilSamples()
        // Widths to probe: ~MainWindow default (920), comfortable (640),
        // pinched (500), narrow (400), and the smallest the user is
        // likely to drag the window to before frustration (320).
        for width in [CGFloat(920), 640, 500, 400, 320] {
            try render(width: width, label: "w\(Int(width))")
        }
    }
}
#endif
