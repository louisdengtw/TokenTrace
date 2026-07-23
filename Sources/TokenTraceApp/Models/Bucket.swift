import Foundation

/// Usage window identifier. The two fixed windows come from the top-level
/// API keys; model-scoped weekly windows come from the `limits[]` array and
/// carry the server-provided model display name (e.g. "Fable").
enum Bucket: Hashable, Codable, Sendable {
    case fiveHour
    case sevenDay
    case weeklyScoped(model: String)

    /// Stable string form used as the SQLite `bucket` column value and the
    /// report section id. Scoped buckets serialize as `weekly_scoped:<model>`.
    var key: String {
        switch self {
        case .fiveHour: return "five_hour"
        case .sevenDay: return "seven_day"
        case .weeklyScoped(let model): return "weekly_scoped:\(model)"
        }
    }

    /// Legacy pre-limits[] storage key for the Sonnet scoped series. Old rows
    /// keep this key on disk; queries for `.weeklyScoped("Sonnet")` match both.
    static let legacySonnetKey = "seven_day_sonnet"

    init?(key: String) {
        switch key {
        case "five_hour": self = .fiveHour
        case "seven_day": self = .sevenDay
        case Self.legacySonnetKey: self = .weeklyScoped(model: "Sonnet")
        default:
            guard key.hasPrefix("weekly_scoped:") else { return nil }
            let model = String(key.dropFirst("weekly_scoped:".count))
            guard !model.isEmpty else { return nil }
            self = .weeklyScoped(model: model)
        }
    }

    init(from decoder: Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        guard let bucket = Bucket(key: key) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath,
                debugDescription: "unknown bucket key '\(key)'"))
        }
        self = bucket
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}
