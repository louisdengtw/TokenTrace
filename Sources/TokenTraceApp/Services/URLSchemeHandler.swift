import Foundation

/// Pure routing for inbound `tokentrace://` URLs. No side effects — the
/// AppDelegate dispatches the outcome (activating the app, populating the
/// pending-import field). Keeping this side-effect-free is what lets us
/// unit-test the URL contract.
enum URLSchemeOutcome: Equatable {
    /// `tokentrace://import?cookie=<value>` with a non-empty decoded value.
    /// Caller must NOT save without explicit user confirmation.
    case importCookie(String)
    /// `tokentrace://import` was reached but the cookie parameter was missing,
    /// empty, or undecodable. Caller surfaces the reason in Settings.
    case importMalformed(reason: String)
    /// Any other URL — different scheme, different host, different path.
    /// Caller leaves all state alone.
    case ignored
}

enum URLSchemeHandler {
    static let scheme = "tokentrace"

    static func handle(_ url: URL) -> URLSchemeOutcome {
        guard url.scheme?.lowercased() == scheme else { return .ignored }
        guard url.host?.lowercased() == "import" else { return .ignored }

        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .importMalformed(reason: "unparseable URL")
        }
        guard let items = components.queryItems else {
            return .importMalformed(reason: "missing cookie parameter")
        }
        guard let cookieItem = items.first(where: { $0.name == "cookie" }) else {
            return .importMalformed(reason: "missing cookie parameter")
        }
        // URLComponents.queryItems already URL-decodes the value. A nil here
        // means the percent-encoding was malformed; an empty string means the
        // user/extension sent ?cookie= with no value.
        guard let value = cookieItem.value else {
            return .importMalformed(reason: "undecodable cookie value")
        }
        guard !value.isEmpty else {
            return .importMalformed(reason: "empty cookie value")
        }
        return .importCookie(value)
    }
}
