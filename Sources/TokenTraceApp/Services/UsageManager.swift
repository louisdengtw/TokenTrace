import Foundation
import OSLog

@MainActor
final class UsageManager: ObservableObject {
    @Published private(set) var latestSample: [Bucket: UsageSample] = [:]
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var hasFetchedData: Bool = false
    @Published private(set) var hasWeeklySonnet: Bool = false
    @Published private(set) var sessionExpired: Bool = false
    @Published private(set) var sessionCookie: String = ""

    /// Cookie value pre-loaded from a `tokentrace://import?cookie=…` URL,
    /// awaiting explicit user "Save" in the Settings tab. Never auto-saved.
    @Published var pendingImportCookie: String?
    /// Error surfaced from an inbound URL-scheme call (malformed, missing
    /// parameter, undecodable). Cleared when consumed by the Settings UI.
    @Published var pendingImportError: String?

    /// Fixed in v1, ascending. See app-settings spec.
    static let notificationThresholds: [Int] = [25, 50, 75, 90]

    /// Composition root attaches a delivery handler (e.g., UNUserNotificationCenter wrapper).
    var onThresholdCrossed: ((Int) -> Void)?

    let store: UsageStore

    private let api: ClaudeAPI
    private let pollInterval: TimeInterval
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "UsageManager")

    private var pollTask: Task<Void, Never>?
    private var notifiedThresholdsThisWindow: Set<Int> = []
    private var lastFiveHourResetsAt: Date?

    init(api: ClaudeAPI = ClaudeAPI(), store: UsageStore, pollInterval: TimeInterval = 300) {
        self.api = api
        self.store = store
        self.pollInterval = pollInterval
        self.sessionCookie = CookieKeychain.read() ?? ""
    }

    /// Begin the polling loop. Fetches immediately, then every `pollInterval` seconds.
    func start() {
        pollTask?.cancel()
        let interval = pollInterval
        pollTask = Task { [weak self] in
            await self?.fetchOnce()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
                } catch {
                    return
                }
                await self?.fetchOnce()
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    /// Routes raw user input (raw cookie header, `Cookie:`-prefixed, or full
    /// curl command) through `CookieParser` before persisting to Keychain.
    /// Both the Settings paste field and the URL-scheme pre-fill path land here.
    @discardableResult
    func saveCookie(_ raw: String) -> Result<Void, CookieParserError> {
        switch CookieParser.parse(raw) {
        case .success(let parsed):
            CookieKeychain.save(parsed)
            sessionCookie = parsed
            sessionExpired = false
            errorMessage = nil
            Task { [weak self] in
                await self?.fetchOnce()
            }
            return .success(())
        case .failure(let error):
            return .failure(error)
        }
    }

    /// Called by the Settings UI after it has consumed a pending import value
    /// (either applied it to the paste field or surfaced its error).
    func consumePendingImport() {
        pendingImportCookie = nil
        pendingImportError = nil
    }

    func clearCookie() {
        CookieKeychain.delete()
        sessionCookie = ""
        latestSample = [:]
        hasFetchedData = false
        hasWeeklySonnet = false
        errorMessage = nil
        sessionExpired = false
        notifiedThresholdsThisWindow = []
        lastFiveHourResetsAt = nil
    }

    func fetchOnce() async {
        guard !sessionCookie.isEmpty else {
            if errorMessage == nil {
                errorMessage = "Session cookie not set"
            }
            return
        }
        isLoading = true
        defer { isLoading = false }

        do {
            let orgId = try await api.fetchOrgId(cookie: sessionCookie)
            let response = try await api.fetchUsage(cookie: sessionCookie, orgId: orgId)
            apply(response: response)
            sessionExpired = false
            errorMessage = nil
        } catch ClaudeAPIError.sessionExpired {
            sessionExpired = true
            errorMessage = "Session expired — please re-sign in"
        } catch ClaudeAPIError.parseError(let msg) {
            errorMessage = "Parse error"
            log.error("parse: \(msg, privacy: .public)")
        } catch ClaudeAPIError.httpError(let code) {
            errorMessage = "HTTP \(code)"
        } catch ClaudeAPIError.network(let msg) {
            errorMessage = "Network error"
            log.error("network: \(msg, privacy: .public)")
        } catch {
            errorMessage = "Unexpected error"
            log.error("unexpected: \(String(describing: error), privacy: .public)")
        }
    }

    private func apply(response: TokenTraceResponse) {
        store.insert(samples: response.samples)
        var merged = latestSample
        for sample in response.samples {
            merged[sample.bucket] = sample
        }
        latestSample = merged
        hasWeeklySonnet = response.hasWeeklySonnet
        hasFetchedData = true
        evaluateThresholdCrossings()
    }

    private func evaluateThresholdCrossings() {
        guard let fiveHour = latestSample[.fiveHour] else { return }

        // A new 5-hour window: re-arm all thresholds.
        if let last = lastFiveHourResetsAt, fiveHour.resetsAt > last {
            notifiedThresholdsThisWindow.removeAll()
        }
        lastFiveHourResetsAt = fiveHour.resetsAt

        let pct = Int(fiveHour.util.rounded(.down))
        for threshold in Self.notificationThresholds {
            if pct >= threshold && !notifiedThresholdsThisWindow.contains(threshold) {
                notifiedThresholdsThisWindow.insert(threshold)
                onThresholdCrossed?(threshold)
            }
        }
    }
}
