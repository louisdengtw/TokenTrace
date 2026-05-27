#if canImport(AppKit)
import AppKit
import SwiftUI
import XCTest
@testable import TokenTraceApp

/// Renders the four empty-data states described in spec scenarios
/// 15.1–15.4 to PNG files under /tmp so I can self-verify the layout
/// without launching the app and stepping through state combos by hand.
///
/// Not a pass/fail correctness test — it always passes as long as the
/// view doesn't crash. Inspect the PNGs visually.
final class CCUsageViewEmptyStateSnapshotTests: XCTestCase {
    private var ccDBURL: URL!
    private var subDBURL: URL!
    private var ccStore: CCUsageStore!
    private var usageStore: UsageStore!
    private var ingester: CCUsageIngester!

    /// 2026-05-15 → 2026-05-26, 11-day window.
    private let domainStart = Date(timeIntervalSince1970: 1_747_267_200)
    private let domainEnd   = Date(timeIntervalSince1970: 1_748_217_600)

    override func setUpWithError() throws {
        let tmp = FileManager.default.temporaryDirectory
        ccDBURL = tmp.appendingPathComponent("snap-cc-\(UUID().uuidString).sqlite")
        subDBURL = tmp.appendingPathComponent("snap-sub-\(UUID().uuidString).sqlite")
        ccStore = try CCUsageStore(url: ccDBURL)
        usageStore = try UsageStore(url: subDBURL)
        ingester = CCUsageIngester(store: ccStore)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: ccDBURL)
        try? FileManager.default.removeItem(at: subDBURL)
    }

    // MARK: - Fixtures

    private func insertCCMessages() {
        let rows: [CCMessage] = (0..<8).map { i in
            CCMessage(
                uuid: "m\(i)-\(UUID().uuidString)",
                ts: domainStart.addingTimeInterval(Double(i) * 86400 + 3600),
                cwd: "/Users/x/workspace/TokenTrace",
                model: i % 2 == 0 ? "claude-opus-4-7" : "claude-sonnet-4-6",
                inputTokens: 400 + i * 50,
                outputTokens: 1200 + i * 100,
                cacheCreationTokens: 80,
                cacheReadTokens: 2000,
                sessionId: "s\(i)",
                requestId: nil,
                isSidechain: false,
                filePath: "/fixture/s\(i).jsonl"
            )
        }
        _ = ccStore.insertMessages(rows)
    }

    private func insertUtilSamples() {
        for i in 0..<11 {
            let ts = domainStart.addingTimeInterval(Double(i) * 86400 + 3 * 3600)
            let util = 30 + Double(i % 5) * 12   // 30, 42, 54, 66, 78, back to 30…
            let sample = UsageSample(
                ts: ts,
                bucket: .fiveHour,
                util: util,
                resetsAt: ts.addingTimeInterval(5 * 3600)
            )
            usageStore.insert(samples: [sample])
        }
    }

    // MARK: - Render helper

    @MainActor
    private func render(_ label: String) throws {
        let view = ZStack {
            // Opaque dark backdrop so `.secondary` / `.tertiary` foreground
            // styles resolve to visible colours; in the headless XCTest
            // process the default light environment renders them effectively
            // transparent against a transparent backdrop.
            Color(red: 0.11, green: 0.11, blue: 0.12)
            CCUsageView(
                domain: domainStart...domainEnd,
                ccStore: ccStore,
                ccIngester: ingester,
                usageStore: usageStore
            )
        }
        .preferredColorScheme(.dark)
        .frame(width: 920, height: 760)

        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: 920, height: 760)

        // Give the ScrollView's content one runloop tick to lay out so
        // its lazy children actually exist when we ask for the bitmap.
        host.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))

        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else {
            return XCTFail("Could not create bitmap rep for \(label)")
        }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else {
            return XCTFail("Could not encode PNG for \(label)")
        }
        let outURL = URL(fileURLWithPath: "/tmp/cc-empty-state-\(label).png")
        try png.write(to: outURL)
    }

    // MARK: - Cases (15.1 — 15.4)

    @MainActor
    func test_15_1_ccDataOnly_noUtil() throws {
        insertCCMessages()
        try render("15_1_cc_only")
    }

    @MainActor
    func test_15_2_utilOnly_noCC() throws {
        // Util in range, CC outside range. The spec's 15.2 intent is
        // "user has CC history but none in the current window"; if CC is
        // globally empty we fall through to 15.4 onboarding instead.
        let oldTs = domainStart.addingTimeInterval(-90 * 86400)
        let rows: [CCMessage] = (0..<3).map { i in
            CCMessage(
                uuid: "om\(i)-\(UUID().uuidString)",
                ts: oldTs.addingTimeInterval(Double(i) * 3600),
                cwd: "/Users/x/workspace/Foo",
                model: "claude-sonnet-4-6",
                inputTokens: 100,
                outputTokens: 200,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                sessionId: "old\(i)",
                requestId: nil,
                isSidechain: false,
                filePath: "/fixture/old\(i).jsonl"
            )
        }
        _ = ccStore.insertMessages(rows)
        insertUtilSamples()
        try render("15_2_util_only")
    }

    @MainActor
    func test_15_3_neitherInRange() throws {
        // Insert CC OUTSIDE the active range so cc_message exists globally
        // (hasAnyCCData=true) but the range itself is empty — exercises
        // the placeholder path rather than the onboarding card.
        let oldTs = domainStart.addingTimeInterval(-90 * 86400)
        let rows: [CCMessage] = (0..<3).map { i in
            CCMessage(
                uuid: "om\(i)-\(UUID().uuidString)",
                ts: oldTs.addingTimeInterval(Double(i) * 3600),
                cwd: "/Users/x/workspace/Foo",
                model: "claude-sonnet-4-6",
                inputTokens: 100,
                outputTokens: 200,
                cacheCreationTokens: 0,
                cacheReadTokens: 0,
                sessionId: "old\(i)",
                requestId: nil,
                isSidechain: false,
                filePath: "/fixture/old\(i).jsonl"
            )
        }
        _ = ccStore.insertMessages(rows)
        try render("15_3_neither_in_range")
    }

    @MainActor
    func test_15_4_globallyEmpty_onboarding() throws {
        // No inserts — cc_message is empty globally.
        try render("15_4_onboarding")
    }
}
#endif
