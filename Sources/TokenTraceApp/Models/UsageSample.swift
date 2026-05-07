import Foundation

struct UsageSample: Equatable, Sendable {
    let ts: Date
    let bucket: Bucket
    let util: Double
    let resetsAt: Date
}
