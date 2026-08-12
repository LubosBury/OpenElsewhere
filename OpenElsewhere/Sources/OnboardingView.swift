import AppKit
import SwiftUI

/// First run: the setup tasks once, in order, so Settings opens clean.
///
/// Onboarding and the Settings setup strip read the same `SetupTask`
/// conditions, so anything skipped here is exactly what is still waiting in
/// Settings afterwards. Nothing is required — every step can be skipped, and
/// the flow never blocks the app.
///
/// Two things shape the interaction. OpenElsewhere is an `LSUIElement` agent,
/// so once System Settings takes focus there is no Dock icon to click back to:
/// the window floats above other apps instead of disappearing behind them.
/// And a step that hands off to System Settings does not advance on the click
/// — the work happens over there, so the step waits, shows what to look for,
/// and either detects completion or offers Continue.
struct OnboardingView: View {
    @EnvironmentObject var routingEngine: RoutingEngine
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @AppStorage(BrowserLauncher.automationDeniedDefaultsKey) private var automationPermissionDenied = false

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var scheme

    /// Resolved once, on appear. Recomputing per step would reshuffle the
    /// flow under the user's feet the moment they satisfy a condition.
    @State private var steps: [SetupTask] = []
    @State private var index = 0
    /// Steps whose CTA has been used and which are now waiting on the user to
    /// finish the job in System Settings.
    @State private var handedOff: Set<SetupTask> = []
    /// Quitting closes the window too, and that must not be mistaken for the
    /// user dismissing onboarding — otherwise quitting from the menu bar on
    /// first launch means never seeing it again.
    @State private var isTerminating = false

    private var t: OETheme { OETheme.resolve(scheme) }
    private var step: SetupTask? { steps.indices.contains(index) ? steps[index] : nil }
    private var isWaiting: Bool { step.map { handedOff.contains($0) } ?? false }

