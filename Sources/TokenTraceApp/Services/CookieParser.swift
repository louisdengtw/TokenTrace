import Foundation

enum CookieParserError: Error, LocalizedError, Equatable {
    case empty
    case missingSessionKey
    case curlMissingCookieHeader
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .empty:
            return "Paste a cookie header or curl command."
        case .missingSessionKey:
            return "No sessionKey found. Paste a Cookie header from claude.ai (it must contain sessionKey=…)."
        case .curlMissingCookieHeader:
            return "The curl command has no Cookie header. Pick a request that includes one."
        case .malformed(let detail):
            return "Could not parse: \(detail)"
        }
    }
}

/// Accepts three input shapes and resolves to a canonical cookie header string:
///   1. Raw cookie header (`sessionKey=…; lastActiveOrg=…`)
///   2. `Cookie:`-prefixed string (case-insensitive prefix is stripped)
///   3. Full `curl` command from a browser DevTools "Copy as cURL" action;
///      the value of `-H 'cookie: …'` (or `--header …`) is extracted.
///
/// Header-name matching for the cURL extraction is case-insensitive.
/// All branches converge on a `sessionKey=` validation gate.
enum CookieParser {
    static func parse(_ raw: String) -> Result<String, CookieParserError> {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .failure(.empty) }

        let extracted: String
        if isCurlCommand(trimmed) {
            switch extractCookieFromCurl(trimmed) {
            case .success(let value): extracted = value
            case .failure(let error): return .failure(error)
            }
        } else if let stripped = stripCookiePrefix(trimmed) {
            extracted = stripped
        } else {
            extracted = trimmed
        }

        guard extracted.contains("sessionKey=") else {
            return .failure(.missingSessionKey)
        }
        return .success(extracted)
    }

    // MARK: - Branch detection

    private static func isCurlCommand(_ s: String) -> Bool {
        let lower = s.lowercased()
        return lower == "curl" || lower.hasPrefix("curl ") || lower.hasPrefix("curl\t") || lower.hasPrefix("curl\n")
    }

    private static func stripCookiePrefix(_ s: String) -> String? {
        let prefix = "cookie:"
        guard s.lowercased().hasPrefix(prefix) else { return nil }
        return String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - cURL extraction

    private static func extractCookieFromCurl(_ s: String) -> Result<String, CookieParserError> {
        // Collapse line continuations: backslash followed by newline (with optional CR)
        // becomes a single space, so a multi-line curl matches the single-line regex.
        let collapsed = s
            .replacingOccurrences(of: "\\\r\n", with: " ")
            .replacingOccurrences(of: "\\\n", with: " ")

        // -H or --header, then a quote, then "cookie:" (case-insensitive header name),
        // then the captured value, terminated by the matching quote (backreference).
        let pattern = #"(?:-H|--header)\s+(['"])\s*(?i:cookie)\s*:\s*([^'"]+?)\s*\1"#
        do {
            let regex = try NSRegularExpression(pattern: pattern)
            let range = NSRange(collapsed.startIndex..., in: collapsed)
            guard let match = regex.firstMatch(in: collapsed, range: range),
                  match.numberOfRanges >= 3,
                  let valueRange = Range(match.range(at: 2), in: collapsed)
            else {
                return .failure(.curlMissingCookieHeader)
            }
            let value = String(collapsed[valueRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { return .failure(.curlMissingCookieHeader) }
            return .success(value)
        } catch {
            return .failure(.malformed("regex compilation failed"))
        }
    }
}
