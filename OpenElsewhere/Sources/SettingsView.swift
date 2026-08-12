import AppKit
import SwiftUI

/// The Settings window: identity and the master switch in a fixed header,
/// three tabs below it, and — above whichever tab is showing — at most **one**
/// setup prompt.
///
/// The previous layout could stack a header card, three setup banners, a
/// picker card and the rules card in one scrolling column. Nothing about
/// routing changed here; the same state drives a smaller surface.
struct SettingsView: View {
    @EnvironmentObject var routingEngine: RoutingEngine
    @StateObject private var tipJar = TipJar()
    @ObservedObject private var route = SettingsRoute.shared

    @SceneStorage("settingsTab") private var selectedTab: SettingsTab = .rules

    @State private var browsers: [AppInfo] = []
    @State private var allApps: [AppInfo] = []
    @State private var destinations: [Destination] = []
    @State private var isHandlingLinks = false
    @State private var profileHelperInstalled = false
    @State private var showsHelperSheet = false
    @State private var launchAtLogin = false

    /// Set by `BrowserLauncher` when macOS returns `errAEEventNotPermitted`
    /// from an AppleScript event, so the prompt appears without a reopen.
    @AppStorage(BrowserLauncher.automationDeniedDefaultsKey) private var automationPermissionDenied = false

    @Environment(\.colorScheme) private var scheme
    private var t: OETheme { OETheme.resolve(scheme) }

    private var conditions: SetupConditions {
        SetupConditions(isHandlingLinks: isHandlingLinks,
                        automationPermissionDenied: automationPermissionDenied,
                        profileHelperInstalled: profileHelperInstalled,
                        hasRules: !routingEngine.rules.isEmpty)
    }

    private var setupQueue: [SetupTask] { SetupTask.settingsQueue(conditions) }

    private var fallbackLabel: String {
        DestinationList.label(browserBundleID: routingEngine.defaultBrowserBundleID,
                              profileDirectoryName: routingEngine.defaultProfileDirectoryName)
    }