    var body: some View {
        ZStack {
            OEBackground(theme: t)

            VStack(spacing: 12) {
                appIconTile

                if let step {
                    Text(step.onboardingTitle)
                        .font(OEFont.onboardingTitle)
                        .foregroundStyle(t.textPrimary)
                        .multilineTextAlignment(.center)

                    Text(step.onboardingBody)
                        .font(OEFont.onboardingBody)
                        .foregroundStyle(t.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: 300)

                    if isWaiting, let instruction = step.followUpInstruction {
                        followUp(instruction)
                    }

                    Button(isWaiting ? "Continue" : step.onboardingCTA) {
                        isWaiting ? advance() : perform(step)
                    }
                    .buttonStyle(OEFilledButtonStyle(font: OEFont.buttonLarge,
                                                     fontSize: 12,
                                                     horizontalPadding: 20,
                                                     verticalPadding: 10))
                    .padding(.top, 8)

                    Button(isWaiting ? "Skip this step" : "Skip for now") { advance() }
                        .buttonStyle(OETextButtonStyle())
                }

                if steps.count > 1 { progressDots }
            }
            .padding(.top, 34)
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: OE.Size.onboardingWidth)
        .tint(t.accent)
        .overlay(alignment: .topLeading) { backButton }
        // Stay on top of System Settings. An agent app has no Dock icon, so a
        // window that falls behind is a window the user cannot get back to.
        .background(WindowAccessor { $0.level = .floating })
        .onAppear {
            steps = SetupTask.onboardingSteps(currentConditions())
            // Nothing left to ask for — a first run on a Mac that is already
            // set up should not open a window at all.
            if steps.isEmpty { finish() }
            NSApp.activate(ignoringOtherApps: true)
        }
        // Coming back from System Settings is the only moment the outcome of a
        // handed-off step can be observed.
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { @MainActor in recheckCurrentStep() }
        }
        .onReceive(NotificationCenter.default.publisher(
            for: NSApplication.willTerminateNotification)) { _ in
            isTerminating = true
        }
        // Closing the window with the red button is a decision too. Without
        // this, onboarding would reappear at every launch until the user
        // clicked all the way through it.
        .onDisappear {
            if !isTerminating { hasCompletedOnboarding = true }
        }
    }

    // MARK: - Pieces

    private var appIconTile: some View {
        Image(nsImage: OEAppIcon.image)
            .resizable()
            .frame(width: 44, height: 44)
            .frame(width: 64, height: 64)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .strokeBorder(t.accentLine, lineWidth: OE.hairline)
            )
            .oeGlow(t.accentLine, css: 34, scale: t.glowScale)
    }

    private func followUp(_ instruction: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(t.accent)
                .padding(.top, 1)
            Text(instruction)
                .font(OEFont.rowSubtitle)
                .foregroundStyle(t.textPrimary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: 300, alignment: .leading)
        .oeSurface(t.accentSoft, border: t.accentLine, radius: OE.Radius.chip)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var backButton: some View {
        if index > 0 {
            Button {
                withAnimation(OE.spring) { index -= 1 }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
            }
            .buttonStyle(OETextButtonStyle())
            .padding(.leading, 14)
            .padding(.top, 12)
            .accessibilityLabel("Back")
        }
    }

    private var progressDots: some View {
        HStack(spacing: 6) {
            ForEach(steps.indices, id: \.self) { i in
                Circle()
                    .fill(i == index ? t.accent : t.borderHairline)
                    .frame(width: 6, height: 6)
                    .oeGlow(i == index ? t.accent : .clear, css: 14, scale: t.glowScale)
            }
        }
        .padding(.top, 6)
        .animation(OE.easeBase, value: index)
    }

    // MARK: - Flow

    private func perform(_ step: SetupTask) {
        switch step {
        case .defaultBrowser:
            if Capabilities.canSetDefaultBrowser {
                setAsDefaultBrowser()
            } else {
                SystemSettings.openDefaultBrowser()
            }
            waitFor(step)
        case .automation:
            automationPermissionDenied = false
            SystemSettings.openAutomation()
            waitFor(step)
        case .profileHelper:
            advance()
        case .firstRule:
            // Hand the intent to Settings rather than mutating rules here: the
            // Rules tab has to be showing for the new row to make any sense.
            SettingsRoute.shared.requestNewRule()
            finish()
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func waitFor(_ step: SetupTask) {
        withAnimation(OE.spring) { _ = handedOff.insert(step) }
    }

    /// If the handed-off work is now done, move on without making the user
    /// confirm what the app can already see.
    private func recheckCurrentStep() {
        guard let step, handedOff.contains(step) else { return }
        if step == .defaultBrowser && isHandlingLinks() {
            advance()
        }
        // `.automation` has no queryable state — macOS offers no way to ask
        // whether a grant exists without sending an event — so it keeps
        // showing Continue.
    }

    private func advance() {
        if index + 1 < steps.count {
            withAnimation(OE.spring) { index += 1 }
        } else {
            finish()
        }
    }

    private func finish() {
        hasCompletedOnboarding = true
        dismiss()
    }

    private func currentConditions() -> SetupConditions {
        SetupConditions(isHandlingLinks: isHandlingLinks(),
                        automationPermissionDenied: automationPermissionDenied,
                        profileHelperInstalled: ProfileRoutingHelper.isInstalled,
                        hasRules: !routingEngine.rules.isEmpty)
    }

    private func isHandlingLinks() -> Bool {
        guard let httpsURL = URL(string: "https://example.com"),
              let defaultBrowserURL = NSWorkspace.shared.urlForApplication(toOpen: httpsURL),
              let defaultBundle = Bundle(url: defaultBrowserURL),
              let defaultBundleID = defaultBundle.bundleIdentifier else { return false }
        return defaultBundleID.lowercased() == (Bundle.main.bundleIdentifier ?? "").lowercased()
    }

    private func setAsDefaultBrowser() {
        let appURL = Bundle.main.bundleURL
        for scheme in ["http", "https"] {
            NSWorkspace.shared.setDefaultApplication(at: appURL,
                                                     toOpenURLsWithScheme: scheme) { error in
                if let error {
                    print("OpenElsewhere: setDefaultApplication(\(scheme)) failed: \(error.localizedDescription)")
                }
                Task { @MainActor in recheckCurrentStep() }
            }
        }
    }
}
