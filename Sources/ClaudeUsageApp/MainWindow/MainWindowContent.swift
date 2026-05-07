import SwiftUI

struct MainWindowContent: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var selection: MainTabSelection
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 200, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark
                            ? Color(red: 0.118, green: 0.118, blue: 0.125)   // #1e1e20
                            : Color(red: 0.965, green: 0.965, blue: 0.969))   // #f6f6f7
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, minHeight: 540)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            Divider().opacity(0.5)
            navList
                .padding(.vertical, 6)
            Spacer(minLength: 0)
            Divider().opacity(0.5)
            sidebarFooter
        }
        .background(scheme == .dark
                    ? Color(red: 0.118, green: 0.118, blue: 0.125).opacity(0.6)
                    : Color(red: 0.926, green: 0.926, blue: 0.933).opacity(0.6))
    }

    private var brandHeader: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 5)
                    .fill(LinearGradient(
                        colors: [
                            Color(red: 0.851, green: 0.467, blue: 0.341),  // #D97757
                            Color(red: 0.788, green: 0.373, blue: 0.247)   // #C95F3F
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing))
                    .shadow(color: .black.opacity(0.15), radius: 1, y: 1)
                Text("C")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white)
            }
            .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 0) {
                Text("ClaudeUsage")
                    .font(.system(size: 13, weight: .semibold))
                    .tracking(-0.08)
                Text(usageManager.hasWeeklySonnet ? "v1.0 · Pro" : "v1.0")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    private var navList: some View {
        VStack(alignment: .leading, spacing: 1) {
            navRow(.dashboard,      label: "Dashboard", systemImage: "chart.line.uptrend.xyaxis")
            navRow(.menuBarPreview, label: "Menu Bar",  systemImage: "menubar.rectangle")
            navRow(.settings,       label: "Settings",  systemImage: "gearshape")
        }
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private func navRow(_ tab: MainTab, label: String, systemImage: String) -> some View {
        let selected = selection.selected == tab
        Button {
            selection.selected = tab
        } label: {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: selected ? .semibold : .regular))
                    .frame(width: 14, height: 14)
                    .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.85))
                Text(label)
                    .font(.system(size: 13, weight: selected ? .medium : .regular))
                    .tracking(-0.06)
                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected
                          ? Color.accentColor.opacity(scheme == .dark ? 0.30 : 0.14)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sidebarFooter: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(syncDotColor)
                .frame(width: 6, height: 6)
            Text(syncText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var syncDotColor: Color {
        if usageManager.sessionExpired { return .orange }
        if usageManager.errorMessage != nil { return .red }
        if usageManager.hasFetchedData {
            return Color(red: 0.204, green: 0.780, blue: 0.349)  // #34C759
        }
        return .secondary
    }

    private var syncText: String {
        if let sample = usageManager.latestSample[.fiveHour] {
            let seconds = max(0, Int(Date().timeIntervalSince(sample.ts)))
            if seconds < 60 { return "Synced \(seconds)s ago" }
            let minutes = seconds / 60
            if minutes < 60 { return "Synced \(minutes)m ago" }
            let hours = minutes / 60
            if hours < 24 { return "Synced \(hours)h ago" }
            return "Synced \(hours / 24)d ago"
        }
        if usageManager.isLoading { return "Syncing…" }
        return "Not synced"
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection.selected {
        case .dashboard:
            DashboardView(usageManager: usageManager)
        case .menuBarPreview:
            MenuBarPreviewView(usageManager: usageManager)
        case .settings:
            SettingsView(usageManager: usageManager)
        }
    }
}
