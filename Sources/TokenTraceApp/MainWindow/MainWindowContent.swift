import SwiftUI

struct MainWindowContent: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var selection: MainTabSelection
    @Environment(\.colorScheme) private var scheme
    @State private var sidebarCollapsed: Bool = false
    @State private var isExporting: Bool = false

    private var sidebarWidth: CGFloat { sidebarCollapsed ? 56 : 200 }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: sidebarWidth)

            Rectangle()
                .fill(scheme == .dark
                      ? Color.white.opacity(0.06)
                      : Color.black.opacity(0.10))
                .frame(width: 0.5)
                .ignoresSafeArea()

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(scheme == .dark
                            ? Color(red: 0.118, green: 0.118, blue: 0.125)
                            : Color(red: 0.965, green: 0.965, blue: 0.969))
        }
        .frame(minWidth: 760, minHeight: 540)
        .onReceive(NotificationCenter.default.publisher(for: .toggleSidebar)) { _ in
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarCollapsed.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .exportReportRequested)) { _ in
            // Reset & open. Per spec the sheet always opens to defaults — that
            // is enforced inside ExportSheetView, but we also toggle here in
            // case the user spammed the menu item to re-open it.
            isExporting = false
            isExporting = true
        }
        .sheet(isPresented: $isExporting) {
            ExportSheetView(usageManager: usageManager)
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            brandHeader
            Divider().opacity(0.5)
            navList.padding(.vertical, 6)
            Spacer(minLength: 0)
            Divider().opacity(0.5)
            sidebarFooter
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(scheme == .dark
                    ? Color(red: 0.118, green: 0.118, blue: 0.125).opacity(0.6)
                    : Color(red: 0.926, green: 0.926, blue: 0.933).opacity(0.6))
    }

    @ViewBuilder
    private var brandHeader: some View {
        if sidebarCollapsed {
            VStack(spacing: 8) {
                brandChip
                toggleButton
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.top, 14)
            .padding(.bottom, 10)
        } else {
            HStack(spacing: 8) {
                brandChip
                VStack(alignment: .leading, spacing: 0) {
                    Text("TokenTrace")
                        .font(.system(size: 13, weight: .semibold))
                        .tracking(-0.08)
                    Text(usageManager.hasWeeklySonnet ? "v1.0 · Pro+" : "v1.0")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                toggleButton
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)
        }
    }

    private var brandChip: some View {
        // The brand chip is the app's own icon (Resources/TokenTrace.icns)
        // rendered at 22pt. Stays in sync with whatever icon ships in the
        // bundle, so future icon updates don't need a code change here.
        Image(nsImage: NSImage(named: NSImage.applicationIconName) ?? NSImage())
            .resizable()
            .interpolation(.high)
            .frame(width: 22, height: 22)
    }

    private var toggleButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                sidebarCollapsed.toggle()
            }
        } label: {
            Image(systemName: sidebarCollapsed ? "sidebar.right" : "sidebar.left")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sidebarCollapsed ? "Show sidebar" : "Hide sidebar")
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
                if !sidebarCollapsed {
                    Text(label)
                        .font(.system(size: 13, weight: selected ? .medium : .regular))
                        .tracking(-0.06)
                    Spacer(minLength: 0)
                }
            }
            .padding(.horizontal, sidebarCollapsed ? 0 : 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(selected
                          ? Color.accentColor.opacity(scheme == .dark ? 0.30 : 0.14)
                          : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(sidebarCollapsed ? label : "")
    }

    private var sidebarFooter: some View {
        HStack(spacing: 7) {
            ZStack {
                Circle()
                    .fill(syncDotColor.opacity(0.22))
                    .frame(width: 12, height: 12)
                Circle()
                    .fill(syncDotColor)
                    .frame(width: 6, height: 6)
            }
            if !sidebarCollapsed {
                VStack(alignment: .leading, spacing: 1) {
                    Text(syncStatusLabel)
                        .font(.system(size: 10, weight: .medium))
                        .textCase(.uppercase)
                        .tracking(0.4)
                        .foregroundStyle(.tertiary)
                    Text(syncText)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: sidebarCollapsed ? .center : .leading)
        .padding(.horizontal, sidebarCollapsed ? 8 : 14)
        .padding(.vertical, 11)
        .help(sidebarCollapsed ? "\(syncStatusLabel) · \(syncText)" : "")
    }

    private var syncStatusLabel: String {
        if usageManager.sessionExpired { return "Session" }
        if usageManager.errorMessage != nil { return "Error" }
        if usageManager.isLoading { return "Syncing" }
        return "Synced"
    }

    private var syncDotColor: Color {
        if usageManager.sessionExpired { return .orange }
        if usageManager.errorMessage != nil { return .red }
        if usageManager.hasFetchedData {
            return Color(red: 0.204, green: 0.780, blue: 0.349)
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
