import AppKit
import SwiftUI

/// First run: the setup tasks once, in order, so Settings opens clean.
///
/// Onboarding and the Settings setup strip read the same `SetupTask`
/// conditions, so anything skipped here is exactly what is still waiting in
/// Settings afterwards. Nothing is required — every step can be skipped, and
/// the flow never blocks the app.
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

    private var t: OETheme { OETheme.resolve(scheme) }
    private var step: SetupTask? { steps.indices.contains(index) ? steps[index] : nil }

    var body: some View {
        ZStack {
            OEBackground(theme: t)

            VStack(spacing: 12) {
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

                    Button(step.onboardingCTA) { perform(step) }
                        .buttonStyle(OEFilledButtonStyle(font: OEFont.buttonLarge,
                                                         fontSize: 12,
                                                         horizontalPadding: 20,
                                                         verticalPadding: 10))
                        .padding(.top, 8)

                    Button("Skip for now") { advance() }
                        .buttonStyle(OETextButtonStyle())
                }

                if steps.count > 1 {
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
            }
            .padding(.top, 34)
            .padding(.horizontal, 30)
            .padding(.bottom, 26)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: OE.Size.onboardingWidth)
        .tint(t.accent)
        .onAppear {
            steps = SetupTask.onboardingSteps(currentConditions())
            // Nothing left to ask for — a first run on a Mac that is already
            // set up should not open a window at all.
            if steps.isEmpty { finish() }
            NSApp.activate(ignoringOtherApps: true)
        }
        // Closing the window with the red button is a decision too. Without
        // this, onboarding would reappear at every launch until the user
        // clicked all the way through it.
        .onDisappear { hasCompletedOnboarding = true }
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
            advance()
        case .automation:
            automationPermissionDenied = false
            SystemSettings.openAutomation()
            advance()
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
            }
        }
    }
}
