// Portions of this file are derived from ClaudeUsageBar (MIT licensed).
// Source: https://github.com/Artzainnn/ClaudeUsageBar
// Copyright (c) 2026 ClaudeUsageBar — see LICENSE-CLAUDEUSAGEBAR for full terms.

import Foundation
import OSLog

enum ClaudeAPIError: Error, Equatable {
    case sessionExpired
    case parseError(String)
    case httpError(Int)
    case network(String)
}

struct TokenTraceResponse: Equatable {
    let samples: [UsageSample]
    /// Model display names of `weekly_scoped` limits in this response,
    /// in order of appearance, deduplicated.
    let scopedModels: [String]
}

final class ClaudeAPI {
    private let session: URLSession
    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "ClaudeAPI")

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchOrgId(cookie: String) async throws -> String {
        if let fromCookie = Self.extractOrgIdFromCookie(cookie) {
            log.debug("Resolved org_id from cookie")
            return fromCookie
        }

        guard let url = URL(string: "https://claude.ai/api/bootstrap") else {
            throw ClaudeAPIError.parseError("invalid bootstrap URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        // Bootstrap accepts the sessionKey-only cookie form.
        req.setValue("sessionKey=\(cookie)", forHTTPHeaderField: "Cookie")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ClaudeAPIError.network(error.localizedDescription)
        }

        try Self.detectAuthFailure(data: data, response: response)

        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            log.error("bootstrap response not JSON; prefix=\(Self.prefix(data), privacy: .public)")
            throw ClaudeAPIError.parseError("bootstrap response not JSON")
        }

        // `account: null` (or missing) is the canonical unauthenticated signal.
        if dict["account"] is NSNull {
            throw ClaudeAPIError.sessionExpired
        }
        guard let account = dict["account"] as? [String: Any],
              let orgId = account["lastActiveOrgId"] as? String else {
            log.error("bootstrap missing account.lastActiveOrgId; keys=\(Array(dict.keys), privacy: .public)")
            throw ClaudeAPIError.sessionExpired
        }
        return orgId
    }

    func fetchUsage(cookie: String, orgId: String, now: Date = Date()) async throws -> TokenTraceResponse {
        guard let url = URL(string: "https://claude.ai/api/organizations/\(orgId)/usage") else {
            throw ClaudeAPIError.parseError("invalid usage URL")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cookie, forHTTPHeaderField: "Cookie")
        req.setValue("*/*", forHTTPHeaderField: "Accept")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Origin")
        req.setValue("https://claude.ai", forHTTPHeaderField: "Referer")
        req.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ClaudeAPIError.network(error.localizedDescription)
        }

        try Self.detectAuthFailure(data: data, response: response)

        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClaudeAPIError.httpError(http.statusCode)
        }

        return try Self.parseUsage(data: data, at: now)
    }

    static func parseUsage(data: Data, at ts: Date) throws -> TokenTraceResponse {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.parseError("not JSON; prefix=\(Self.prefix(data))")
        }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoNoFractional = ISO8601DateFormatter()
        isoNoFractional.formatOptions = [.withInternetDateTime]

        func parseDate(_ s: String) -> Date? {
            iso.date(from: s) ?? isoNoFractional.date(from: s)
        }

        // Top-level fixed-window objects (still live; float-precision utilization).
        func topLevelSample(_ key: String, bucket: Bucket) -> UsageSample? {
            guard let inner = dict[key] as? [String: Any],
                  let util = (inner["utilization"] as? NSNumber)?.doubleValue,
                  let resetStr = inner["resets_at"] as? String,
                  let resetsAt = parseDate(resetStr) else { return nil }
            return UsageSample(ts: ts, bucket: bucket, util: util, resetsAt: resetsAt)
        }

        let limits = dict["limits"] as? [[String: Any]] ?? []

        // limits[] entry by kind; integer `percent` fallback for fixed windows.
        func limitSample(kind: String, bucket: Bucket) -> UsageSample? {
            guard let entry = limits.first(where: { $0["kind"] as? String == kind }),
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                  let resetStr = entry["resets_at"] as? String,
                  let resetsAt = parseDate(resetStr) else { return nil }
            return UsageSample(ts: ts, bucket: bucket, util: percent, resetsAt: resetsAt)
        }

        var samples: [UsageSample] = []
        var scopedModels: [String] = []

        if let s = topLevelSample("five_hour", bucket: .fiveHour)
            ?? limitSample(kind: "session", bucket: .fiveHour) {
            samples.append(s)
        }
        if let s = topLevelSample("seven_day", bucket: .sevenDay)
            ?? limitSample(kind: "weekly_all", bucket: .sevenDay) {
            samples.append(s)
        }

        // Model-scoped weekly limits. Entries without a model display name
        // (surface scopes etc.) are skipped.
        for entry in limits where entry["kind"] as? String == "weekly_scoped" {
            guard let scope = entry["scope"] as? [String: Any],
                  let model = scope["model"] as? [String: Any],
                  let name = model["display_name"] as? String, !name.isEmpty else {
                Logger(subsystem: "dev.louisdeng.tokentrace", category: "ClaudeAPI")
                    .notice("skipping weekly_scoped limit without model display_name")
                continue
            }
            guard !scopedModels.contains(name),
                  let percent = (entry["percent"] as? NSNumber)?.doubleValue,
                  let resetStr = entry["resets_at"] as? String,
                  let resetsAt = parseDate(resetStr) else { continue }
            samples.append(UsageSample(ts: ts, bucket: .weeklyScoped(model: name), util: percent, resetsAt: resetsAt))
            scopedModels.append(name)
        }

        // Legacy shape: non-null top-level seven_day_sonnet (old fixtures /
        // server rollback). limits[] wins if it already produced Sonnet.
        if !scopedModels.contains("Sonnet"),
           let s = topLevelSample(Bucket.legacySonnetKey, bucket: .weeklyScoped(model: "Sonnet")) {
            samples.append(s)
            scopedModels.append("Sonnet")
        }

        let hasFiveHourOrSevenDay = samples.contains { $0.bucket == .fiveHour || $0.bucket == .sevenDay }
        guard hasFiveHourOrSevenDay else {
            throw ClaudeAPIError.parseError("response missing both five_hour and seven_day")
        }

        return TokenTraceResponse(samples: samples, scopedModels: scopedModels)
    }

    static func extractOrgIdFromCookie(_ cookie: String) -> String? {
        for part in cookie.split(separator: ";") {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("lastActiveOrg=") {
                let value = String(trimmed.dropFirst("lastActiveOrg=".count))
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func detectAuthFailure(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        let finalPath = response.url?.path.lowercased() ?? ""
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()

        let statusFail = http.statusCode == 401 || http.statusCode == 403
        let redirectFail = finalPath.contains("/login")
        // Treat 200 + non-JSON as auth failure (login HTML page served on cookie expiry).
        let contentTypeFail = http.statusCode == 200
            && !contentType.isEmpty
            && !contentType.contains("application/json")

        if statusFail || redirectFail || contentTypeFail {
            throw ClaudeAPIError.sessionExpired
        }
    }

    private static func prefix(_ data: Data, _ maxLen: Int = 300) -> String {
        let bytes = data.prefix(maxLen)
        return String(data: bytes, encoding: .utf8) ?? "<binary>"
    }
}
