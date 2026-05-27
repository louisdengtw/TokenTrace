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
/// Which Dashboard tab the user had selected last; restored on launch.
/// Persisted as the raw string in `AppSettings.lastDashboardTab`.
///
/// Note: a sibling enum `DashboardTabKey` exists locally in
/// `DashboardView.swift` (added during the prototype phase). Both have the
/// same string cases and will be unified when the proper TabView refactor
/// lands in claude-code-usage group 11.
enum DashboardTab: String, Codable, Sendable {
    case subscription
    case claudeCode
}

enum AppSettings {
    private static let defaults = UserDefaults.standard
    private static let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "AppSettings")

    private enum Key {
        static let notificationsEnabled = "notificationsEnabled"
        static let openAtLoginEnabled = "openAtLoginEnabled"
        static let dashboardRangeSelection = "dashboardRangeSelection"
        static let lastDashboardTab = "lastDashboardTab"
        static let ccProjectNameDepth = "ccProjectNameDepth"
        static let ccMergeWorktrees = "ccMergeWorktrees"
    }

    static var notificationsEnabled: Bool {
        get { defaults.bool(forKey: Key.notificationsEnabled) }
        set { defaults.set(newValue, forKey: Key.notificationsEnabled) }
    }

    static var openAtLoginEnabled: Bool {
        get { defaults.bool(forKey: Key.openAtLoginEnabled) }
        set { defaults.set(newValue, forKey: Key.openAtLoginEnabled) }
    }

    /// How many trailing path components to use when synthesising a project's
    /// display name from its `cwd`. Default `1` keeps labels compact
    /// (e.g. `/Users/x/workspace/TokenTrace` → "TokenTrace"); set to `2` for
    /// monorepo-style uniqueness ("workspace/TokenTrace"). User-set aliases
    /// always override this.
    static var ccProjectNameDepth: Int {
        get {
            let raw = defaults.integer(forKey: Key.ccProjectNameDepth)
            return raw == 0 ? 1 : raw  // 0 == "never set"
        }
        set {
            defaults.set(max(1, min(3, newValue)), forKey: Key.ccProjectNameDepth)
        }
    }

    /// When true (default), cwds containing a `.worktree` or `.worktrees`
    /// path segment fold into the parent path, so a `repo/.worktree/branch`
    /// worktree merges into `repo`'s aggregated row.
    static var ccMergeWorktrees: Bool {
        get {
            // UserDefaults.bool defaults to false for missing keys, but we
            // want "missing" → true. Probe for existence first.
            if defaults.object(forKey: Key.ccMergeWorktrees) == nil {
                return true
            }
            return defaults.bool(forKey: Key.ccMergeWorktrees)
        }
        set {
            defaults.set(newValue, forKey: Key.ccMergeWorktrees)
        }
    }

    /// Last-active Dashboard tab. Missing or unrecognised values fall back to
    /// `.subscription` (the original single-tab view). Stored as the raw
    /// string so adding a new tab in the future is forward-compatible.
    static var lastDashboardTab: DashboardTab {
        get {
            guard let raw = defaults.string(forKey: Key.lastDashboardTab),
                  let tab = DashboardTab(rawValue: raw) else {
                return .subscription
            }
            return tab
        }
        set {
            defaults.set(newValue.rawValue, forKey: Key.lastDashboardTab)
        }
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
