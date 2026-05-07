import Foundation

enum Bucket: String, CaseIterable, Codable, Sendable {
    case fiveHour = "five_hour"
    case sevenDay = "seven_day"
    case sevenDaySonnet = "seven_day_sonnet"
}
