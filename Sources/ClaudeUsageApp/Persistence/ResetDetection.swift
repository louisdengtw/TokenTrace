import Foundation

struct ResetEvent: Equatable, Sendable {
    let displayTimestamp: Date
}

enum ResetDetection {
    static func detect(_ samples: [UsageSample]) -> [ResetEvent] {
        guard samples.count >= 2 else { return [] }
        var events: [ResetEvent] = []
        events.reserveCapacity(samples.count - 1)
        for i in 1..<samples.count {
            let previous = samples[i - 1]
            let current = samples[i]
            if current.resetsAt > previous.resetsAt {
                events.append(ResetEvent(displayTimestamp: previous.resetsAt))
            }
        }
        return events
    }
}
