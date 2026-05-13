import Foundation
import OSLog

/// Loader for the Chart.js library that ships inline inside every exported
/// HTML report. The asset is bundled at build time so reports remain
/// fully self-contained — no network access required to view them.
///
/// Pinned version: **Chart.js 4.4.1**
/// Source: https://cdn.jsdelivr.net/npm/chart.js@4.4.1/dist/chart.umd.min.js
/// Stored at: Sources/TokenTraceApp/Resources/chart.umd.min.js
/// SHA-256: d2af8974e95271638772e9e9524db5b9a6f58d6ec2d5d781400447b4a31c681e
///
/// To upgrade: replace the file, update the SHA-256 above, and re-run
/// `swift build`. Also re-run the cross-browser check from `usage-export`
/// tasks group 9 / 10.
enum ChartJSAsset {
    private static let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "ChartJSAsset")

    enum Error: Swift.Error {
        case notFoundInBundle
        case readFailed(underlying: Swift.Error)
    }

    /// Returns the full JavaScript source as a `String`, ready to be embedded
    /// inside a `<script>` tag in the exported HTML.
    static func bundledContents() throws -> String {
        guard let url = Bundle.module.url(
            forResource: "chart.umd.min",
            withExtension: "js",
            subdirectory: "Resources"
        ) else {
            log.error("Chart.js asset not found in module bundle")
            throw Error.notFoundInBundle
        }
        do {
            return try String(contentsOf: url, encoding: .utf8)
        } catch {
            log.error("Chart.js asset read failed: \(String(describing: error), privacy: .public)")
            throw Error.readFailed(underlying: error)
        }
    }
}
