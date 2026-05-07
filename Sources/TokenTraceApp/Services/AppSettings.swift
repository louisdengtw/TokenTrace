import Foundation

/// Thin UserDefaults wrapper for the toggles in the Settings tab.
///
/// Threshold list (25/50/75/90) is intentionally NOT exposed here — it is fixed in v1
/// per the app-settings spec.
enum AppSettings {
    private static let defaults = UserDefaults.standard

    private enum Key {
        static let notificationsEnabled = "notificationsEnabled"
        static let openAtLoginEnabled = "openAtLoginEnabled"
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    static var openAtLoginEnabled: Bool {
        get { defaults.bool(forKey: Key.openAtLoginEnabled) }
        set { defaults.set(newValue, forKey: Key.openAtLoginEnabled) }
    }
}
