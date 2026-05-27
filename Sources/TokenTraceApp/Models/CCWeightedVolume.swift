import Foundation

/// Relative attribution proxy for a Claude Code message's contribution to
/// subscription quota burn. Anthropic does not publish the subscription
/// quota formula, so we use public pay-as-you-go API pricing ratios as the
/// closest available proxy. Opus and Sonnet share the same per-token ratios
/// within their families (Opus is ~5× Sonnet at every component, so the
/// *ratio* between components is the same), making one weight set good for
/// both.
///
/// Source: Anthropic API pricing snapshot 2026-05-27 (Claude 4 family).
/// Update these constants when pricing materially shifts; the chart and any
/// derived totals will reflect the new weights immediately.
///
/// The number this produces is *not* a dollar cost and *not* a direct
/// measure of subscription quota burn. UI surfaces should label it
/// "weighted tokens" or "weighted token volume".
enum CCWeightedVolume {
    static let inputWeight:         Double = 1.0
    static let outputWeight:        Double = 5.0
    static let cacheCreationWeight: Double = 1.25
    static let cacheReadWeight:     Double = 0.1

    /// Weighted total of the four token components.
    /// Returns `input·1.0 + output·5.0 + cacheCreation·1.25 + cacheRead·0.1`.
    static func weightedTotal(
        input: Int,
        output: Int,
        cacheCreation: Int,
        cacheRead: Int
    ) -> Double {
        return Double(input)         * inputWeight
            + Double(output)         * outputWeight
            + Double(cacheCreation)  * cacheCreationWeight
            + Double(cacheRead)      * cacheReadWeight
    }
}
