import SwiftUI

struct SettingsView: View {
    @Binding var isPresented: Bool
    // Supplied by ContentView's environment. Carries the credential state so this
    // screen never reads the keychain while drawing.
    @EnvironmentObject var viewModel: UsageViewModel
    @AppStorage("showSessionInMenuBar") private var showSession = false
    @AppStorage("showWeeklyInMenuBar") private var showWeekly = false
    @AppStorage("showFableInMenuBar") private var showFable = false
    @AppStorage(Prefs.showLocationInMenuBar) private var showLocation = false
    @AppStorage("appearancePreference") private var appearance: AppearancePreference = .system
    @AppStorage(Prefs.showSpendCard) private var showSpendCard = true
    @AppStorage(Prefs.showRTKCard) private var showRTKCard = true
    @AppStorage(Prefs.showTraceCard) private var showTrace = true

    var body: some View {
        VStack(spacing: 0) {
            settingsHeader

            Divider()
                .background(Theme.divider)

            // A plain VStack, not a ScrollView: inside MenuBarExtra(.window) a
            // ScrollView reports an indefinite fitting height, so the popover
            // keeps the taller main-view height while the scroll content
            // collapses and clips (issue #25). The settings content is short
            // enough to always fit, so let it size the window naturally.
            VStack(alignment: .leading, spacing: 16) {
                authStatusSection
                appearanceSection
                menuBarDisplaySection
                cardsSection
                connectionSection
                versionRow
            }
            .padding(12)
        }
        .frame(width: 280)
        .background(Theme.background)
    }

    private var settingsHeader: some View {
        HStack {
            Button(action: { isPresented = false }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12))
                    .foregroundColor(Theme.textPrimary)
            }
            .buttonStyle(.plain)

            Text("Settings")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Theme.textPrimary)

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var authStatusSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Authentication")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.hasCredentials ? Color.green : Color.red)
                    .frame(width: 8, height: 8)

                Text(viewModel.hasCredentials
                     ? "Authenticated via Claude Code"
                     : "Not authenticated")
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
            }

            if !viewModel.hasCredentials {
                Text("Run 'claude' in your terminal to log in. Credentials are detected automatically.")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.textSecondary)
                    .padding(8)
                    .background(Theme.inputBackground)
                    .cornerRadius(6)
            }
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Appearance")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            // Named for VoiceOver even though the heading above already says it
            // visually — labelsHidden() only suppresses the on-screen label, so
            // an empty string would leave the control unannounced.
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearancePreference.allCases) { option in
                    Text(option.label).tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)

            Text("Auto follows the system setting.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var menuBarDisplaySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Menu Bar Display")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Toggle("Show session usage", isOn: $showSession)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Toggle("Show weekly usage", isOn: $showWeekly)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Toggle("Show Fable usage", isOn: $showFable)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Toggle("Show location flag", isOn: $showLocation)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Text("The flag needs the trace request, so it stays live even with the Trace card off.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var cardsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Cards")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Toggle("API-equivalent spend", isOn: $showSpendCard)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Toggle("RTK savings", isOn: $showRTKCard)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Text("Hiding a card also skips its work — no transcript scan, no database read.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var connectionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Connection")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Theme.textPrimary)

            Toggle("Show trace card", isOn: $showTrace)
                .font(.system(size: 11))
                .foregroundColor(Theme.textSecondary)
                .toggleStyle(.switch)
                .controlSize(.mini)

            Text("Country, edge datacentre and protocols, from Cloudflare at claude.ai. Off means the request isn't sent at all.")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .background(Theme.cardBackground)
        .cornerRadius(8)
    }

    private var versionRow: some View {
        HStack {
            Spacer()

            Text("v\(appVersion)")
                .font(.system(size: 10))
                .foregroundColor(Theme.textSecondary)
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
    }
}

#Preview {
    SettingsView(isPresented: .constant(true))
        .environmentObject(UsageViewModel())
}
