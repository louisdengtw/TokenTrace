import Foundation

/// Quick-access presets in the range picker UI.
enum RangePreset: String, CaseIterable, Codable, Identifiable, Sendable {
    case last24h
    case last7d
    case last30d
    case all

    var id: String { rawValue }

    var label: String {
        switch self {
        case .last24h: return "24h"
        case .last7d:  return "7d"
        case .last30d: return "30d"
        case .all:     return "All"
        }
    }
}

/// The unified range model shared by Dashboard and Export. Either one of the
/// quick-access presets, or an explicit custom From/To window.
enum RangeSelection: Equatable, Sendable {
    case preset(RangePreset)
    case custom(from: Date, to: Date)

    static let `default`: RangeSelection = .preset(.last7d)

    /// Resolve to absolute `(start, end)` dates the store can be queried with.
    /// `now` is injected so callers can be deterministic in tests; `oldestSample`
    /// is consulted only for the `.all` preset.
    func resolved(now: Date, oldestSample: Date?) -> (start: Date, end: Date) {
        switch self {
        case .preset(.last24h):
            return (now.addingTimeInterval(-24 * 3600), now)
        case .preset(.last7d):
            return (now.addingTimeInterval(-7 * 86400), now)
        case .preset(.last30d):
            return (now.addingTimeInterval(-30 * 86400), now)
        case .preset(.all):
            return (oldestSample ?? now.addingTimeInterval(-86400), now)
        case .custom(let from, let to):
            // Defensive: clamp to non-inverted ordering. The widget enforces this
            // interactively, but persisted-but-corrupted values could land here.
            return from <= to ? (from, to) : (to, from)
        }
    }

    /// Short human description used as a fallback caption on the Dashboard.
    var trendDescription: String {
        switch self {
        case .preset(.last24h): return "Trend across last 24 hours"
        case .preset(.last7d):  return "Trend across last 7 days"
        case .preset(.last30d): return "Trend across last 30 days"
        case .preset(.all):     return "Trend across all time"
        case .custom(let from, let to):
            let fmt = DateFormatter()
            fmt.dateFormat = "yyyy-MM-dd"
            return "Trend \(fmt.string(from: from)) → \(fmt.string(from: to))"
        }
    }
}

// MARK: - Codable

extension RangeSelection: Codable {
    private enum CodingKeys: String, CodingKey { case kind, preset, from, to }
    private enum Kind: String, Codable { case preset, custom }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try c.decode(Kind.self, forKey: .kind)
        switch kind {
        case .preset:
            self = .preset(try c.decode(RangePreset.self, forKey: .preset))
        case .custom:
            let from = try c.decode(Date.self, forKey: .from)
            let to = try c.decode(Date.self, forKey: .to)
            self = .custom(from: from, to: to)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .preset(let p):
            try c.encode(Kind.preset, forKey: .kind)
            try c.encode(p, forKey: .preset)
        case .custom(let from, let to):
            try c.encode(Kind.custom, forKey: .kind)
            try c.encode(from, forKey: .from)
            try c.encode(to, forKey: .to)
        }
    }
}
