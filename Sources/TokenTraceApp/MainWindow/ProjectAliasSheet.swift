import AppKit
import SwiftUI

struct ProjectAliasSheet: View {
    let ccStore: CCUsageStore
    @Environment(\.dismiss) private var dismiss

    @State private var cwds: [String]
    @State private var aliasMap: [String: String]            // user-editable
    @State private var originalAliasMap: [String: String]   // for diff on commit
    @State private var hoveredCwd: String? = nil            // drives bottom indicator

    /// Loads observed cwds and current aliases synchronously at init time.
    /// `.onAppear { load() }` would also work for the live sheet, but doing
    /// it here means a static render (e.g. via NSHostingView for snapshot
    /// tests) sees the populated state instead of an empty body.
    ///
    /// The cwd list comes from `effectiveCwds(mergeWorktrees:)` so that
    /// when worktree fold is on (default), the sheet shows ONE row per
    /// parent project rather than parent + per-worktree duplicates.
    /// Aliases set here are stored against the *parent* path, which the
    /// aggregation query inherits into all worktrees automatically.
    ///
    /// `aliasMap` is pre-populated with the *effective* current label for
    /// each row — either the user's stored alias or the synthesised label.
    /// That way the TextField shows something editable instead of an empty
    /// field; users tweak the displayed text rather than type from scratch.
    /// `originalAliasMap` keeps the raw DB state so `commit()` can diff
    /// against the actual persisted aliases.
    init(ccStore: CCUsageStore) {
        self.ccStore = ccStore
        let options = CCUsageStore.QueryOptions(
            displayNameDepth: AppSettings.ccProjectNameDepth,
            mergeWorktrees:   AppSettings.ccMergeWorktrees,
            workspaceRoot:    AppSettings.ccProjectWorkspaceRootExpanded
        )
        let initialCwds = ccStore.effectiveCwds(options: options)
        let storedAliases = ccStore.aliases()
        var effective: [String: String] = [:]
        for cwd in initialCwds {
            effective[cwd] = storedAliases[cwd] ?? Self.synthesisedLabel(for: cwd)
        }
        _cwds = State(initialValue: initialCwds)
        _aliasMap = State(initialValue: effective)
        _originalAliasMap = State(initialValue: storedAliases)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            if cwds.isEmpty {
                emptyState
            } else {
                // ScrollView wraps the rows so a large project list stays
                // scrollable in the live sheet. (ImageRenderer doesn't
                // render ScrollView contents — that's why snapshot tests
                // disable it via the `.headerProminence` path; not needed
                // at runtime.)
                ScrollView(.vertical, showsIndicators: true) {
                    rowsContent
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            footer
        }
        .frame(width: 700, height: 520)
        .background(Color(NSColor.windowBackgroundColor))
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Manage project aliases")
                .font(.system(size: 13, weight: .semibold))
            Text("Rename a `cwd` to a friendly display label. Aliases persist across launches; two cwds with the same alias text merge into one row on the dashboard.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Text("No Claude Code projects observed yet")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Open the Claude Code tab and hit Refresh to scan ~/.claude/projects/.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var rowsContent: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(cwds.enumerated()), id: \.element) { (i, cwd) in
                row(for: cwd)
                if i < cwds.count - 1 {
                    Divider().opacity(0.4)
                }
            }
        }
    }

    private func row(for cwd: String) -> some View {
        let synth = Self.synthesisedLabel(for: cwd)
        let aliasBinding = Binding<String>(
            get: { aliasMap[cwd] ?? "" },
            set: { aliasMap[cwd] = $0 }
        )
        let current = (aliasMap[cwd] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        // "Set" = differs from the synthesised default. Drives the reset
        // button's enabled/dimmed state.
        let isOverridden = !current.isEmpty && current != synth

        return HStack(alignment: .center, spacing: 12) {
            // cwd column — monospaced, muted, HEAD-truncated so the unique
            // tail of the path is always visible (the `/Users/louisdeng/...`
            // prefix is the same across rows; the worktree branch / repo
            // name lives at the end). Full cwd surfaces in the sheet's
            // bottom indicator on hover — `.help()` system tooltips don't
            // fire reliably in SwiftUI sheets so we don't rely on them.
            Text(cwd)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.head)
                .frame(maxWidth: .infinity, alignment: .leading)

            // alias TextField — pre-populated with the synthesised label
            // (or the user's stored alias). Empty value means the user
            // explicitly cleared the field; the placeholder shows the
            // synthesised fallback in that state.
            TextField(synth, text: aliasBinding)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 11))
                .frame(width: 180)

            // Reset-to-synthesised affordance. Enabled only when the
            // current text differs from the synthesised default; clicking
            // restores the default value.
            Button {
                aliasMap[cwd] = synth
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Reset this alias to the default label (\(synth))")
            .opacity(isOverridden ? 1.0 : 0.25)
            .disabled(!isOverridden)
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredCwd = hovering ? cwd : nil
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Hover indicator — always-on bottom strip that shows the
            // currently-hovered row's full cwd. Avoids the SwiftUI sheet
            // `.help()` tooltip-reliability issue while still letting the
            // user see the truncated tail-of-path.
            hoverIndicator
            HStack {
                Text("\(cwds.count) project\(cwds.count == 1 ? "" : "s")")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Done") {
                    commit()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var hoverIndicator: some View {
        if let cwd = hoveredCwd {
            // Wrap onto multiple lines if needed — the whole point of this
            // indicator is to surface paths that don't fit on one row.
            Text(cwd)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
                .textSelection(.enabled)
        } else {
            Text("Hover a row to see the full cwd path")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 6)
        }
    }

    // MARK: - Data flow

    /// Persist the diff between current text and the originally-stored
    /// alias. An "effective" alias is non-empty AND differs from the
    /// synthesised default; otherwise the row should have no DB entry.
    /// Calls `setAlias` / `removeAlias` only where the effective state
    /// changed.
    private func commit() {
        for cwd in cwds {
            let raw = (aliasMap[cwd] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let synth = Self.synthesisedLabel(for: cwd)
            let effectiveNew: String? = (raw.isEmpty || raw == synth) ? nil : raw
            let effectiveOld: String? = originalAliasMap[cwd]   // nil if no row in project_alias

            if effectiveNew == effectiveOld { continue }
            if let newAlias = effectiveNew {
                ccStore.setAlias(cwd: cwd, displayName: newAlias)
            } else {
                ccStore.removeAlias(cwd: cwd)
            }
        }
    }

    /// Mirror of CCUsageStore's private synthesised-label rule so the
    /// pre-populated TextField text matches what the chart will use when
    /// the alias field is left at its default. Honours
    /// `AppSettings.ccProjectNameDepth`. Static so the init helper can
    /// call it without bootstrapping `self`.
    private static func synthesisedLabel(for cwd: String) -> String {
        let depth = max(1, AppSettings.ccProjectNameDepth)
        let trimmed = cwd.hasSuffix("/") ? String(cwd.dropLast()) : cwd
        let comps = trimmed.split(separator: "/", omittingEmptySubsequences: true)
        guard comps.count >= depth else { return cwd }
        return comps.suffix(depth).joined(separator: "/")
    }
}
