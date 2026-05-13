import Foundation
import OSLog

/// Thin UserDefaults wrapper for app-level state.
///
/// Two layers live here:
///   • Settings-tab toggles (per app-settings spec): `notificationsEnabled`,
///     `openAtLoginEnabled`. Threshold list is intentionally NOT exposed —
///     fixed in v1 per the same spec.
///   • UI state that needs to survive launches but is not a user-facing
///     preference: `dashboardRangeSelection` (per usage-dashboard spec —
///     "Range selection persists across launches"). The Export sheet does
///     NOT persist its picker state by design (usage-export spec — every
///     open resets to fixed defaults).
enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "AppSettings")

    private enum Key {
        static let notificationsEnabled = "notificationsEnabled"
        static let openAtLoginEnabled = "openAtLoginEnabled"
        static let dashboardRangeSelection = "dashboardRangeSelection"
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    static var openAtLoginEnabled: Bool {
        get { defaults.bool(forKey: Key.openAtLoginEnabled) }
        set { defaults.set(newValue, forKey: Key.openAtLoginEnabled) }
    }

    /// Last-used Dashboard range. Missing or undecodable values fall back to
    /// `.preset(.last7d)` and the bad value is overwritten on the next write.
    static var dashboardRangeSelection: RangeSelection {
        get {
            guard let data = defaults.data(forKey: Key.dashboardRangeSelection) else {
                return .default
            }
            do {
                return try JSONDecoder().decode(RangeSelection.self, from: data)
            } catch {
                log.error("dashboardRangeSelection decode failed; falling back to default. error=\(String(describing: error), privacy: .public)")
                return .default
            }
        }
        set {
            do {
                let data = try JSONEncoder().encode(newValue)
                defaults.set(data, forKey: Key.dashboardRangeSelection)
            } catch {
                log.error("dashboardRangeSelection encode failed: \(String(describing: error), privacy: .public)")
            }
        }
    }
}
