import SwiftUI

struct MainWindowContent: View {
    @ObservedObject var usageManager: UsageManager
    @ObservedObject var selection: MainTabSelection

    var body: some View {
        TabView(selection: $selection.selected) {
            MenuBarPreviewView(usageManager: usageManager)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }
                .tag(MainTab.menuBarPreview)

            DashboardView(usageManager: usageManager)
                .tabItem { Label("Dashboard", systemImage: "chart.line.uptrend.xyaxis") }
                .tag(MainTab.dashboard)

            SettingsView(usageManager: usageManager)
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(MainTab.settings)
        }
        .frame(minWidth: 720, minHeight: 480)
    }
}
