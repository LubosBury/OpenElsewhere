import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var routingEngine: RoutingEngine
    @State private var browsers: [AppInfo] = []
    @State private var allApps: [AppInfo] = []
    @State private var isHandlingLinks = false

    // Observes the permission-denied flag set by BrowserLauncher when macOS
    // returns `errAEEventNotPermitted` from an AppleScript event. Updates
    // reactively so the banner appears / disappears without a reopen.
    @AppStorage(BrowserLauncher.automationDeniedDefaultsKey) private var automationPermissionDenied = false

    // Cache: bundleID -> profiles, computed on demand.
    @State private var profileCache: [String: [BrowserProfile]] = [:]

    // Accent: light blue in light mode, deeper blue in dark mode.
    @Environment(\.colorScheme) private var colorScheme
    private var accent: Color {
        colorScheme == .dark
            ? Color(red: 0.45, green: 0.68, blue: 1.0)
            : Color(red: 0.2, green: 0.45, blue: 0.95)
    }

    var body: some View {
        ZStack {
            backgroundGradient

            ScrollView {
                VStack(spacing: 20) {
                    headerCard
                    defaultBrowserCard
                    if !isHandlingLinks { statusBanner }
                    if automationPermissionDenied { automationPermissionBanner }
                    rulesCard
                }
                .padding(24)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
        .tint(accent)
        .frame(minWidth: 620, minHeight: 540)
        .onAppear(perform: loadData)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: colorScheme == .dark
                ? [Color(red: 0.05, green: 0.08, blue: 0.18),
                   Color(red: 0.08, green: 0.12, blue: 0.28)]
                : [Color(red: 0.88, green: 0.93, blue: 1.0),
                   Color(red: 0.95, green: 0.97, blue: 1.0)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }

    // MARK: - Header card

    private var headerCard: some View {
        HStack(spacing: 16) {
            CompassLogo(size: 48, tint: accent)
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(accent.opacity(0.25), lineWidth: 0.5)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenElsewhere")
                    .font(.system(size: 22, weight: .semibold, design: .rounded))
                Text("Send links from any app to the right browser")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: $routingEngine.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.large)
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Default browser card

    private var defaultBrowserCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Default Browser", systemImage: "arrow.triangle.branch")
                    .font(.headline)
                Spacer()
                Text("Fallback when nothing matches")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                browserPicker(selection: $routingEngine.defaultBrowserBundleID)
                    .frame(maxWidth: .infinity)

                if !profiles(for: routingEngine.defaultBrowserBundleID).isEmpty {
                    profilePicker(
                        browserBundleID: routingEngine.defaultBrowserBundleID,
                        selection: $routingEngine.defaultProfileDirectoryName
                    )
                    .frame(width: 170)
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    // MARK: - Status banner (not handling links)

    private var statusBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "bolt.horizontal.circle.fill")
                .font(.title2)
                .foregroundStyle(accent)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenElsewhere isn't routing your links yet")
                    .font(.subheadline.weight(.semibold))
                Text("Set it as your default link handler so other apps send URLs through it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Make it Default") {
                setAsDefaultBrowser()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.regular)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(accent.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(accent.opacity(0.35), lineWidth: 0.5)
        )
    }

    // MARK: - Automation-permission banner

    /// Shown when `BrowserLauncher` recorded an `errAEEventNotPermitted`
    /// (-1743) from AppleScript. Without this banner, denying the one-time
    /// automation prompt results in links silently falling back to
    /// `/usr/bin/open` (which re-opens the "Little Arc" popup the AppleScript
    /// path was designed to avoid) with no user-facing indication of why.
    private var automationPermissionBanner: some View {
        HStack(spacing: 12) {
            Image(systemName: "lock.shield.fill")
                .font(.title2)
                .foregroundStyle(.orange)
                .symbolRenderingMode(.hierarchical)

            VStack(alignment: .leading, spacing: 2) {
                Text("Automation permission needed")
                    .font(.subheadline.weight(.semibold))
                Text("Allow OpenElsewhere to control Arc/Dia so links open as tabs in your existing window instead of popups.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Open Privacy Settings") {
                openAutomationSettings()
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
            .controlSize(.regular)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.orange.opacity(colorScheme == .dark ? 0.18 : 0.12))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 0.5)
        )
    }

    private func openAutomationSettings() {
        // Deep-link into System Settings → Privacy & Security → Automation.
        // If the URL scheme fails (e.g. future macOS changes the anchor),
        // fall back to the generic Privacy pane.
        let automationURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
        let fallbackURL = URL(string: "x-apple.systempreferences:com.apple.preference.security")
        if let url = automationURL ?? fallbackURL {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Rules card

    private var rulesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Routing Rules", systemImage: "point.3.filled.connected.trianglepath.dotted")
                    .font(.headline)
                Spacer()
                Button {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) {
                        addEmptyRule()
                    }
                } label: {
                    Label("Add Rule", systemImage: "plus.circle.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(accent)
            }

            if routingEngine.rules.isEmpty {
                emptyState
            } else {
                VStack(spacing: 10) {
                    ForEach($routingEngine.rules) { $rule in
                        RuleCard(
                            rule: $rule,
                            allApps: allApps,
                            browsers: browsers,
                            profiles: profiles(for: rule.targetBrowserBundleID),
                            accent: accent,
                            onDelete: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    routingEngine.removeRule(id: rule.id)
                                }
                            }
                        )
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                    }
                }
            }
        }
        .padding(20)
        .glassCard()
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(accent.opacity(0.6))
                .padding(.top, 8)
            Text("No rules yet")
                .font(.subheadline.weight(.medium))
            Text("Add a rule to route links from a specific app")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    // MARK: - Pickers

    private func browserPicker(selection: Binding<String>) -> some View {
        Picker("", selection: selection) {
            ForEach(browsers) { browser in
                HStack {
                    if let icon = browser.icon {
                        Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                    }
                    Text(browser.name)
                }
                .tag(browser.bundleID)
            }
        }
        .labelsHidden()
    }

    private func profilePicker(browserBundleID: String, selection: Binding<String?>) -> some View {
        let list = profiles(for: browserBundleID)
        return Picker("", selection: selection) {
            Text("Default Profile").tag(String?.none)
            Divider()
            ForEach(list) { profile in
                Text(profile.displayName).tag(String?.some(profile.directoryName))
            }
        }
        .labelsHidden()
    }

    // MARK: - Data

    private func profiles(for bundleID: String) -> [BrowserProfile] {
        if let cached = profileCache[bundleID] { return cached }
        let discovered = ProfileDiscovery.profiles(forBrowser: bundleID)
        profileCache[bundleID] = discovered
        return discovered
    }

    private func loadData() {
        browsers = BrowserDiscovery.shared.installedBrowsers()
        allApps = BrowserDiscovery.shared.installedApps()
        checkIfDefault()
        // Warm profile cache for default browser.
        _ = profiles(for: routingEngine.defaultBrowserBundleID)
    }

    private func checkIfDefault() {
        guard let httpsURL = URL(string: "https://example.com"),
              let defaultBrowserURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL),
              let defaultBundle = Bundle(url: defaultBrowserURL),
              let defaultBundleID = defaultBundle.bundleIdentifier else {
            isHandlingLinks = false
            return
        }
        isHandlingLinks = defaultBundleID.lowercased() == (Bundle.main.bundleIdentifier ?? "").lowercased()
    }

    private func setAsDefaultBrowser() {
        // Use the modern NSWorkspace API (macOS 14+). LaunchServices'
        // LSSetDefaultHandlerForURLScheme is deprecated since macOS 12 and
        // may silently no-op on future OS versions.
        let appURL = Bundle.main.bundleURL

        let group = DispatchGroup()
        for scheme in ["http", "https"] {
            group.enter()
            NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                    toOpenURLsWithScheme: scheme) { error in
                if let error {
                    print("OpenElsewhere: setDefaultApplication(\(scheme)) failed: \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) {
            checkIfDefault()
        }
    }

    private func addEmptyRule() {
        let sourceApp = allApps.first(where: { app in
            !routingEngine.rules.contains(where: { $0.sourceAppBundleID == app.bundleID })
        })?.bundleID ?? allApps.first?.bundleID ?? ""
        let targetBrowser = browsers.first?.bundleID ?? "com.apple.Safari"
        routingEngine.addRule(
            sourceAppBundleID: sourceApp,
            targetBrowserBundleID: targetBrowser,
            profileDirectoryName: nil
        )
    }
}

// MARK: - Rule Card

struct RuleCard: View {
    @Binding var rule: RoutingRule
    let allApps: [AppInfo]
    let browsers: [AppInfo]
    let profiles: [BrowserProfile]
    let accent: Color
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            // Source app
            Picker("", selection: $rule.sourceAppBundleID) {
                ForEach(allApps) { app in
                    HStack {
                        if let icon = app.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(app.name)
                    }
                    .tag(app.bundleID)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Image(systemName: "arrow.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(accent.opacity(0.7))

            // Target browser
            Picker("", selection: $rule.targetBrowserBundleID) {
                ForEach(browsers) { browser in
                    HStack {
                        if let icon = browser.icon {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(browser.name)
                    }
                    .tag(browser.bundleID)
                }
            }
            .labelsHidden()
            .frame(maxWidth: .infinity)

            // Profile (if the browser has any)
            if !profiles.isEmpty {
                Picker("", selection: $rule.profileDirectoryName) {
                    Text("Default Profile").tag(String?.none)
                    Divider()
                    ForEach(profiles) { profile in
                        Text(profile.displayName).tag(String?.some(profile.directoryName))
                    }
                }
                .labelsHidden()
                .frame(width: 150)
            }

            Button(role: .destructive) {
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 0.5)
        )
    }
}

// MARK: - Glass card modifier

private struct GlassCardModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.regularMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(
                        colorScheme == .dark ? .white.opacity(0.1) : .black.opacity(0.05),
                        lineWidth: 0.5
                    )
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.3 : 0.06),
                    radius: 20, x: 0, y: 8)
    }
}

private extension View {
    func glassCard() -> some View { modifier(GlassCardModifier()) }
}
