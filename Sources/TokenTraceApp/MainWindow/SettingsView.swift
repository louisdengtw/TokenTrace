import OSLog
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var usageManager: UsageManager

    @State private var pastedCookie = ""
    @State private var parserErrorMessage: String?
    @State private var notificationsOn = AppSettings.notificationsEnabled
    @State private var openAtLoginOn = AppSettings.openAtLoginEnabled
    @State private var openAtLoginErrorMessage: String?

    @Environment(\.openURL) private var openURL

    private let log = Logger(subsystem: "dev.louisdeng.tokentrace", category: "SettingsView")

    private static let extensionDocsURL = URL(string: "https://github.com/louisdengtw/TokenTrace/releases/latest")!

    var body: some View {
        Form {
            cookieSection
            notificationsSection
            loginSection
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { applyPendingImportIfAny() }
        .onChange(of: usageManager.pendingImportCookie) { _ in applyPendingImportIfAny() }
        .onChange(of: usageManager.pendingImportError) { _ in applyPendingImportIfAny() }
    }

    // MARK: - Cookie

    @ViewBuilder
    private var cookieSection: some View {
        Section("Cookie") {
            if !usageManager.sessionCookie.isEmpty {
                HStack {
                    Text(redactedPreview(of: usageManager.sessionCookie))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Sign out", role: .destructive) {
                        usageManager.clearCookie()
                        pastedCookie = ""
                        parserErrorMessage = nil
                    }
                }
            } else {
                Text("No cookie stored.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Paste cookie header or curl command:")
                    .font(.caption)
                TextEditor(text: $pastedCookie)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 60, maxHeight: 90)
                    .scrollContentBackground(.hidden)
                    .background(.quinary, in: RoundedRectangle(cornerRadius: 4))
                HStack {
                    Button {
                        // /settings/usage triggers the same /api/organizations/{id}/usage
                        // request TokenTrace polls, so DevTools → Network → "Copy as cURL"
                        // lands on the right request straight away.
                        openURL(URL(string: "https://claude.ai/settings/usage")!)
                    } label: {
                        Label("Open claude.ai", systemImage: "safari")
                    }
                    Spacer()
                    Button("Save") {
                        save()
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(pastedCookie.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            if let parserErrorMessage {
                Label(parserErrorMessage, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            } else if usageManager.sessionExpired {
                Label("Session expired — paste a fresh cookie above.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else if let error = usageManager.errorMessage {
                Label(error, systemImage: "exclamationmark.circle")
                    .foregroundStyle(.red)
                    .font(.caption)
            }

            HStack(spacing: 4) {
                Image(systemName: "puzzlepiece.extension")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                Text("Skip the dance —")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("install the Firefox/Zen add-on") {
                    openURL(Self.extensionDocsURL)
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
    }

    private func save() {
        switch usageManager.saveCookie(pastedCookie) {
        case .success:
            pastedCookie = ""
            parserErrorMessage = nil
        case .failure(let error):
            parserErrorMessage = error.errorDescription ?? "Could not save cookie."
        }
    }

    private func applyPendingImportIfAny() {
        if let pending = usageManager.pendingImportCookie, !pending.isEmpty {
            pastedCookie = pending
            parserErrorMessage = nil
            usageManager.consumePendingImport()
        } else if let error = usageManager.pendingImportError {
            parserErrorMessage = "Import failed: \(error)"
            usageManager.consumePendingImport()
        }
    }

    // MARK: - Notifications

    @ViewBuilder
    private var notificationsSection: some View {
        Section("Notifications") {
            Toggle("Enable notifications", isOn: $notificationsOn)
                .onChange(of: notificationsOn) { newValue in
                    AppSettings.notificationsEnabled = newValue
                    if newValue {
                        Task { await NotificationCoordinator.requestAuthorization() }
                    }
                }
            Text("Fires once each at 25%, 50%, 75%, and 90% of the 5-hour session.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Open at login

    @ViewBuilder
    private var loginSection: some View {
        Section("Login") {
            Toggle("Open at login", isOn: $openAtLoginOn)
                .onChange(of: openAtLoginOn) { newValue in
                    applyOpenAtLogin(newValue)
                }
            if let openAtLoginErrorMessage {
                Text(openAtLoginErrorMessage)
                    .foregroundStyle(.red)
                    .font(.caption)
            }
        }
    }

    private func applyOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            AppSettings.openAtLoginEnabled = enabled
            openAtLoginErrorMessage = nil
        } catch {
            log.error("SMAppService toggle failed: \(String(describing: error), privacy: .public)")
            openAtLoginErrorMessage = "Could not update login item: \(error.localizedDescription)"
            // Revert UI to actual state.
            openAtLoginOn = !enabled
        }
    }

    // MARK: - Helpers

    private func redactedPreview(of cookie: String) -> String {
        let prefix = cookie.prefix(20)
        return "\(prefix)●●●●●● (\(cookie.count) chars)"
    }
}