    var body: some View {
        ZStack {
            OEBackground(theme: t)

            VStack(spacing: 0) {
                header
                    .padding(.horizontal, OE.Pad.window)
                    .padding(.top, 18)
                    .padding(.bottom, 16)

                tabBar
                    .padding(.horizontal, OE.Pad.window)
                    .padding(.bottom, 12)

                OEHairline(theme: t)

                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        if let task = setupQueue.first {
                            setupStrip(task)
                                .id(task.id)
                                .transition(.opacity.combined(with: .move(edge: .top)))
                        }

                        switch selectedTab {
                        case .general: generalTab
                        case .rules: rulesTab
                        case .about: aboutTab
                        }
                    }
                    .padding(OE.Pad.window)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(minHeight: OE.Size.contentMinHeight, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }
        }
        .tint(t.accent)
        .frame(minWidth: OE.Size.settingsMinWidth, minHeight: 500)
        .animation(OE.spring, value: setupQueue.first)
        .onAppear {
            loadData()
            consumePendingRoute()
        }
        .onChange(of: route.wantsNewRule) { _, _ in consumePendingRoute() }
        // The user leaves the app to change the default browser, grant
        // automation or install the helper, so returning to the window is
        // exactly when every condition should re-evaluate.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            // Hop to the next main-actor turn before touching @State:
            // `didBecomeActive` fires during launch, which can land inside a
            // SwiftUI view update.
            Task { @MainActor in
                checkIfDefault()
                profileHelperInstalled = ProfileRoutingHelper.isInstalled
                launchAtLogin = LaunchAtLogin.isEnabled
            }
        }
        .sheet(isPresented: $showsHelperSheet) {
            HelperScriptSheet(isInstalled: $profileHelperInstalled) {
                showsHelperSheet = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            Image(nsImage: OEAppIcon.image)
                .resizable()
                .frame(width: 30, height: 30)
                .oeGlow(t.accent.opacity(0.5), css: 20, scale: t.glowScale)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: OE.Radius.tile, style: .continuous)
                        .fill(.ultraThinMaterial)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: OE.Radius.tile, style: .continuous)
                        .strokeBorder(t.accentLine, lineWidth: OE.hairline)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text("OpenElsewhere")
                    .font(OEFont.appName)
                    .foregroundStyle(t.textPrimary)
                Text("Send links from any app to the right browser")
                    .font(OEFont.appSubtitle)
                    .foregroundStyle(t.textSecondary)
            }

            Spacer(minLength: 12)

            Toggle(isOn: $routingEngine.isEnabled) {
                Text(routingEngine.isEnabled ? "Routing" : "Paused")
                    .font(OEFont.switchLabel)
                    .tracking(OEFont.labelTracking(10))
                    .textCase(.uppercase)
                    .foregroundStyle(routingEngine.isEnabled ? t.accent : t.textTertiary)
            }
            .toggleStyle(OESwitchStyle())
            .accessibilityLabel("Route links through OpenElsewhere")
        }
    }

    // MARK: - Tab bar

    private var tabBar: some View {
        HStack(spacing: 2) {
            ForEach(SettingsTab.allCases) { tab in
                let active = tab == selectedTab
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.title)
                        .font(OEFont.tab)
                        .tracking(OEFont.labelTracking(11))
                        .textCase(.uppercase)
                        .foregroundStyle(active ? t.textPrimary : t.textTertiary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: OE.Radius.chip, style: .continuous)
                                .fill(active ? t.surfaceCardRaised : .clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(active ? [.isSelected] : [])
            }
            Spacer()
        }
    }

    // MARK: - Setup strip

    /// Exactly one prompt, highest priority first. The hint under the CTA
    /// tells the user how much is left so a queue of three does not feel
    /// endless when only one is visible.
    private func setupStrip(_ task: SetupTask) -> some View {
        let tone = task.tone
        return HStack(spacing: 14) {
            Image(systemName: task.symbol)
                .font(.system(size: 15))
                .foregroundStyle(tone.solid(t))
                .frame(width: 32, height: 32)
                .oeSurface(tone.tint(t), border: tone.line(t), radius: OE.Radius.chip)

            VStack(alignment: .leading, spacing: 2) {
                Text(task.stripTitle)
                    .font(OEFont.bannerTitle)
                    .foregroundStyle(t.textPrimary)
                Text(task.stripBody)
                    .font(OEFont.bannerBody)
                    .foregroundStyle(t.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 5) {
                Button(task.stripCTA) { resolve(task) }
                    .buttonStyle(OEFilledButtonStyle(tone: tone))
                    .fixedSize()

                Text(setupQueue.count > 1
                     ? "\(setupQueue.count - 1) more after this"
                     : "Last step")
                    .font(OEFont.hint)
                    .foregroundStyle(t.textTertiary)
            }
        }
        .padding(.horizontal, OE.Pad.banner)
        .padding(.vertical, 14)
        .oeSurface(tone.tint(t), border: tone.line(t), radius: OE.Radius.banner)
    }

    private func resolve(_ task: SetupTask) {
        switch task {
        case .defaultBrowser: setAsDefaultBrowser()
        case .automation:
            // Clearing the flag lets the strip advance now; the next blocked
            // AppleScript event sets it again if permission is still missing.
            automationPermissionDenied = false
            SystemSettings.openAutomation()
        case .profileHelper: showsHelperSheet = true
        case .firstRule:
            selectedTab = .rules
            withAnimation(OE.spring) { addEmptyRule() }
        }
    }

    // MARK: - General tab

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            OEEyebrow(text: "Fallback", theme: t)

            HStack(spacing: 12) {
                rowText("Default browser",
                        "Used when no rule matches the app a link came from.")
                Spacer(minLength: 8)
                destinationMenu(
                    browserBundleID: routingEngine.defaultBrowserBundleID,
                    profileDirectoryName: routingEngine.defaultProfileDirectoryName
                ) { destination in
                    routingEngine.defaultBrowserBundleID = destination.browserBundleID
                    routingEngine.defaultProfileDirectoryName = destination.profileDirectoryName
                }
            }
            .oeInsetRow(t)

            HStack(spacing: 12) {
                rowText("Launch at login", "Keep routing after a restart.")
                Spacer(minLength: 8)
                Toggle("", isOn: Binding(
                    get: { launchAtLogin },
                    set: { launchAtLogin = LaunchAtLogin.set($0) }
                ))
                .toggleStyle(OESwitchStyle(glows: false, labelGap: 0))
                .labelsHidden()
                .accessibilityLabel("Launch at login")
            }
            .oeInsetRow(t)
        }
    }

    // MARK: - Rules tab

    private var rulesTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                OEEyebrow(text: "Routing rules", theme: t)
                Spacer()
                Button("+ Add rule") {
                    withAnimation(OE.spring) { addEmptyRule() }
                }
                .buttonStyle(OESoftButtonStyle())
            }

            if routingEngine.rules.isEmpty {
                emptyState
            } else {
                ForEach($routingEngine.rules) { $rule in
                    ruleRow($rule)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.95).combined(with: .opacity),
                            removal: .scale(scale: 0.9).combined(with: .opacity)
                        ))
                }
            }
        }
    }

    /// A rule reads as a sentence — the direction is carried by "Links from …
    /// open in …", so the old arrow glyph is gone, and the destination menu
    /// folds browser and profile into one choice.
    private func ruleRow(_ rule: Binding<RoutingRule>) -> some View {
        HStack(spacing: 8) {
            if let icon = DestinationList.appIcon(for: rule.wrappedValue.sourceAppBundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 18, height: 18)
            }

            Text("Links from")
                .font(OEFont.sentence)
                .foregroundStyle(t.textSecondary)

            OEChipMenu(title: DestinationList.appName(for: rule.wrappedValue.sourceAppBundleID),
                       maxTitleWidth: 150) {
                ForEach(allApps) { app in
                    Button {
                        rule.wrappedValue.sourceAppBundleID = app.bundleID
                    } label: {
                        OEMenuRowLabel(name: app.name, icon: app.icon)
                    }
                }
            }

            Text("open in")
                .font(OEFont.sentence)
                .foregroundStyle(t.textSecondary)

            destinationMenu(browserBundleID: rule.wrappedValue.targetBrowserBundleID,
                            profileDirectoryName: rule.wrappedValue.profileDirectoryName) { destination in
                rule.wrappedValue.targetBrowserBundleID = destination.browserBundleID
                rule.wrappedValue.profileDirectoryName = destination.profileDirectoryName
            }

            Spacer(minLength: 4)

            Button {
                withAnimation(OE.springTight) {
                    routingEngine.removeRule(id: rule.wrappedValue.id)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
            }
            .buttonStyle(OETextButtonStyle(color: t.textTertiary, hoverColor: t.danger))
            .accessibilityLabel("Delete rule")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .oeSurface(t.surfaceInset, border: t.borderInset, radius: OE.Radius.row)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(nsImage: OEAppIcon.image)
                .resizable()
                .frame(width: 40, height: 40)
                .opacity(0.5)
                .oeGlow(t.accent.opacity(0.35), css: 24, scale: t.glowScale)

            Text("No rules yet")
                .font(OEFont.bannerTitle)
                .foregroundStyle(t.textPrimary)

            // Naming the current fallback beats stating the abstraction: the
            // user can see where links go today, so the offer is concrete.
            Text("Every link goes to \(fallbackLabel). Add a rule to send links from one app somewhere else.")
                .font(OEFont.rowSubtitle)
                .foregroundStyle(t.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 280)

            Button("Add your first rule") {
                withAnimation(OE.spring) { addEmptyRule() }
            }
            .buttonStyle(OESoftButtonStyle(glows: true, horizontalPadding: 14, verticalPadding: 8))
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 38)
        .padding(.horizontal, 24)
        .background(
            RoundedRectangle(cornerRadius: OE.Radius.row, style: .continuous)
                .fill(t.surfaceInset)
        )
        .overlay(
            RoundedRectangle(cornerRadius: OE.Radius.row, style: .continuous)
                .strokeBorder(t.borderHairline,
                              style: StrokeStyle(lineWidth: OE.hairline, dash: [4, 3]))
        )
    }

    // MARK: - About tab

    private var aboutTab: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                rowText(AppLinks.versionString, Capabilities.buildChannelDetail)
                Spacer(minLength: 8)
                Link("Release notes", destination: AppLinks.releaseNotes)
                    .font(OEFont.button)
                    .tracking(OEFont.labelTracking(11))
                    .foregroundStyle(t.accent)
            }
            .oeInsetRow(t)

            supportRow

            HStack(spacing: 18) {
                Link("Privacy", destination: AppLinks.privacy)
                Link("Source on GitHub", destination: AppLinks.repository)
                Link("Support", destination: AppLinks.support)
            }
            .font(OEFont.link)
            .foregroundStyle(t.accent)
            .padding(.horizontal, OE.Pad.rowX)
            .padding(.top, 2)
        }
        // Products are only needed by the tip jar, and only the App Store
        // build has one. Loading here rather than inside `supportRow` keeps it
        // to a single request when the row appears after products arrive.
        .task {
            guard !Capabilities.showsExternalDonationLink else { return }
            await tipJar.loadProducts()
        }
    }

    /// App Store: a StoreKit tip jar, because App Review restricts donation
    /// links for individual developers. Developer ID: the external link.
    @ViewBuilder
    private var supportRow: some View {
        if Capabilities.showsExternalDonationLink {
            HStack(spacing: 12) {
                rowText("Buy me a coffee", "One-off, no unlocks. Thank you either way.")
                Spacer(minLength: 8)
                Link(destination: AppLinks.buyMeACoffee) {
                    HStack(spacing: 6) {
                        Image(systemName: "cup.and.saucer.fill")
                        Text("Buy Me a Coffee")
                    }
                    .font(OEFont.button)
                    .foregroundStyle(t.textPrimary)
                    .padding(.horizontal, 11)
                    .padding(.vertical, 7)
                    .oeSurface(t.sponsorSoft, border: t.sponsorLine, radius: 9)
                }
                .buttonStyle(.plain)
            }
            .oeInsetRow(t)
        } else if !tipJar.products.isEmpty {
            // Hidden entirely when products fail to load — offline, or before
            // App Store Connect approves them — rather than showing "Loading…".
            HStack(spacing: 12) {
                rowText(tipJar.didTip ? "Thank you — that genuinely helps." : "Leave a tip",
                        "One-off, no unlocks. Thank you either way.")
                Spacer(minLength: 8)
                HStack(spacing: 6) {
                    ForEach(tipJar.products, id: \.id) { product in
                        Button(product.displayPrice) {
                            Task { await tipJar.purchase(product) }
                        }
                        .buttonStyle(OEChipButtonStyle(fill: t.sponsorSoft, border: t.sponsorLine))
                        .accessibilityLabel("\(product.displayName), \(product.displayPrice)")
                    }
                }
                .disabled(tipJar.isPurchasing)
            }
            .oeInsetRow(t)
        }
    }

    // MARK: - Shared pieces

    private func rowText(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(OEFont.rowTitle)
                .foregroundStyle(t.textPrimary)
            Text(subtitle)
                .font(OEFont.rowSubtitle)
                .foregroundStyle(t.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func destinationMenu(browserBundleID: String,
                                 profileDirectoryName: String?,
                                 onSelect: @escaping (Destination) -> Void) -> some View {
        let current = DestinationList.match(destinations,
                                            browserBundleID: browserBundleID,
                                            profileDirectoryName: profileDirectoryName)
        return OEChipMenu(title: current?.label
                          ?? DestinationList.label(browserBundleID: browserBundleID,
                                                   profileDirectoryName: profileDirectoryName),
                          icon: current?.icon) {
            ForEach(destinations) { destination in
                Button {
                    onSelect(destination)
                } label: {
                    OEMenuRowLabel(name: destination.label,
                                   icon: destination.profileDirectoryName == nil ? destination.icon : nil)
                }
            }
        }
    }

    // MARK: - Data

    private func loadData() {
        browsers = BrowserDiscovery.shared.installedBrowsers()
        allApps = BrowserDiscovery.shared.installedApps()
        destinations = DestinationList.build(browsers: browsers) {
            ProfileDiscovery.profiles(forBrowser: $0)
        }
        checkIfDefault()
        profileHelperInstalled = ProfileRoutingHelper.isInstalled
        launchAtLogin = LaunchAtLogin.isEnabled
    }

    private func consumePendingRoute() {
        if let tab = route.requestedTab {
            selectedTab = tab
            route.requestedTab = nil
        }
        if route.wantsNewRule {
            route.wantsNewRule = false
            if allApps.isEmpty { loadData() }
            withAnimation(OE.spring) { addEmptyRule() }
        }
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
        // Apple has not extended runtime default-handler APIs to sandboxed
        // apps, so the App Store build cannot do this itself. Opening a URL is
        // legal in the sandbox, so the user still lands one click from the
        // control — which is what the button now says.
        guard Capabilities.canSetDefaultBrowser else {
            SystemSettings.openDefaultBrowser()
            return
        }

        // LaunchServices' LSSetDefaultHandlerForURLScheme is deprecated since
        // macOS 12 and may silently no-op, so use the NSWorkspace API.
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
        routingEngine.addRule(
            sourceAppBundleID: sourceApp,
            targetBrowserBundleID: routingEngine.defaultBrowserBundleID,
            profileDirectoryName: routingEngine.defaultProfileDirectoryName
        )
    }
}
