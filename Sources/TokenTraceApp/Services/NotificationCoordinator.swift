import Foundation
import OSLog
import UserNotifications

@MainActor
final class NotificationCoordinator {
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "Notifications")
    private let center = UNUserNotificationCenter.current()

    @discardableResult
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        do {
            return try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            return false
        }
    }

    func deliverThresholdCrossed(_ threshold: Int) {
        guard AppSettings.notificationsEnabled else { return }

        let content = UNMutableNotificationContent()
        content.title = "Claude Usage Alert"
        content.body = "5-hour session usage just crossed \(threshold)%."
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "threshold-\(threshold)-\(Int(Date().timeIntervalSince1970))",
            content: content,
            trigger: nil
        )

        center.add(request) { [log] error in
            if let error {
                log.error("notification add failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
