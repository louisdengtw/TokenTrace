import Foundation

/// One ingested assistant message from `~/.claude/projects/<...>/<session>.jsonl`.
/// Matches the `cc_message` table 1:1.
///
/// `uuid` is the JSONL line's per-message UUID; `INSERT OR IGNORE` against it
/// dedups same-message mirrors that appear in multiple files (e.g. subagent
/// transcripts that also surface in a parent session JSONL).
struct CCMessage: Equatable, Sendable {
    let uuid: String
    let ts: Date
    let cwd: String
    let model: String
    let inputTokens: Int
    let outputTokens: Int
    let cacheCreationTokens: Int
    let cacheReadTokens: Int
    let sessionId: String
    let requestId: String?
    let isSidechain: Bool
    let filePath: String
}
