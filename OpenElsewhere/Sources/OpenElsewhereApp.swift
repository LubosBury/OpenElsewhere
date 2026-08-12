import SwiftUI

@main
struct OpenElsewhereApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var routingEngine = RoutingEngine.shared

    /// Read here, at launch, so the onboarding scene's launch behaviour can
    /// depend on it. `OnboardingView` writes the same key when it finishes.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(routingEngine)
        } label: {
            // Template-style menu bar icon: a simple compass glyph (SF Symbol
            // renders cleanly in the menu bar with the correct tint).
            Image(systemName: "location.north.line")
        }
        // `.window` rather than `.menu`: the panel shows real app icons and
        // the rule sentence, which NSMenu cannot lay out. It dismisses on
        // click-away instead of on selection — see `MenuBarView`.
        .menuBarExtraStyle(.window)

        Window("Welcome to OpenElsewhere", id: "onboarding") {
            OnboardingView()
                .environmentObject(routingEngine)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .restorationBehavior(.disabled)
        // The app is an LSUIElement agent, so nothing would otherwise put a
        // window on screen at first launch.
        .defaultLaunchBehavior(hasCompletedOnboarding ? .suppressed : .presented)

        Window("OpenElsewhere", id: "settings") {
            SettingsView()
                .environmentObject(routingEngine)
        }
        .defaultSize(width: 660, height: 540)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
    }
}
